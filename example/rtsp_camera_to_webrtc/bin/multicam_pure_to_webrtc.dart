// multicam_pure_to_webrtc — pure-Dart edition of the multi-camera viewer.
// No GStreamer, no ffmpeg, no native deps. One PeerConnection per
// browser tab, N sendonly H.264 transceivers.
//
// Each camera is fed by an [RtspClient] running an RTSP/1.0 session
// over TCP-interleaved transport (RFC 7826 §14). H.264 NALUs are
// reassembled (FU-A, STAP-A) and grouped into Access Units, then
// re-packetized per viewer with `packetizeH264AccessUnit` and shipped
// out as SRTP via `pure_dart_webrtc`.
//
// Usage:
//   dart run bin/multicam_pure_to_webrtc.dart \
//       --ip 192.168.56.1 \
//       --cam Front=rtsp://admin:pw@10.0.0.10/Streaming/Channels/101 \
//       --cam Back=rtsp://admin:pw@10.0.0.11/Streaming/Channels/101
//
// Bare positional URLs become cam0, cam1, ...:
//   dart run bin/multicam_pure_to_webrtc.dart --ip 192.168.56.1 \
//       rtsp://.../1 rtsp://.../2

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:pure_dart_webrtc/signal/sdp_v2.dart' as sdpv2;
import 'package:pure_dart_webrtc/src/codecs/h264/h264_rtp.dart';
import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

import 'package:pure_dart_webrtc_rtsp_camera_to_webrtc_example/rtsp_pure.dart';

class _Cam {
  final String name;
  final String url;
  _Cam(this.name, this.url);
}

Future<int> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('ip', defaultsTo: '127.0.0.1')
    ..addOption('http-port', defaultsTo: '8080')
    ..addOption('rtp-port', defaultsTo: '50000')
    ..addOption('profile-level-id', defaultsTo: '42e01f')
    ..addMultiOption('cam',
        abbr: 'c',
        help: 'NAME=rtsp://... (repeatable). Bare URLs become cam0, cam1, ...');

  late final ArgResults opts;
  try {
    opts = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    return 64;
  }

  final cams = <_Cam>[];
  for (final entry in (opts['cam'] as List<String>)) {
    final eq = entry.indexOf('=');
    if (eq <= 0) {
      stderr.writeln('--cam needs NAME=URL form: $entry');
      return 64;
    }
    cams.add(
        _Cam(entry.substring(0, eq).trim(), entry.substring(eq + 1).trim()));
  }
  for (final url in opts.rest) {
    cams.add(_Cam('cam${cams.length}', url));
  }
  if (cams.isEmpty) {
    stderr.writeln('At least one camera required.\n${parser.usage}');
    return 64;
  }

  final ip = InternetAddress(opts['ip'] as String);
  final httpPort = int.parse(opts['http-port'] as String);
  final rtpPort = int.parse(opts['rtp-port'] as String);
  final profileLevelId = opts['profile-level-id'] as String;

  // One RtspClient + AuHub per camera. runForever() handles reconnects
  // (back-off 3 s) so a flaky camera doesn't take everyone else down.
  final hubs = <AuHub>[];
  for (final cam in cams) {
    final hub = AuHub(name: cam.name);
    hubs.add(hub);
    final client = RtspClient(url: cam.url, hub: hub, logTag: cam.name);
    unawaited(client.runForever());
  }

  unawaited(_runHttpServer(
    ip: ip,
    port: httpPort,
    rtpBasePort: rtpPort,
    cams: cams,
    hubs: hubs,
    profileLevelId: profileLevelId,
  ));

  stdout.writeln('[main] viewer: http://${ip.address}:$httpPort');
  stdout.writeln('[main] cameras: ${cams.map((c) => c.name).join(', ')}');
  await Completer<void>().future;
  return 0;
}

// ---------------------------------------------------------------------------
// HTTP signalling + WebRTC viewer
// ---------------------------------------------------------------------------

int _nextWebrtcPortOffset = 0;

Future<void> _runHttpServer({
  required InternetAddress ip,
  required int port,
  required int rtpBasePort,
  required List<_Cam> cams,
  required List<AuHub> hubs,
  required String profileLevelId,
}) async {
  final server = await HttpServer.bind(ip, port);
  await for (final req in server) {
    if (req.uri.path == '/' || req.uri.path == '/index.html') {
      req.response.headers.contentType =
          ContentType('text', 'html', charset: 'utf-8');
      req.response.write(_renderHtml(cams));
      await req.response.close();
      continue;
    }
    if (req.uri.path == '/ws') {
      try {
        final ws = await WebSocketTransformer.upgrade(req);
        unawaited(_handleViewer(
          ws: ws,
          ip: ip,
          basePort: rtpBasePort,
          cams: cams,
          hubs: hubs,
          profileLevelId: profileLevelId,
        ));
      } catch (e) {
        stderr.writeln('[webrtc] WS upgrade failed: $e');
      }
      continue;
    }
    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }
}

