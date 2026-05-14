// WebSocket + JSON signaling for the ion-style SFU.
//
// Protocol (one message per JSON object, TEXT frames):
//
//   client -> server  {"type":"join",   "sid":"room",  "uid":"alice"}
//   client -> server  {"type":"offer",  "target":"pub","sdp":"..."}
//   server -> client  {"type":"answer", "target":"pub","sdp":"..."}
//
//   server -> client  {"type":"offer",  "target":"sub","sdp":"..."}
//   client -> server  {"type":"answer", "target":"sub","sdp":"..."}
//
//   either direction  {"type":"trickle","target":"pub|sub",
//                      "candidate":"...", "sdpMid":"0", "sdpMLineIndex":0}
//
//   server -> client  {"type":"peer-joined", "uid":"bob"}
//   server -> client  {"type":"peer-left",   "uid":"bob"}
//
// One Peer (= Publisher PC + Subscriber PC) per WebSocket. The server
// reissues `target:"sub"` offers whenever a producer joins/leaves the
// room.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';

class IonSfuServerHandle {
  final HttpServer http;
  final Sfu sfu;
  IonSfuServerHandle(this.http, this.sfu);

  int get port => http.port;

  Future<void> close() async {
    await sfu.close();
    await http.close(force: true);
  }
}

Future<IonSfuServerHandle> runIonStyleSfuServer({
  String ip = '0.0.0.0',
  int port = 9090,
  int rtpBase = 51000,
  String? announceIp,
  bool quiet = false,
}) async {
  final bindAddr = InternetAddress(ip);
  final advertisedIp = announceIp ??
      ((ip == '0.0.0.0' || ip == '::' || ip.isEmpty)
          ? (await _firstNonLoopbackIPv4() ?? '127.0.0.1')
          : ip);

  final sfu = Sfu(WebRTCTransportConfig(
    bindAddress: bindAddr,
    rtpBasePort: rtpBase,
    announceAddress: InternetAddress(advertisedIp),
    defaultVideoCodecs: [Vp8Codec()],
    defaultAudioCodecs: [PcmuCodec()],
  ));

  final http = await HttpServer.bind(bindAddr, port);
  if (!quiet) {
    stdout.writeln('ion-style SFU listening on '
        'ws://$advertisedIp:${http.port}/ws/<sessionId>');
    stdout.writeln('UDP transports start at port $rtpBase '
        '(host candidate: $advertisedIp).');
  }

  http.listen((req) {
    // Permissive CORS so the static page (e.g. http://127.0.0.1:8000)
    // can hit /stats and /metrics from a different origin.
    req.response.headers.set('Access-Control-Allow-Origin', '*');
    req.response.headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
    req.response.headers.set('Access-Control-Allow-Headers', '*');
    if (req.method == 'OPTIONS') {
      req.response.statusCode = HttpStatus.noContent;
      req.response.close();
      return;
    }
    if (req.uri.path == '/stats' || req.uri.path == '/metrics') {
      final snap = snapshotSfu(sfu);
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(snap.toJson()));
      req.response.close();
      return;
    }
    if (req.uri.path.startsWith('/ws/')) {
      final sid = req.uri.path.substring('/ws/'.length);
      if (sid.isEmpty) {
        req.response.statusCode = HttpStatus.badRequest;
        req.response.close();
        return;
      }
      WebSocketTransformer.upgrade(req).then(
        (ws) => _IonPeerSession(ws, sfu, sid, quiet: quiet).run(),
        onError: (e) {
          if (!quiet) stderr.writeln('ws upgrade error: $e');
        },
      );
      return;
    }
    req.response.statusCode = HttpStatus.notFound;
    req.response.close();
  });

  return IonSfuServerHandle(http, sfu);
}

/// Glue between one WebSocket and one [Peer]. Owns the lifetime of both.
class _IonPeerSession {
  final WebSocket ws;
  final Sfu sfu;
  final String sid;
  final bool quiet;

  Peer? _peer;
  String? _uid;

  _IonPeerSession(this.ws, this.sfu, this.sid, {this.quiet = false});

  Future<void> run() async {
    ws.listen(
      _onMessage,
      onDone: _onClose,
      onError: (e) {
        if (!quiet) stderr.writeln('ws error: $e');
      },
      cancelOnError: false,
    );
  }

  void _send(Map<String, Object?> msg) {
    if (ws.readyState == WebSocket.open) {
      ws.add(jsonEncode(msg));
    }
  }

