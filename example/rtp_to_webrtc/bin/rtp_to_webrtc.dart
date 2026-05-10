// rtp-to-webrtc: bridge a plain RTP UDP source to a WebRTC browser.
//
// Architecture:
//
//   ffmpeg / GStreamer / asterisk / kamailio
//        │  plain RTP, no SRTP, no DTLS
//        ▼
//   UDP socket (this binary, --rtp-port)
//        │  on each packet: rewrite SSRC, push to sender
//        ▼
//   RTCRtpSender (existing pure_dart_webrtc stack)
//        │  SRTP-GCM encrypt + UDP send
//        ▼
//   browser
//
// This is the read-only direction (RTP -> WebRTC), which is what 99% of
// rtpengine-style integrations need to bootstrap. Reverse direction
// (WebRTC -> plain RTP) is one Stream subscription on the receiver and
// a `socket.send(bytes, host, port)` away — see TODO at the bottom.
//
// Send a test stream from ffmpeg:
//   ffmpeg -re -f lavfi -i testsrc=size=640x360:rate=30 \
//          -c:v libvpx -b:v 800k -f rtp \
//          -payload_type 96 -ssrc 0xCAFEBABE \
//          rtp://127.0.0.1:5004
//
// Then open http://<server>:8080 and click Play.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:pure_dart_webrtc/signal/sdp_v2.dart';
import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

Future<int> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('ip', defaultsTo: '127.0.0.1')
    ..addOption('http-port', defaultsTo: '8080')
    ..addOption('rtp-listen-ip', defaultsTo: '0.0.0.0')
    ..addOption('rtp-port', defaultsTo: '5004')
    ..addOption('webrtc-port', defaultsTo: '50000')
    ..addOption('codec',
        allowed: ['vp8', 'pcmu'],
        defaultsTo: 'vp8',
        help: 'Codec the upstream RTP carries (also picks the m= section).')
    ..addOption('payload-type',
        defaultsTo: '96',
        help: 'RTP payload type the upstream sends. Will be rewritten to the '
            'PT the browser negotiates.');

  late final ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    return 64;
  }

  final webIp = InternetAddress(parsed['ip'] as String);
  final httpPort = int.parse(parsed['http-port'] as String);
  final rtpListenIp = InternetAddress(parsed['rtp-listen-ip'] as String);
  final rtpPort = int.parse(parsed['rtp-port'] as String);
  final webrtcPort = int.parse(parsed['webrtc-port'] as String);
  final codecName = parsed['codec'] as String;
  final upstreamPt = int.parse(parsed['payload-type'] as String);

  _EchoSink? echoSink;
  final echoTo = parsed['echo-to'] as String?;
  if (echoTo != null) {
    final i = echoTo.lastIndexOf(':');
    if (i <= 0) {
      stderr.writeln('--echo-to must be host:port, got "$echoTo"');
      return 64;
    }
    final host = echoTo.substring(0, i);
    final port = int.tryParse(echoTo.substring(i + 1));
    if (port == null) {
      stderr.writeln('--echo-to port not numeric: $echoTo');
      return 64;
    }
    final addrs = await InternetAddress.lookup(host);
    if (addrs.isEmpty) {
      stderr.writeln('--echo-to host did not resolve: $host');
      return 64;
    }
    echoSink = _EchoSink(
      dst: addrs.first,
      port: port,
      pt: _parseIntFlexible(parsed['echo-pt'] as String?) ?? upstreamPt,
      ssrc: _parseIntFlexible(parsed['echo-ssrc'] as String?),
    );
    stdout.writeln('[bridge] echoing browser RTP to '
        '${addrs.first.address}:$port (pt=${echoSink.pt}'
        '${echoSink.ssrc != null ? " ssrc=0x${echoSink.ssrc!.toRadixString(16)}" : ""})');
  }

  // One UDP socket consumes plain RTP and broadcasts every packet to all
  // currently-connected browser senders (RTP fan-out, no demux).
  final rtpSocket = await RawDatagramSocket.bind(rtpListenIp, rtpPort);
  stdout.writeln('[bridge] listening for plain RTP on '
      '${rtpListenIp.address}:$rtpPort (codec=$codecName pt=$upstreamPt)');

  final clients = <_Client>[];

  // RTP fan-out from plain UDP to every connected client.
  rtpSocket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = rtpSocket.receive();
    if (dg == null) return;
    final pkt = dg.data;
    if (pkt.length < 12) return;
    for (final c in clients) {
      c.deliverInbound(pkt, upstreamPt: upstreamPt);
    }
  });

  // HTTP: page + WS signaling endpoint.
  final server = await HttpServer.bind(webIp, httpPort);
  stdout.writeln('[bridge] http://${webIp.address}:$httpPort');

  await for (final req in server) {
    if (req.uri.path == '/' || req.uri.path == '/index.html') {
      req.response.headers.contentType =
          ContentType('text', 'html', charset: 'utf-8');
      req.response.write(_demoHtml(codecName, fullDuplex: echoSink != null));
      await req.response.close();
      continue;
    }
    if (req.uri.path == '/ws') {
      try {
        final ws = await WebSocketTransformer.upgrade(req);
        final client = _Client(
          ws: ws,
          ip: webIp,
          webrtcPort: webrtcPort + clients.length,
          codecName: codecName,
          echoSink: echoSink,
        );
        clients.add(client);
        unawaited(client.run().whenComplete(() => clients.remove(client)));
      } catch (e) {
        stderr.writeln('[bridge] WS upgrade failed: $e');
      }
      continue;
    }
    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }

  rtpSocket.close();
  echoSink?.close();
  return 0;
}

