// 03_server_offers_to_browser.dart
//
// Server-initiated negotiation: the Dart server creates the offer and
// the browser responds with the answer. This is the pattern used by
// SFU "play-from-disk" style endpoints, IVR systems, and anywhere the
// server already knows what media it wants to send.
//
// This example does NOT pump real media — it just demonstrates the
// signalling + ICE/DTLS shape. See `example/play_from_disk` for a
// version that adds a VP8 RTP pump.
//
// Run:
//   dart run bin/03_server_offers_to_browser.dart --ip <LAN-IPv4>
//
// Then open http://<LAN-IPv4>:8080/ in a browser and click "Connect".
//
// On Windows + Chrome, prefer your real LAN IPv4 over 127.0.0.1; the
// browser does not always pick the loopback adapter for ICE.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

Future<int> main(List<String> args) async {
  final ip = InternetAddress(_arg(args, '--ip', '127.0.0.1'));
  final httpPort = int.parse(_arg(args, '--http-port', '8080'));
  final rtpBase = int.parse(_arg(args, '--rtp-base', '52000'));

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

  // Sendonly: we offer to push media to the browser. We don't actually
  // pump packets in this example — see play_from_disk for that.
  pc.addTransceiver(
    trackOrKind: MediaKind.video,
    direction: RTCRtpTransceiverDirection.sendonly,
  );

  await pc.bind(ip, port, announceAddress: ip);
  print('[srv] new client on udp/$port');

  pc.onConnectionStateChange = (s) {
    print('[srv:$port] conn=${s.name}');
    if (s == RTCPeerConnectionState.failed ||
        s == RTCPeerConnectionState.closed) {
      ws.close();
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

  // 1) Server creates offer, sends it down the WS.
  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  ws.add(jsonEncode({'type': 'offer', 'sdp': offer.sdp}));

  // 2) Browser replies with an answer (and ICE candidates).
  ws.listen((raw) async {
    try {
      final m = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (m['type']) {
        case 'answer':
          await pc.setRemoteDescription(
            RTCSessionDescription(RTCSdpType.answer, m['sdp'] as String),
          );
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
    print('[srv:$port] disconnected');
    pc.close();
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
<title>server-offers</title>
<style>body{font:14px sans-serif;margin:1em;background:#111;color:#eee}
#log{font-family:monospace;white-space:pre-wrap;background:#000;padding:.5em;
height:12em;overflow:auto}</style>
<h2>Server offers, browser answers</h2>
<button id="go">Connect</button>
<div id="log"></div>
<script>
const log = (...a) => {
  document.getElementById('log').textContent += a.join(' ') + '\n';
};
document.getElementById('go').onclick = async () => {
  const ws = new WebSocket(`ws://${location.host}/ws`);
  await new Promise(r => ws.onopen = r);
  const pc = new RTCPeerConnection();
  pc.oniceconnectionstatechange = () => log('ice', pc.iceConnectionState);
  pc.onconnectionstatechange = () => log('conn', pc.connectionState);
  pc.onicecandidate = (e) => ws.send(JSON.stringify({
    type: 'candidate',
    candidate: e.candidate ? e.candidate.candidate : null,
    sdpMid: e.candidate?.sdpMid,
    sdpMLineIndex: e.candidate?.sdpMLineIndex,
  }));
  pc.ontrack = (e) => log('ontrack', e.track.kind);
  ws.onmessage = async (ev) => {
    const m = JSON.parse(ev.data);
    if (m.type === 'offer') {
      await pc.setRemoteDescription({type:'offer', sdp:m.sdp});
      const ans = await pc.createAnswer();
      await pc.setLocalDescription(ans);
      ws.send(JSON.stringify({type:'answer', sdp:ans.sdp}));
    } else if (m.type === 'candidate' && m.candidate) {
      await pc.addIceCandidate({candidate:m.candidate, sdpMid:m.sdpMid,
        sdpMLineIndex:m.sdpMLineIndex});
    }
  };
};
</script>
''';
