// 04_server_answers_browser.dart
//
// Browser-initiated negotiation: the browser creates the offer with
// its camera/microphone, the Dart server answers as a recvonly sink
// and prints periodic getStats() snapshots so you can confirm RTP is
// flowing in.
//
// This is the WHIP-shaped pattern: clients push, the server ingests.
// See `example/whip_server` for a fuller, production-style version.
//
// Run:
//   dart run bin/04_server_answers_browser.dart --ip <LAN-IPv4>
//
// Then open http://<LAN-IPv4>:8081/ and click "Publish".

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

Future<int> main(List<String> args) async {
  final ip = InternetAddress(_arg(args, '--ip', '127.0.0.1'));
  final httpPort = int.parse(_arg(args, '--http-port', '8081'));
  final rtpBase = int.parse(_arg(args, '--rtp-base', '53000'));

  final server = await HttpServer.bind(InternetAddress.anyIPv4, httpPort);
  print('[srv] http://${ip.address}:$httpPort');

  var nextPort = rtpBase;

  await for (final req in server) {
    if (req.uri.path == '/' || req.uri.path == '/index.html') {
      req.response.headers.contentType =
          ContentType('text', 'html', charset: 'utf-8');
      req.response.write(_html);
      await req.response.close();
      continue;
    }
    if (req.uri.path == '/ws') {
      try {
        final ws = await WebSocketTransformer.upgrade(req);
        unawaited(_handle(ws, ip, nextPort++));
      } catch (e) {
        stderr.writeln('[srv] upgrade failed: $e');
      }
      continue;
    }
    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }
  return 0;
}

Future<void> _handle(WebSocket ws, InternetAddress ip, int port) async {
  final pc = RTCPeerConnection(RTCConfiguration(
    defaultVideoCodecs: [Vp8Codec()],
    defaultAudioCodecs: [PcmuCodec()],
  ));

  await pc.bind(ip, port, announceAddress: ip);
  print('[srv] new client on udp/$port');

  Timer? statsTimer;
  pc.onConnectionStateChange = (s) {
    print('[srv:$port] conn=${s.name}');
    if (s == RTCPeerConnectionState.connected) {
      statsTimer ??= Timer.periodic(const Duration(seconds: 2), (_) async {
        final r = await pc.getStats();
        final t = r.stats.values.firstWhere(
          (x) => x.type == 'inbound-rtp',
          orElse: () => RTCStats(type: '-', id: '-', values: const {}),
        );
        print('[srv:$port] inbound packets=${t.values['packetsReceived']} '
            'bytes=${t.values['bytesReceived']}');
      });
    }
    if (s == RTCPeerConnectionState.failed ||
        s == RTCPeerConnectionState.closed ||
        s == RTCPeerConnectionState.disconnected) {
      statsTimer?.cancel();
      statsTimer = null;
    }
  };
  pc.onIceCandidate = (c) {
    ws.add(jsonEncode({
      'type': 'candidate',
      'candidate': c?.candidate,
      'sdpMid': c?.sdpMid,
      'sdpMLineIndex': c?.sdpMLineIndex,
    }));
  };
  pc.onTrack = (e) {
    print('[srv:$port] ontrack kind=${e.track.kind}');
  };

  ws.listen((raw) async {
    try {
      final m = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (m['type']) {
        case 'offer':
          // 1) Accept the browser's offer.
          await pc.setRemoteDescription(
            RTCSessionDescription(RTCSdpType.offer, m['sdp'] as String),
          );
          // 2) Reply with our answer.
          final ans = await pc.createAnswer();
          await pc.setLocalDescription(ans);
          ws.add(jsonEncode({'type': 'answer', 'sdp': ans.sdp}));
          break;
        case 'candidate':
          final c = m['candidate'];
          if (c == null) break;
          await pc.addIceCandidate(RTCIceCandidate(
            candidate: c as String,
            sdpMid: m['sdpMid'] as String?,
            sdpMLineIndex: m['sdpMLineIndex'] as int?,
          ));
          break;
      }
    } catch (e) {
      stderr.writeln('[srv:$port] ws error: $e');
    }
  }, onDone: () {
    statsTimer?.cancel();
    pc.close();
    print('[srv:$port] disconnected');
  }, cancelOnError: true);
}

String _arg(List<String> args, String name, String fallback) {
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == name) return args[i + 1];
  }
  return fallback;
}

const _html = r'''
<!doctype html>
<meta charset="utf-8">
<title>browser-publishes</title>
<style>body{font:14px sans-serif;margin:1em;background:#111;color:#eee}
video{width:320px;background:#000;border:1px solid #444}
#log{font-family:monospace;white-space:pre-wrap;background:#000;padding:.5em;
height:10em;overflow:auto}</style>
<h2>Browser publishes, server ingests</h2>
<button id="go">Publish</button>
<div><video id="v" autoplay playsinline muted></video></div>
<div id="log"></div>
<script>
const log = (...a) => {
  document.getElementById('log').textContent += a.join(' ') + '\n';
};
document.getElementById('go').onclick = async () => {
  const stream = await navigator.mediaDevices.getUserMedia(
    {video:true, audio:true});
  document.getElementById('v').srcObject = stream;

  const ws = new WebSocket(`ws://${location.host}/ws`);
  await new Promise(r => ws.onopen = r);
  const pc = new RTCPeerConnection();
  for (const tr of stream.getTracks()) pc.addTrack(tr, stream);
  pc.oniceconnectionstatechange = () => log('ice', pc.iceConnectionState);
  pc.onconnectionstatechange = () => log('conn', pc.connectionState);
  pc.onicecandidate = (e) => ws.send(JSON.stringify({
    type:'candidate',
    candidate: e.candidate ? e.candidate.candidate : null,
    sdpMid: e.candidate?.sdpMid,
    sdpMLineIndex: e.candidate?.sdpMLineIndex,
  }));
  ws.onmessage = async (ev) => {
    const m = JSON.parse(ev.data);
    if (m.type === 'answer') {
      await pc.setRemoteDescription({type:'answer', sdp:m.sdp});
    } else if (m.type === 'candidate' && m.candidate) {
      await pc.addIceCandidate({candidate:m.candidate, sdpMid:m.sdpMid,
        sdpMLineIndex:m.sdpMLineIndex});
    }
  };
  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  ws.send(JSON.stringify({type:'offer', sdp:offer.sdp}));
};
</script>
''';