int? _parseIntFlexible(String? s) {
  if (s == null) return null;
  final t = s.trim();
  if (t.startsWith('0x') || t.startsWith('0X')) {
    return int.parse(t.substring(2), radix: 16);
  }
  return int.parse(t);
}

/// Outbound (browser -> plain RTP) sink. One UDP socket shared across
/// all clients; per-packet PT/SSRC rewriting is config-driven.
class _EchoSink {
  final InternetAddress dst;
  final int port;
  final int pt;
  final int? ssrc;
  RawDatagramSocket? _sock;

  _EchoSink({
    required this.dst,
    required this.port,
    required this.pt,
    required this.ssrc,
  });

  Future<void> _ensure() async {
    _sock ??= await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  }

  Future<void> send(Uint8List rtp) async {
    if (rtp.length < 12) return;
    await _ensure();
    final out = Uint8List.fromList(rtp);
    out[1] = (out[1] & 0x80) | (pt & 0x7F);
    if (ssrc != null) {
      ByteData.sublistView(out).setUint32(8, ssrc!, Endian.big);
    }
    _sock!.send(out, dst, port);
  }

  void close() {
    _sock?.close();
    _sock = null;
  }
}

class _Client {
  final WebSocket ws;
  final InternetAddress ip;
  final int webrtcPort;
  final String codecName;
  final _EchoSink? echoSink;

  late final RTCPeerConnection pc;
  late final RTCRtpTransceiver transceiver;
  late final int announcedSsrc;
  int? _negotiatedPt;
  bool _connected = false;
  StreamSubscription<Uint8List>? _echoSub;

  _Client({
    required this.ws,
    required this.ip,
    required this.webrtcPort,
    required this.codecName,
    this.echoSink,
  });