Future<void> _handleViewer({
  required WebSocket ws,
  required InternetAddress ip,
  required int basePort,
  required List<_Cam> cams,
  required List<AuHub> hubs,
  required String profileLevelId,
}) async {
  final port = basePort + _nextWebrtcPortOffset++;
  final pc = RTCPeerConnection(RTCConfiguration(
    defaultVideoCodecs: [H264Codec(profileLevelId: profileLevelId)],
  ));

  final txs = <RTCRtpTransceiver>[];
  final ssrcs = <int>[];
  for (var i = 0; i < cams.length; i++) {
    txs.add(pc.addTransceiver(
      trackOrKind: MediaKind.video,
      direction: RTCRtpTransceiverDirection.sendonly,
    ));
    ssrcs.add(Random.secure().nextInt(0xFFFFFFFE) + 1);
  }

  await pc.bind(ip, port, announceAddress: ip);
  stdout.writeln('[webrtc] new viewer on UDP $port — ${cams.length} cameras');

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

  final offer = await pc.createOffer();
  final offerSdp = _addPerCameraSsrcs(offer.sdp, cams, ssrcs);
  await pc.setLocalDescription(
    RTCSessionDescription(RTCSdpType.offer, offerSdp),
  );
  ws.add(jsonEncode({
    'type': 'offer',
    'sdp': offerSdp,
    'cams': [
      for (var i = 0; i < cams.length; i++)
        {'name': cams[i].name, 'mid': txs[i].mid},
    ],
  }));

  final subs = <StreamSubscription<AccessUnit>>[];

  pc.onConnectionStateChange = (state) {
    if (state == RTCPeerConnectionState.connected && subs.isEmpty) {
      stdout.writeln('[webrtc] DTLS connected on $port — fanning out');
      for (var i = 0; i < cams.length; i++) {
        final tx = txs[i];
        final ssrc = ssrcs[i];
        final hub = hubs[i];
        final camName = cams[i].name;
        var pt = 102;
        for (final c in tx.codecs) {
          if (c is H264Codec) {
            pt = c.payloadType;
            break;
          }
        }
        var seq = Random.secure().nextInt(0x10000);
        final tsBase = Random.secure().nextInt(0x80000000);
        var auCounter = 0;
        subs.add(hub.subscribe().listen((au) async {
          // Synthetic 30 fps clock — replace with camera RTCP-SR if you
          // need frame-accurate timing.
          final ts = (tsBase + auCounter * 3000) & 0xffffffff;
          auCounter++;
          final pkts = packetizeH264AccessUnit(
            nalus: au.nalus,
            ssrc: ssrc,
            timestamp: ts,
            startSeq: seq,
            payloadType: pt,
          );
          seq = (seq + pkts.length) & 0xffff;
          for (final p in pkts) {
            await tx.sender.send(p.rawData);
          }
        }, onError: (Object e) {
          stderr.writeln('[webrtc/$camName] $e');
        }));
      }
    } else if (state == RTCPeerConnectionState.failed ||
        state == RTCPeerConnectionState.closed ||
        state == RTCPeerConnectionState.disconnected) {
      for (final s in subs) {
        s.cancel();
      }
      subs.clear();
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
      stderr.writeln('[webrtc] WS error: $e\n$st');
    }
  }, onDone: () async {
    for (final s in subs) {
      s.cancel();
    }
    pc.close();
    stdout.writeln('[webrtc] viewer on $port disconnected');
  }, cancelOnError: true);
}

String _addPerCameraSsrcs(String sdp, List<_Cam> cams, List<int> ssrcs) {
  final session = sdpv2.parseSdp(sdp);
  var idx = 0;
  for (final m in session.mediaList) {
    if ((m['type'] as String?) != 'video') continue;
    if (idx >= cams.length) break;
    final cam = cams[idx];
    final ssrc = ssrcs[idx];
    idx++;
    final list = (m['ssrcs'] as List?) ?? <Map<String, dynamic>>[];
    final cname = 'multicam-${cam.name}';
    final streamId = cam.name;
    final trackId = '${cam.name}-video';
    list.add({'id': ssrc, 'attribute': 'cname', 'value': cname});
    list.add({'id': ssrc, 'attribute': 'msid', 'value': '$streamId $trackId'});
    m['ssrcs'] = list;
  }
  return sdpv2.writeSdp(session);
}

String _renderHtml(List<_Cam> cams) {
  final tiles = StringBuffer();
  for (final c in cams) {
    tiles.write('<div class="tile" data-cam="${c.name}">'
        '<h3>${c.name}</h3>'
        '<video id="v-${c.name}" autoplay playsinline muted></video>'
        '</div>');
  }
  return _htmlShell.replaceAll('<!--TILES-->', tiles.toString());
}

const _htmlShell = r'''
<!doctype html>
<html><head><meta charset="utf-8"><title>multicam (pure dart)</title>
<style>
  body{font:14px sans-serif;margin:1em;background:#111;color:#eee}
  .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(360px,1fr));gap:.75em}
  .tile{background:#000;border:1px solid #333;padding:.4em}
  .tile h3{margin:.2em 0 .4em;font-size:13px;color:#9cf}
  video{width:100%;background:#000;display:block}
  #log{font-family:monospace;white-space:pre-wrap;background:#000;padding:.5em;height:8em;overflow:auto;margin-top:.75em}
  button{font:14px sans-serif;padding:.4em 1em;margin-bottom:.5em}
</style></head><body>
<h2>multi-camera viewer (pure dart)</h2>
<button id="go">Connect</button>
<div class="grid"><!--TILES--></div>
<div id="log"></div>
<script>
const log = (...a) => {
  document.getElementById('log').textContent += a.join(' ') + '\n';
};
document.getElementById('go').onclick = async () => {
  const ws = new WebSocket(`ws://${location.host}/ws`);
  await new Promise(r => ws.onopen = r);
  const pc = new RTCPeerConnection();
  let cams = [];
  pc.ontrack = (e) => {
    const stream = e.streams[0];
    if (!stream) { log('ontrack: no stream'); return; }
    const v = document.getElementById('v-' + stream.id);
    if (v) {
      v.srcObject = stream;
      log('attached', e.track.kind, '→', stream.id);
    } else {
      log('orphan track for stream', stream.id);
    }
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
      cams = m.cams || [];
      log('offer with', cams.length, 'camera(s)');
      for (let i = 0; i < cams.length; i++) {
        pc.addTransceiver('video', {direction:'recvonly'});
      }
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
