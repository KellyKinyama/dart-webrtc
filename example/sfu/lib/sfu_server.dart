// Reusable SFU signaling server. The CLI entry point in
// `bin/sfu_server.dart` is a thin wrapper around [runSfuServer].
//
// Exposed so integration tests can boot the full HTTP + WebSocket
// stack on an ephemeral port.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

import 'basic_sfu.dart';

/// Result of [runSfuServer] — keeps the bound HTTP server and the SFU
/// alive so callers can shut both down cleanly.
class SfuServerHandle {
  final HttpServer http;
  final BasicSfu sfu;

  SfuServerHandle(this.http, this.sfu);

  int get port => http.port;

  Future<void> close() async {
    await sfu.close();
    await http.close(force: true);
  }
}

/// Boot the SFU's HTTP + WebSocket signaling stack.
///
/// Pass `port: 0` to let the OS pick a free port; read the actual port
/// back from `result.port`.
Future<SfuServerHandle> runSfuServer({
  String ip = '0.0.0.0',
  int port = 8080,
  int rtpBase = 50000,
  bool quiet = false,
}) async {
  final sfu = BasicSfu(
    address: InternetAddress(ip),
    basePort: rtpBase,
  );

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

  void log(String msg) {
    if (!quiet) print(msg);
  }

  sfu
    ..onParticipantJoined = (p) {
      log('[sfu] joined ${p.id} (${p.displayName ?? '-'}) on '
          '${p.transport.address.address}:${p.transport.port}');
      broadcast({
        'type': 'peer-joined',
        'id': p.id,
        'name': p.displayName,
      }, except: p.id);
    }
    ..onParticipantConnected = (p) {
      log('[sfu] ${p.id} DTLS connected');
    }
    ..onParticipantLeft = (p) {
      log('[sfu] left ${p.id}');
      broadcast({'type': 'peer-left', 'id': p.id});
      broadcast({'type': 'renegotiate', 'reason': 'peer-left:${p.id}'});
    }
    ..onProducersChanged = (producerId, newStreams) {
      log('[sfu] producer $producerId added ${newStreams.length} stream(s); '
          'asking other peers to renegotiate');
      broadcast(
        {'type': 'renegotiate', 'reason': 'new-producer:$producerId'},
        except: producerId,
      );
    };

  final server = await HttpServer.bind(ip, port);

  // Fire-and-forget the request loop; tests close the server to stop it.
  unawaited(_serve(server, sfu, clients, broadcast, log));

  return SfuServerHandle(server, sfu);
}

Future<void> _serve(
  HttpServer server,
  BasicSfu sfu,
  Map<String, WebSocket> clients,
  Future<void> Function(Map<String, Object?>, {String? except}) broadcast,
  void Function(String) log,
) async {
  await for (final request in server) {
    if (request.uri.path == '/ws') {
      WebSocket ws;
      try {
        ws = await WebSocketTransformer.upgrade(request);
      } catch (e) {
        log('[ws] upgrade failed: $e');
        continue;
      }
      _handleClient(ws, sfu, clients, broadcast, log);
      continue;
    }

    if (request.method == 'GET' &&
        (request.uri.path == '/' || request.uri.path == '/index.html')) {
      request.response.headers.contentType =
          ContentType('text', 'html', charset: 'utf-8');
      request.response.write(demoHtml);
      await request.response.close();
      continue;
    }

    if (request.method == 'GET' && request.uri.path == '/health') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'status': 'ok',
        'participants': sfu.participants.length,
      }));
      await request.response.close();
      continue;
    }

    if (request.method == 'GET' && request.uri.path == '/stats') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(buildStatsJson(sfu)));
      await request.response.close();
      continue;
    }

    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }
}

/// JSON snapshot returned by `GET /stats`. Exposed so tests can assert
/// the same shape.
Map<String, Object?> buildStatsJson(BasicSfu sfu) => {
      'participants': [
        for (final p in sfu.participants)
          {
            'id': p.id,
            'name': p.displayName,
            'port': p.transport.port,
            'connectionState': p.pc.connectionState.name,
            'producers': [
              for (final s in sfu.producersOf(p.id))
                {
                  'kind': s.kind,
                  'mid': s.mid,
                  'primarySsrc': s.primarySsrc,
                  'rtxSsrc': s.rtxSsrc,
                  'cname': s.cname,
                  'msidStream': s.msidStream,
                  'msidTrack': s.msidTrack,
                }
            ],
          }
      ],
      'forwarding': {
        'rtpForwarded': sfu.stats.rtpForwarded,
        'rtcpForwarded': sfu.stats.rtcpForwarded,
        'rtpDropped': sfu.stats.rtpDropped,
        'rtcpDropped': sfu.stats.rtcpDropped,
        'ssrcRewrites': sfu.stats.ssrcRewrites,
        'rtxForwarded': sfu.stats.rtxForwarded,
        'pliSent': sfu.stats.pliSent,
      },
    };

void _handleClient(
  WebSocket ws,
  BasicSfu sfu,
  Map<String, WebSocket> clients,
  Future<void> Function(Map<String, Object?>, {String? except}) broadcast,
  void Function(String) log,
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
          ws.add(jsonEncode({'type': 'joined', 'id': participantId}));
          break;

        case 'offer':
          final p = sfu.getParticipant(participantId ?? '');
          if (p == null) break;
          final sdpText = msg['sdp'] as String;
          sfu.learnSsrcMappingFromOffer(participantId!, sdpText);
          await p.pc.setRemoteDescription(
            RTCSessionDescription(RTCSdpType.offer, sdpText),
          );
          final answer = await p.pc.createAnswer();
          await p.pc.setLocalDescription(answer);
          final augmented = sfu.augmentAnswerSdp(participantId!, answer.sdp);
          ws.add(jsonEncode({'type': 'answer', 'sdp': augmented}));
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
      log('[ws] error handling message: $e\n$st');
    }
  }, onDone: () async {
    if (participantId != null) {
      await sfu.removeParticipant(participantId!);
      clients.remove(participantId);
    }
  }, cancelOnError: true);
}

/// Tiny self-hosted browser demo — captures camera+mic, publishes via
/// the SFU, and renders every other participant's stream.
const demoHtml = r'''
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
<pre id="stats" style="background:#000;padding:.5em;font-size:12px;max-height:14em;overflow:auto"></pre>
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
    } else if (msg.type === 'renegotiate') {
      log('renegotiate:', msg.reason || '(no reason)');
      try {
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        ws.send(JSON.stringify({type:'offer', sdp: offer.sdp}));
      } catch (e) { log('renegotiate err:', e); }
    } else if (msg.type === 'peer-joined' || msg.type === 'peer-left') {
      log(msg.type, msg.id);
    }
  };

  ws.send(JSON.stringify({type:'join', id, name:id}));
  log('joined as', id);
  const statsEl = document.getElementById('stats');
  setInterval(async () => {
    try {
      const r = await fetch('/stats');
      const j = await r.json();
      statsEl.textContent = JSON.stringify(j, null, 2);
    } catch (e) {}
  }, 2000);
};
</script></body></html>
''';