  Future<void> run() async {
    final isVideo = codecName == 'vp8';
    pc = RTCPeerConnection(RTCConfiguration(
      defaultVideoCodecs: isVideo ? [Vp8Codec()] : const [],
      defaultAudioCodecs: !isVideo ? [PcmuCodec()] : const [],
    ));
    transceiver = pc.addTransceiver(
      trackOrKind: isVideo ? MediaKind.video : MediaKind.audio,
      direction: echoSink != null
          ? RTCRtpTransceiverDirection.sendrecv
          : RTCRtpTransceiverDirection.sendonly,
    );
    if (echoSink != null) {
      _echoSub = transceiver.receiver.onRtp.listen((rtp) {
        echoSink!.send(rtp);
      });
    }
    await pc.bind(ip, webrtcPort, announceAddress: ip);
    stdout.writeln('[bridge] client UDP $webrtcPort allocated');

    // Pick the SSRC up-front so we can advertise it in the offer and
    // rewrite inbound RTP to match. Without this Chrome would accept the
    // SDP but never fire `ontrack` for our sendonly stream.
    announcedSsrc = Random.secure().nextInt(0xFFFFFFFE) + 1;

    pc.onIceCandidate = (cand) {
      if (cand == null) {
        ws.add(jsonEncode({'type': 'candidate', 'candidate': null}));
        return;
      }
      ws.add(jsonEncode({
        'type': 'candidate',
        'candidate': cand.candidate,
        'sdpMid': cand.sdpMid,
        'sdpMLineIndex': cand.sdpMLineIndex,
      }));
    };

    pc.onConnectionStateChange = (s) {
      if (s == RTCPeerConnectionState.connected) {
        _connected = true;
        stdout.writeln('[bridge] DTLS connected on $webrtcPort, '
            'forwarding plain RTP -> SRTP');
      } else if (s == RTCPeerConnectionState.failed ||
          s == RTCPeerConnectionState.closed ||
          s == RTCPeerConnectionState.disconnected) {
        _connected = false;
      }
    };

    final offer = await pc.createOffer();
    final offerSdp = _injectSsrc(offer.sdp, announcedSsrc, isVideo: isVideo);
    await pc.setLocalDescription(
      RTCSessionDescription(RTCSdpType.offer, offerSdp),
    );
    ws.add(jsonEncode({'type': 'offer', 'sdp': offerSdp}));

    final done = Completer<void>();
    ws.listen((raw) async {
      try {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        switch (msg['type']) {
          case 'answer':
            final sdpText = msg['sdp'] as String;
            await pc.setRemoteDescription(
              RTCSessionDescription(RTCSdpType.answer, sdpText),
            );
            _negotiatedPt = _readFirstPayloadType(sdpText, isVideo: isVideo);
            stdout.writeln('[bridge] browser negotiated PT=$_negotiatedPt');
            break;
          case 'candidate':
            final cand = msg['candidate'];
            if (cand == null) break;
            await pc.addIceCandidate(RTCIceCandidate(
              candidate: cand as String,
              sdpMid: msg['sdpMid'] as String?,
              sdpMLineIndex: msg['sdpMLineIndex'] as int?,
            ));
            break;
        }
      } catch (e, st) {
        stderr.writeln('[bridge] WS error: $e\n$st');
      }
    }, onDone: () {
      _echoSub?.cancel();
      pc.close();
      done.complete();
    }, cancelOnError: true);

    return done.future;
  }

  /// Mutate [pkt] (in place is unsafe — we copy first) to the SSRC and
  /// PT this peer expects, then push through the SRTP-protected sender.
  void deliverInbound(Uint8List pkt, {required int upstreamPt}) {
    if (!_connected) return;
    final out = Uint8List.fromList(pkt);
    // RTP header: byte 1 low 7 bits = PT; bytes 8..12 = SSRC (big endian).
    final pt = _negotiatedPt;
    if (pt != null) {
      out[1] = (out[1] & 0x80) | (pt & 0x7F);
    }
    final bd = ByteData.sublistView(out);
    bd.setUint32(8, announcedSsrc, Endian.big);
    // Fire-and-forget; sender.send awaits the UDP write but we don't
    // gate the upstream RTP loop on it.
    unawaited(transceiver.sender.send(out));
  }
}

/// Pull the first payload type number out of the answer's first matching
/// m= line. Used to rewrite the upstream PT (which the browser may not
/// have advertised).
int? _readFirstPayloadType(String sdp, {required bool isVideo}) {
  final wanted = isVideo ? 'm=video' : 'm=audio';
  for (final line in sdp.split(RegExp(r'\r?\n'))) {
    if (!line.startsWith(wanted)) continue;
    final parts = line.split(' ');
    if (parts.length < 4) return null;
    return int.tryParse(parts[3]);
  }
  return null;
}

