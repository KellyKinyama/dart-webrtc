// Minimal SFU video-conferencing server.
//
// Run with:
//   dart run bin\sfu_server.dart [--ip 0.0.0.0] [--ws-port 8080] [--rtp-base 50000]
//
// Browsers connect to:    ws://<host>:<ws-port>/ws
//
// Wire protocol (JSON over WebSocket, one message per frame):
//   {"type":"join", "id":"alice", "name":"Alice"}            (client → server)
//   {"type":"offer", "sdp":"..."}                              (server → client)
//   {"type":"answer", "sdp":"..."}                             (client → server)
//   {"type":"candidate", "candidate":"...", "sdpMid":"0", "sdpMLineIndex":0}
//                                                              (both directions)
//   {"type":"leave"}                                           (client → server)
//   {"type":"peer-joined" | "peer-left", "id":"...", "name":"..."}
//                                                              (server → client broadcast)

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
  print('SFU media base port: $rtpBase (one port per participant)');

  await for (final request in server) {
    if (request.uri.path != '/ws') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      continue;
    }

    WebSocket ws;
    try {
      ws = await WebSocketTransformer.upgrade(request);
    } catch (e) {
      print('[ws] upgrade failed: $e');
      continue;
    }

    _handleClient(ws, sfu, clients, broadcast);
  }
}

void _handleClient(
  WebSocket ws,
  BasicSfu sfu,
  Map<String, WebSocket> clients,
  Future<void> Function(Map<String, Object?>, {String? except}) broadcast,
) {
  String? participantId;

  Future<void> sendOffer(SfuParticipant p) async {
    final offer = await p.pc.createOffer();
    await p.pc.setLocalDescription(offer);
    ws.add(jsonEncode({'type': 'offer', 'sdp': offer.sdp}));

    // Forward host candidates as they get fired.
    p.pc.onIceCandidate = (cand) {
      if (cand == null) return;
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
          await sendOffer(p);
          break;

        case 'answer':
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
