// Minimal SFU video-conferencing server.
//
// Run with:
//   dart run bin\sfu_server.dart [--ip 0.0.0.0] [--ws-port 8080] [--rtp-base 50000]
//
// Open in a browser:    http://<host>:<ws-port>/
// Browsers connect to:  ws://<host>:<ws-port>/ws
//
// Wire protocol (JSON over WebSocket, one message per frame):
//   {"type":"join", "id":"alice", "name":"Alice"}            (client -> server)
//   {"type":"offer", "sdp":"..."}                              (client -> server)
//   {"type":"answer", "sdp":"..."}                             (server -> client)
//   {"type":"candidate", "candidate":"...", "sdpMid":"0", "sdpMLineIndex":0}
//                                                              (both directions)
//   {"type":"leave"}                                           (client -> server)
//   {"type":"peer-joined" | "peer-left", "id":"...", "name":"..."}
//                                                              (server -> client broadcast)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:pure_dart_webrtc_sfu_example/basic_sfu.dart';

Future<void> main(List<String> arguments) async {
  String ip = '0.0.0.0';
  int wsPort = 8080;
  int rtpBase = 50000;

  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--ip':
        ip = arguments[++i];
        break;
      case '--ws-port':
        wsPort = int.parse(arguments[++i]);
        break;
      case '--rtp-base':
        rtpBase = int.parse(arguments[++i]);
        break;
    }
  }

  final sfu = BasicSfu(
    address: InternetAddress(ip),
    basePort: rtpBase,
  );

  // Each WebSocket → one participant. We track the mapping here so we can
  // route signaling and broadcast peer-joined / peer-left events.
  final clients = <String, WebSocket>{};

  Future<void> broadcast(Map<String, Object?> msg, {String? except}) async {
    final encoded = jsonEncode(msg);
    for (final entry in clients.entries) {
      if (entry.key == except) continue;
      try {
        entry.value.add(encoded);
      } catch (_) {}
    }
  }

  sfu
    ..onParticipantJoined = (p) {
      print('[sfu] joined ${p.id} (${p.displayName ?? '-'}) on '
          '${p.transport.address.address}:${p.transport.port}');
      broadcast({
        'type': 'peer-joined',
        'id': p.id,
        'name': p.displayName,
      }, except: p.id);
    }
    ..onParticipantConnected = (p) {
      print('[sfu] ${p.id} DTLS connected');
    }
    ..onParticipantLeft = (p) {
      print('[sfu] left ${p.id}');
      broadcast({'type': 'peer-left', 'id': p.id});
    };

  final server = await HttpServer.bind(ip, wsPort);
  print('SFU signaling listening on ws://$ip:$wsPort/ws');
  print('Browser demo:               http://$ip:$wsPort/');
  print('SFU media base port: $rtpBase (one port per participant)');

  await for (final request in server) {
    if (request.uri.path == '/ws') {
      WebSocket ws;
      try {
        ws = await WebSocketTransformer.upgrade(request);
      } catch (e) {
        print('[ws] upgrade failed: $e');
        continue;
      }
      _handleClient(ws, sfu, clients, broadcast);
      continue;
    }

    if (request.method == 'GET' &&
        (request.uri.path == '/' || request.uri.path == '/index.html')) {
      request.response.headers.contentType =
          ContentType('text', 'html', charset: 'utf-8');
      request.response.write(_demoHtml);
      await request.response.close();
      continue;
    }

    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }
}