/// Add an `a=ssrc:<id> cname:...` line to the first matching m= section
/// so Chrome can wire up the inbound stream to a track before any RTP
/// arrives (avoids the "SDP has no SSRC" → no `ontrack` race).
String _injectSsrc(String sdp, int ssrc, {required bool isVideo}) {
  final session = parseSdp(sdp);
  final wantedKind = isVideo ? 'video' : 'audio';
  for (final m in session.mediaList) {
    if ((m['type'] as String?) != wantedKind) continue;
    final ssrcs = (m['ssrcs'] as List?) ?? <Map<String, dynamic>>[];
    ssrcs.add({'id': ssrc, 'attribute': 'cname', 'value': 'rtp-bridge'});
    ssrcs
        .add({'id': ssrc, 'attribute': 'msid', 'value': 'bridge bridge-track'});
    m['ssrcs'] = ssrcs;
    break;
  }
  return writeSdp(session);
}

String _demoHtml(String codec, {required bool fullDuplex}) {
  final kind = codec == 'vp8' ? 'video' : 'audio';
  final tag = codec == 'vp8'
      ? '<video id="m" autoplay playsinline muted></video>'
      : '<audio id="m" autoplay controls></audio>';
  // When the bridge is full-duplex the offer arrives as sendrecv, so the
  // browser side becomes sendrecv too and we attach a captured local
  // track. Without --echo-to the offer is sendonly and a recvonly
  // transceiver is enough.
  final dirJs = fullDuplex ? "'sendrecv'" : "'recvonly'";
  final captureJs = fullDuplex
      ? '''
  try {
    const local = await navigator.mediaDevices.getUserMedia(
      $kind === 'video' ? {video:true} : {audio:true});
    for (const t of local.getTracks()) {
      const tx = pc.getTransceivers().find(x => x.receiver.track.kind === t.kind);
      if (tx) await tx.sender.replaceTrack(t);
      else pc.addTrack(t, local);
    }
    log('captured local', local.getTracks().map(t=>t.kind).join(','));
  } catch (e) { log('gUM failed:', e); }
'''
      : '';
  return '''<!doctype html>
<html><head><meta charset="utf-8"><title>rtp-to-webrtc</title>
<style>
  body{font:14px sans-serif;margin:1em;background:#111;color:#eee}
  video,audio{width:480px;background:#000;border:1px solid #444}
  #log{font-family:monospace;white-space:pre-wrap;background:#000;padding:.5em;height:8em;overflow:auto;margin-top:.5em}
</style></head><body>
<h2>rtp-to-webrtc bridge ($codec, ${fullDuplex ? "full duplex" : "recv only"})</h2>
<button id="go">Play</button>
<div>$tag</div>
<div id="log"></div>
<script>
const log = (...a) => {
  document.getElementById('log').textContent += a.join(' ') + '\\n';
};
document.getElementById('go').onclick = async () => {
  const ws = new WebSocket(`ws://\${location.host}/ws`);
  await new Promise(r => ws.onopen = r);
  const pc = new RTCPeerConnection();
  pc.addTransceiver('$kind', {direction:$dirJs});
$captureJs
  pc.ontrack = (e) => {
    document.getElementById('m').srcObject =
        e.streams[0] || new MediaStream([e.track]);
    log('ontrack', e.track.kind);
  };
  pc.oniceconnectionstatechange = () => log('ice:', pc.iceConnectionState);
  pc.onicecandidate = (e) => {
    if (!e.candidate) return ws.send(JSON.stringify(
      {type:'candidate', candidate:null}));
    ws.send(JSON.stringify({
      type:'candidate', candidate:e.candidate.candidate,
      sdpMid:e.candidate.sdpMid, sdpMLineIndex:e.candidate.sdpMLineIndex,
    }));
  };
  ws.onmessage = async (ev) => {
    const m = JSON.parse(ev.data);
    if (m.type === 'offer') {
      await pc.setRemoteDescription({type:'offer', sdp:m.sdp});
      const ans = await pc.createAnswer();
      await pc.setLocalDescription(ans);
      ws.send(JSON.stringify({type:'answer', sdp:ans.sdp}));
      log('sent answer');
    } else if (m.type === 'candidate' && m.candidate) {
      try { await pc.addIceCandidate(m); } catch (e) { log('ice err:', e); }
    }
  };
};
</script></body></html>
''';
}