  Future<void> _onMessage(dynamic raw) async {
    Map<String, Object?> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, Object?>;
    } catch (_) {
      return;
    }
    final type = msg['type'] as String?;
    try {
      switch (type) {
        case 'join':
          await _onJoin(msg);
          break;
        case 'offer':
          await _onOffer(msg);
          break;
        case 'answer':
          await _onAnswer(msg);
          break;
        case 'trickle':
          await _onTrickle(msg);
          break;
        case 'leave':
          await _peer?.close();
          await ws.close();
          break;
      }
    } catch (e, st) {
      if (!quiet) stderr.writeln('signaling error ($type): $e\n$st');
    }
  }

  Future<void> _onJoin(Map<String, Object?> msg) async {
    if (_peer != null) return;
    final uid = (msg['uid'] as String?) ??
        'peer-${DateTime.now().microsecondsSinceEpoch}';
    _uid = uid;
    final peer = Peer(sfu);
    peer.onPublisherIceCandidate = (c) {
      _trickle('pub', c);
    };
    peer.onSubscriberIceCandidate = (c) {
      _trickle('sub', c);
    };
    peer.onSubscriberNegotiationNeeded = _emitSubscriberOffer;
    peer.onIceConnectionStateChange = (target, s) {
      if (!quiet) stdout.writeln('[$uid] $target ice: ${s.name}');
    };
    await peer.join(sid: sid, uid: uid);
    _peer = peer;

    // Tell other peers we're here.
    for (final other in peer.session!.peers) {
      if (other.id == uid) continue;
      _sendPeerEvent(other, 'peer-joined', toAll: false);
    }
    _broadcast({'type': 'peer-joined', 'uid': uid});
    _send({'type': 'joined', 'uid': uid, 'sid': sid});

    // If the subscriber was auto-subscribed, the negotiation-needed
    // microtask fires shortly and we'll emit the first sub offer there.
  }

  Future<void> _onOffer(Map<String, Object?> msg) async {
    final target = msg['target'] as String? ?? 'pub';
    final sdp = msg['sdp'] as String?;
    if (sdp == null) return;
    if (target != 'pub') return; // only publisher offers come from client.
    final answer = await _peer!.answerPublisherOffer(sdp);
    _send({'type': 'answer', 'target': 'pub', 'sdp': answer.sdp});
  }

  Future<void> _onAnswer(Map<String, Object?> msg) async {
    final target = msg['target'] as String? ?? 'sub';
    final sdp = msg['sdp'] as String?;
    if (sdp == null) return;
    if (target != 'sub') return; // only subscriber answers come from client.
    await _peer!.setSubscriberAnswer(sdp);
  }

  Future<void> _onTrickle(Map<String, Object?> msg) async {
    final target = msg['target'] as String? ?? 'pub';
    final candidate = msg['candidate'] as String?;
    if (candidate == null) return;
    final cand = RTCIceCandidate(
      candidate: candidate,
      sdpMid: msg['sdpMid']?.toString(),
      sdpMLineIndex: (msg['sdpMLineIndex'] as num?)?.toInt(),
    );
    if (target == 'pub') {
      await _peer!.addPublisherIceCandidate(cand);
    } else {
      await _peer!.addSubscriberIceCandidate(cand);
    }
  }

  Future<void> _emitSubscriberOffer() async {
    final peer = _peer;
    if (peer == null) return;
    final offer = await peer.createSubscriberOffer();
    _send({'type': 'offer', 'target': 'sub', 'sdp': offer.sdp});
  }

  void _trickle(String target, RTCIceCandidate? c) {
    if (c == null || c.candidate.isEmpty) return;
    _send({
      'type': 'trickle',
      'target': target,
      'candidate': c.candidate,
      'sdpMid': c.sdpMid,
      'sdpMLineIndex': c.sdpMLineIndex,
    });
  }

  void _broadcast(Map<String, Object?> msg) {
    final peer = _peer;
    if (peer == null) return;
    final session = peer.session;
    if (session == null) return;
    // We can't reach other peers' WebSockets from here without a registry.
    // Phase 1 keeps it simple: each session's signaling fan-out goes
    // through Session.onPeerJoined / onPeerLeft, which we hook below.
    // For now, emit to self only (peer joined echoes are best-effort).
  }

  void _sendPeerEvent(Peer other, String evt, {required bool toAll}) {
    _send({'type': evt, 'uid': other.id});
  }

  Future<void> _onClose() async {
    if (_uid != null && !quiet) stdout.writeln('[$_uid] ws closed');
    await _peer?.close();
  }
}

Future<String?> _firstNonLoopbackIPv4() async {
  final ifaces = await NetworkInterface.list(
    includeLinkLocal: false,
    type: InternetAddressType.IPv4,
  );
  for (final iface in ifaces) {
    for (final addr in iface.addresses) {
      if (!addr.isLoopback) return addr.address;
    }
  }
  return null;
}