void _handleClient(
  WebSocket ws,
  BasicSfu sfu,
  Map<String, WebSocket> clients,
  Future<void> Function(Map<String, Object?>, {String? except}) broadcast,
) {
  String? participantId;

  void wireIceTrickle(SfuParticipant p) {
    p.pc.onIceCandidate = (cand) {
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
  }

  ws.listen((raw) async {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (msg['type']) {
        case 'join':
          participantId = msg['id'] as String;
          final name = msg['name'] as String?;
          clients[participantId!] = ws;
          final p = await sfu.addParticipant(participantId!, displayName: name);
          wireIceTrickle(p);
          // Tell the client we're ready; it will follow up with an offer.
          ws.add(jsonEncode({'type': 'joined', 'id': participantId}));
          break;

        case 'offer':
          final p = sfu.getParticipant(participantId ?? '');
          if (p == null) break;
          await p.pc.setRemoteDescription(
            RTCSessionDescription(RTCSdpType.offer, msg['sdp'] as String),
          );
          final answer = await p.pc.createAnswer();
          await p.pc.setLocalDescription(answer);
          ws.add(jsonEncode({'type': 'answer', 'sdp': answer.sdp}));
          break;

        case 'answer':
          // Supported for the legacy "server offers" flow.
          final p = sfu.getParticipant(participantId ?? '');
          if (p == null) break;
          await p.pc.setRemoteDescription(
            RTCSessionDescription(RTCSdpType.answer, msg['sdp'] as String),
          );
          break;

        case 'candidate':
          final p = sfu.getParticipant(participantId ?? '');
          if (p == null) break;
          final candStr = msg['candidate'] as String?;
          if (candStr == null) break;
          await p.pc.addIceCandidate(RTCIceCandidate(
            candidate: candStr,
            sdpMid: msg['sdpMid'] as String?,
            sdpMLineIndex: msg['sdpMLineIndex'] as int?,
          ));
          break;

        case 'leave':
          if (participantId != null) {
            await sfu.removeParticipant(participantId!);
            clients.remove(participantId);
          }
          await ws.close();
          break;
      }
    } catch (e, st) {
      print('[ws] error handling message: $e\n$st');
    }
  }, onDone: () async {
    if (participantId != null) {
      await sfu.removeParticipant(participantId!);
      clients.remove(participantId);
    }
  }, cancelOnError: true);
}

/// Tiny self-hosted browser demo. Captures camera+mic, publishes via the
/// SFU, and renders every other participant's stream.
const _demoHtml = r'''
<!doctype html>
<html><head><meta charset="utf-8"><title>pure_dart_webrtc SFU demo</title>
<style>
  body{font:14px sans-serif;margin:1em;background:#111;color:#eee}
  video{width:320px;background:#000;margin:.25em;border:1px solid #444}
  #log{font-family:monospace;white-space:pre-wrap;background:#000;padding:.5em;height:10em;overflow:auto}
  button,input{font:inherit;padding:.3em .6em}
</style></head><body>
<h2>pure_dart_webrtc SFU demo</h2>
<p>id: <input id="id" value="alice"> <button id="go">Join</button></p>
<div id="videos"></div>
<div id="log"></div>
<script>
const log = (...a) => {
  document.getElementById('log').textContent += a.join(' ') + '\n';
  console.log(...a);
};
const videos = document.getElementById('videos');

document.getElementById('go').onclick = async () => {
  const id = document.getElementById('id').value || 'alice';
  const ws = new WebSocket(`ws://${location.host}/ws`);
  await new Promise(r => ws.onopen = r);

  const local = await navigator.mediaDevices.getUserMedia({video:true, audio:true});
  const localV = document.createElement('video');
  localV.autoplay = true; localV.muted = true; localV.srcObject = local;
  videos.appendChild(localV);

  const pc = new RTCPeerConnection();
  for (const t of local.getTracks()) pc.addTrack(t, local);

  pc.onicecandidate = (e) => {
    if (!e.candidate) {
      ws.send(JSON.stringify({type:'candidate', candidate:null}));
      return;
    }
    ws.send(JSON.stringify({
      type:'candidate',
      candidate: e.candidate.candidate,
      sdpMid: e.candidate.sdpMid,
      sdpMLineIndex: e.candidate.sdpMLineIndex,
    }));
  };
  pc.ontrack = (e) => {
    let v = document.getElementById('v_' + e.streams[0].id);
    if (!v) {
      v = document.createElement('video');
      v.id = 'v_' + e.streams[0].id;
      v.autoplay = true; v.playsInline = true;
      videos.appendChild(v);
    }
    v.srcObject = e.streams[0];
  };
  pc.oniceconnectionstatechange = () => log('ice:', pc.iceConnectionState);
  pc.onconnectionstatechange = () => log('conn:', pc.connectionState);

  ws.onmessage = async (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.type === 'joined') {
      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      ws.send(JSON.stringify({type:'offer', sdp: offer.sdp}));
    } else if (msg.type === 'answer') {
      await pc.setRemoteDescription({type:'answer', sdp: msg.sdp});
      log('got answer');
    } else if (msg.type === 'candidate' && msg.candidate) {
      try {
        await pc.addIceCandidate({
          candidate: msg.candidate,
          sdpMid: msg.sdpMid,
          sdpMLineIndex: msg.sdpMLineIndex,
        });
      } catch (e) { log('addIceCandidate err:', e); }
    } else if (msg.type === 'peer-joined' || msg.type === 'peer-left') {
      log(msg.type, msg.id);
    }
  };

  ws.send(JSON.stringify({type:'join', id, name:id}));
  log('joined as', id);
};
</script></body></html>
''';
