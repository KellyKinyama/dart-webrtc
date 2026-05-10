// Play-from-disk: pump a VP8 IVF file into a browser via WebRTC.
//
// Browser opens `/`, clicks Play. The page WebSockets in, receives an
// `offer` from this server containing a single sendonly VP8 video
// section, answers it, and the server starts pacing IVF frames at the
// file's nominal FPS, packetizing each frame as RTP and pushing it out
// over the SRTP transport.
//
// Usage:
//   dart run bin/play_from_disk.dart --ip 192.168.56.1 path/to/video.ivf
//
// The IVF file MUST be VP8. Use `bin/vpx_example.dart` to produce one
// from a raw RGB24 source.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:pure_dart_webrtc/signal/sdp_v2.dart';
import 'package:pure_dart_webrtc/src/codecs/vpx/vp8_rtp_payloader.dart';
import 'package:pure_dart_webrtc/vpx.dart';
import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

Future<int> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('ip', defaultsTo: '127.0.0.1')
    ..addOption('http-port', defaultsTo: '8080')
    ..addOption('rtp-port', defaultsTo: '50000');

  late final ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    return 64;
  }
  if (parsed.rest.length != 1) {
    stderr.writeln('Usage: play_from_disk [options] <input.ivf>\n'
        '${parser.usage}');
    return 64;
  }

  final ivfPath = parsed.rest.single;
  final ivfFile = File(ivfPath);
  if (!ivfFile.existsSync()) {
    stderr.writeln('IVF not found: $ivfPath');
    return 66;
  }

  // Quick sanity-check the header so we fail fast on a non-VP8 file.
  final probe = IvfReader.open(ivfFile);
  if (probe.codec != VpxCodec.vp8) {
    stderr.writeln('Only VP8 is supported (got ${probe.codec}).');
    probe.close();
    return 65;
  }
  stdout.writeln('[play] ${probe.width}x${probe.height} @ ${probe.fps} fps');
  probe.close();

  final ip = InternetAddress(parsed['ip'] as String);
  final httpPort = int.parse(parsed['http-port'] as String);
  final rtpPort = int.parse(parsed['rtp-port'] as String);

  final server = await HttpServer.bind(ip, httpPort);
  stdout.writeln('[play] http://${ip.address}:$httpPort');

  await for (final req in server) {
    if (req.uri.path == '/' || req.uri.path == '/index.html') {
      req.response.headers.contentType =
          ContentType('text', 'html', charset: 'utf-8');
      req.response.write(_demoHtml);
      await req.response.close();
      continue;
    }
    if (req.uri.path == '/ws') {
      try {
        final ws = await WebSocketTransformer.upgrade(req);
        // Each browser tab gets its own peer connection, transport, and
        // playback loop. The next browser is bound to rtpPort+1, +2, ...
        unawaited(_handleClient(ws, ip, rtpPort, ivfFile));
      } catch (e) {
        stderr.writeln('[play] WS upgrade failed: $e');
      }
      continue;
    }
    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }
  return 0;
}

int _nextPortOffset = 0;

Future<void> _handleClient(
  WebSocket ws,
  InternetAddress ip,
  int basePort,
  File ivfFile,
) async {
  final port = basePort + _nextPortOffset++;
  final pc = RTCPeerConnection(RTCConfiguration(
    defaultVideoCodecs: [Vp8Codec()],
  ));
  final transceiver = pc.addTransceiver(
    trackOrKind: MediaKind.video,
    direction: RTCRtpTransceiverDirection.sendonly,
  );
  await pc.bind(ip, port, announceAddress: ip);
  stdout.writeln('[play] new client on UDP $port');

  // Pick the SSRC up-front so the offer can advertise it. Browsers need
  // an `a=ssrc:` line in the m= section to fire `ontrack` for the
  // sendonly stream — without it Chrome accepts the SDP but never
  // demuxes any packets to a track.
  final ssrc = (Random.secure().nextInt(0xFFFFFFFE)) + 1;

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

  // Emit the offer immediately. Browser will answer.
  final offer = await pc.createOffer();
  final offerSdp = _addSendOnlySsrc(offer.sdp, ssrc, streamId: 'play');
  await pc.setLocalDescription(
    RTCSessionDescription(RTCSdpType.offer, offerSdp),
  );
  ws.add(jsonEncode({'type': 'offer', 'sdp': offerSdp}));

  Timer? pump;

  pc.onConnectionStateChange = (state) {
    if (state == RTCPeerConnectionState.connected && pump == null) {
      stdout.writeln('[play] DTLS connected, starting IVF pump');
      pump = _startIvfPump(transceiver.sender, ivfFile, ssrc);
    } else if (state == RTCPeerConnectionState.failed ||
        state == RTCPeerConnectionState.closed ||
        state == RTCPeerConnectionState.disconnected) {
      pump?.cancel();
      pump = null;
    }
  };

  ws.listen((raw) async {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (msg['type']) {
        case 'answer':
          await pc.setRemoteDescription(
            RTCSessionDescription(RTCSdpType.answer, msg['sdp'] as String),
          );
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
      stderr.writeln('[play] WS error: $e\n$st');
    }
  }, onDone: () async {
    pump?.cancel();
    pc.close();
    stdout.writeln('[play] client on $port disconnected');
  }, cancelOnError: true);
}

/// Read [ivfFile] in a loop, packetize each VP8 frame as RTP, and push
/// each packet through [sender]. Returns a [Timer] that callers can
/// cancel to stop playback.
Timer _startIvfPump(RTCRtpSender sender, File ivfFile, int ssrc) {
  final firstReader = IvfReader.open(ivfFile);
  final fps = firstReader.fps == 0 ? 30 : firstReader.fps;
  final period = Duration(microseconds: (1e6 / fps).round());
  // RTP timestamp ticks at 90 kHz for video.
  final tsStep = (90000 / fps).round();

  // Mutable state captured by the timer closure.
  IvfReader reader = firstReader;
  Iterator<IvfFrame> frames = reader.frames().iterator;
  var seq = Random.secure().nextInt(0x10000);
  var ts = Random.secure().nextInt(0x80000000);

  return Timer.periodic(period, (_) async {
    if (!frames.moveNext()) {
      // EOF — loop. IvfReader has no seek, so re-open from the start.
      reader.close();
      reader = IvfReader.open(ivfFile);
      frames = reader.frames().iterator;
      if (!frames.moveNext()) return;
    }
    final frame = frames.current;
    final pkts = packetizeVp8Frame(
      frame: frame.data,
      ssrc: ssrc,
      timestamp: ts & 0xFFFFFFFF,
      startSeq: seq,
    );
    seq = (seq + pkts.length) & 0xFFFF;
    ts = (ts + tsStep) & 0xFFFFFFFF;
    for (final p in pkts) {
      await sender.send(p.rawData);
    }
  });
}

/// Inject a randomly-chosen SSRC into the first video m= section so the
/// browser's transceiver fires `ontrack` for the incoming stream. Modern
/// Chrome happily accepts an SDP without `a=ssrc:` lines, but never
/// reports a track until packets with a known SSRC arrive — and by then
/// the browser may have GC'd the transceiver state. Declaring the SSRC
/// up-front avoids that race.
String _addSendOnlySsrc(String sdp, int ssrc, {required String streamId}) {
  final session = parseSdp(sdp);
  for (final m in session.mediaList) {
    if ((m['type'] as String?) != 'video') continue;
    final ssrcs = (m['ssrcs'] as List?) ?? <Map<String, dynamic>>[];
    final cname = 'play-$streamId';
    final track = '$streamId-video';
    ssrcs.add({'id': ssrc, 'attribute': 'cname', 'value': cname});
    ssrcs.add({'id': ssrc, 'attribute': 'msid', 'value': '$streamId $track'});
    m['ssrcs'] = ssrcs;
    break;
  }
  return writeSdp(session);
}

const _demoHtml = r'''
<!doctype html>
<html><head><meta charset="utf-8"><title>play-from-disk</title>
<style>
  body{font:14px sans-serif;margin:1em;background:#111;color:#eee}
  video{width:480px;background:#000;border:1px solid #444}
  #log{font-family:monospace;white-space:pre-wrap;background:#000;padding:.5em;height:8em;overflow:auto;margin-top:.5em}
</style></head><body>
<h2>play-from-disk (pure_dart_webrtc)</h2>
<button id="go">Play</button>
<div><video id="v" autoplay playsinline muted></video></div>
<div id="log"></div>
<script>
const log = (...a) => {
  document.getElementById('log').textContent += a.join(' ') + '\n';
};
document.getElementById('go').onclick = async () => {
  const ws = new WebSocket(`ws://${location.host}/ws`);
  await new Promise(r => ws.onopen = r);
  const pc = new RTCPeerConnection();
  pc.addTransceiver('video', {direction:'recvonly'});
  pc.ontrack = (e) => {
    document.getElementById('v').srcObject = e.streams[0] ||
        new MediaStream([e.track]);
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
