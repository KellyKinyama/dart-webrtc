// WebSocket + JSON signaling for the ion-style SFU.
//
// Each session runs in its own [SessionShard] worker isolate; this
// file is the main-isolate edge that maps WebSocket frames to RPCs
// against the right shard and demultiplexes shard events back to the
// owning WebSocket.
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';

/// Lifecycle handle returned by [runIonStyleSfuServer].
class IonSfuServerHandle {
  final HttpServer http;
  final ShardedSfu sharded;
  final ClusterCoordinator? cluster;
  IonSfuServerHandle(this.http, this.sharded, [this.cluster]);

  int get port => http.port;

  Future<void> close() async {
    await http.close(force: true);
    await sharded.close();
    await cluster?.close();
  }
}

Future<IonSfuServerHandle> runIonStyleSfuServer({
  String ip = '0.0.0.0',
  int port = 9090,
  int rtpBase = 51000,
  String? announceIp,
  bool quiet = false,
  // Phase 10 — production knobs.
  String? authToken,
  int maxPeersPerRoom = 0,
  int maxRooms = 0,
  // Phase 12 — cluster knobs. Pass [clusterPeers] (including this
  // node) to enable SFU-to-SFU cascade over UDP. [selfClusterId] must
  // match exactly one entry's id; [relayPort] is the local UDP port
  // the relay hub binds; [relaySecret] enables HMAC-SHA256 framing.
  Iterable<ClusterPeer> clusterPeers = const [],
  String? selfClusterId,
  int? relayPort,
  String? relaySecret,
  // Phase 15 — when non-null, every shard's worker periodically
  // closes cascade bridges that haven't seen any inbound traffic for
  // this many milliseconds. Surfaces as a `bridgeClosed` event so the
  // coordinator reclaims the UDP hub endpoint exactly as it would for
  // a remote `bye`.
  int? bridgeIdleTimeoutMs,
  // Phase 19 — when non-null, every established cascade bridge emits
  // a relay-level ping every this many milliseconds. Pair with
  // [bridgeIdleTimeoutMs] (typically keepalive < timeout / 2) so
  // healthy-but-silent media bridges (e.g. audio paused) are not
  // wrongly torn down.
  int? bridgeKeepaliveMs,
}) async {
  final bindAddr = InternetAddress(ip);
  final advertisedIp = announceIp ??
      ((ip == '0.0.0.0' || ip == '::' || ip.isEmpty)
          ? (await _firstNonLoopbackIPv4() ?? '127.0.0.1')
          : ip);

  final sharded = ShardedSfu(ShardConfigTemplate(
    bindAddress: ip,
    rtpBasePort: rtpBase,
    announceAddress: advertisedIp,
    quiet: quiet,
    bridgeIdleTimeoutMs: bridgeIdleTimeoutMs,
    bridgeKeepaliveMs: bridgeKeepaliveMs,
  ));

  // Optional cluster wiring — hub + locator now; coordinator is
  // constructed *after* the WS routers attach to `sharded.onEvent`,
  // because the coordinator wraps that callback to also dispatch
  // CascadeOutboundEvents into the UDP hub.
  ClusterCoordinator? cluster;
  RoomLocator? locator;
  UdpRelayHub? hub;
  List<ClusterPeer>? peersList;
  if (clusterPeers.isNotEmpty) {
    if (selfClusterId == null || selfClusterId.isEmpty) {
      throw ArgumentError(
        'selfClusterId is required when clusterPeers is non-empty',
      );
    }
    if (relayPort == null) {
      throw ArgumentError(
        'relayPort is required when clusterPeers is non-empty',
      );
    }
    peersList = clusterPeers.toList(growable: false);
    if (!peersList.any((p) => p.id == selfClusterId)) {
      throw ArgumentError(
        'selfClusterId "$selfClusterId" must match one of clusterPeers',
      );
    }
    locator = RoomLocator(selfId: selfClusterId, peers: peersList);
    hub = await UdpRelayHub.bind(
      bindAddress: bindAddr,
      port: relayPort,
      secret: relaySecret,
    );
  }

  // Per-session bookkeeping for routing shard events back to the right
  // WebSocket(s).
  final routers = <String, _SessionRouter>{};

  _SessionRouter routerFor(String sid) =>
      routers.putIfAbsent(sid, () => _SessionRouter(sid));

  sharded
    ..onEvent = (event) {
      final r = routers[event.sessionId];
      r?.dispatch(event);
    }
    ..onShardClosed = (sid) {
      final r = routers.remove(sid);
      r?.closeAll();
    };

  // Now that WS routing is in place, layer the cluster coordinator on
  // top — it wraps onEvent and onShardCreated.
  if (hub != null && locator != null && peersList != null) {
    cluster = ClusterCoordinator(
      sharded: sharded,
      hub: hub,
      locator: locator,
      log: quiet ? (_) {} : null,
    );
    if (!quiet) {
      stdout.writeln(
        'cluster mode: self=$selfClusterId, '
        'peers=${peersList.length}, relayUdp=${hub.port}'
        '${relaySecret == null ? ' (UNAUTHENTICATED)' : ''}',
      );
    }
  }

  final http = await HttpServer.bind(bindAddr, port);
  if (!quiet) {
    stdout.writeln(
      'ion-style sharded SFU listening on '
      'ws://$advertisedIp:${http.port}/ws/<sessionId>',
    );
    stdout.writeln(
      'UDP transports start at port $rtpBase '
      '(host candidate: $advertisedIp); each shard owns a 64-port slice.',
    );
  }

  http.listen((req) {
    req.response.headers.set('Access-Control-Allow-Origin', '*');
    req.response.headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
    req.response.headers.set('Access-Control-Allow-Headers', '*');
    if (req.method == 'OPTIONS') {
      req.response.statusCode = HttpStatus.noContent;
      req.response.close();
      return;
    }
    if (req.uri.path == '/stats') {
      sharded.aggregateSnapshotJson().then((j) {
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(j));
        req.response.close();
      });
      return;
    }
    if (req.uri.path == '/metrics') {
      sharded.aggregateSnapshot().then((snap) async {
        final body = StringBuffer(formatPrometheus(snap));
        if (cluster != null && hub != null) {
          try {
            final bridges = await cluster.detailedSnapshot();
            body.write(formatPrometheusCluster(
              hubStats: hub.stats,
              bridges: bridges,
              selfId: selfClusterId,
              upstreamReconnectAttempts: cluster.upstreamReconnectAttempts,
              upstreamReconnectsSucceeded: cluster.upstreamReconnectsSucceeded,
            ));
          } catch (_) {
            // best-effort — never fail /metrics on cluster snapshot
          }
        }
        req.response
          ..headers.contentType =
              ContentType('text', 'plain', charset: 'utf-8', parameters: {
            'version': '0.0.4',
          })
          ..write(body.toString());
        req.response.close();
      });
      return;
    }
    if (req.uri.path == '/healthz') {
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'status': 'ok',
          'shards': sharded.shardCount,
          'mode': cluster == null ? 'sharded' : 'cluster',
          if (cluster != null) ...{
            'self': selfClusterId,
            'peers': clusterPeers.length,
            'cascadeBridges':
                cluster.snapshot().map((b) => b.toJson()).toList(),
          },
        }));
      req.response.close();
      return;
    }
    if (req.uri.path == '/cluster') {
      if (cluster == null) {
        req.response.statusCode = HttpStatus.notFound;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'error': 'not in cluster mode'}));
        req.response.close();
        return;
      }
      final c = cluster;
      c.detailedSnapshot().then((bridges) {
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'self': selfClusterId,
            'peers': [
              for (final p in clusterPeers)
                {
                  'id': p.id,
                  'host': p.host,
                  'httpPort': p.httpPort,
                  'relayPort': p.relayPort,
                  'self': p.id == selfClusterId,
                },
            ],
            'relay': hub?.stats,
            // Phase 22 — upstream-cascade auto-reconnect counters.
            'reconnect': {
              'attempts': c.upstreamReconnectAttempts,
              'succeeded': c.upstreamReconnectsSucceeded,
            },
            'bridges': bridges,
          }));
        req.response.close();
      }).catchError((Object e) {
        req.response.statusCode = HttpStatus.internalServerError;
        req.response.write('cluster snapshot error: $e');
        req.response.close();
      });
      return;
    }
    if (req.uri.path == '/locate') {
      final sid = req.uri.queryParameters['sid'] ?? '';
      final owner = locator?.ownerOf(sid);
      final isSelf = owner == null || owner.id == selfClusterId;
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'sid': sid,
          'owner': isSelf
              ? {'self': true, if (owner != null) 'id': owner.id}
              : {
                  'self': false,
                  'id': owner.id,
                  'host': owner.host,
                  'httpPort': owner.httpPort,
                  'relayPort': owner.relayPort,
                },
        }));
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
      if (authToken != null) {
        final got = req.uri.queryParameters['token'] ??
            _bearerHeader(req.headers.value(HttpHeaders.authorizationHeader));
        if (got != authToken) {
          req.response.statusCode = HttpStatus.unauthorized;
          req.response.close();
          return;
        }
      }
      if (maxRooms > 0 &&
          sharded.get(sid) == null &&
          sharded.shardCount >= maxRooms) {
        req.response.statusCode = HttpStatus.serviceUnavailable;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'error': 'maxRoomsReached',
          'limit': maxRooms,
        }));
        req.response.close();
        return;
      }
      WebSocketTransformer.upgrade(req).then(
        (ws) => _IonPeerSession(
          ws: ws,
          sharded: sharded,
          router: routerFor(sid),
          sid: sid,
          quiet: quiet,
          maxPeersPerRoom: maxPeersPerRoom,
        ).run(),
        onError: (e) {
          if (!quiet) stderr.writeln('ws upgrade error: $e');
        },
      );
      return;
    }
    req.response.statusCode = HttpStatus.notFound;
    req.response.close();
  });

  return IonSfuServerHandle(http, sharded, cluster);
}

String? _bearerHeader(String? raw) {
  if (raw == null) return null;
  if (!raw.toLowerCase().startsWith('bearer ')) return null;
  return raw.substring(7).trim();
}

/// Per-session main-isolate state: the set of WebSockets currently
/// joined to this session, keyed by uid.
class _SessionRouter {
  final String sid;
  final Map<String, WebSocket> sockets = {};

  _SessionRouter(this.sid);

  void register(String uid, WebSocket ws) {
    sockets[uid] = ws;
  }

  void deregister(String uid) {
    sockets.remove(uid);
  }

  void dispatch(ShardEvent event) {
    switch (event) {
      case IceCandidateEvent(
          :final uid,
          :final target,
          :final candidate,
          :final sdpMid,
          :final sdpMLineIndex
        ):
        _sendTo(uid, {
          'type': 'trickle',
          'target': target,
          'candidate': candidate,
          'sdpMid': sdpMid,
          'sdpMLineIndex': sdpMLineIndex,
        });
      case SubscriberOfferEvent(:final uid, :final sdp):
        _sendTo(uid, {'type': 'offer', 'target': 'sub', 'sdp': sdp});
      case PeerLifecycleEvent(:final uid, :final joined):
        final type = joined ? 'peer-joined' : 'peer-left';
        // Broadcast to everyone *except* the peer that joined/left.
        for (final entry in sockets.entries) {
          if (entry.key == uid) continue;
          if (entry.value.readyState == WebSocket.open) {
            entry.value.add(jsonEncode({'type': type, 'uid': uid}));
          }
        }
      case IceStateEvent():
        // Currently log-only; not surfaced to clients.
        break;
      case CascadeOutboundEvent():
        // Handled by ClusterCoordinator listener attached to
        // ShardedSfu.onEvent; nothing to do at the WS-routing layer.
        break;
      case CascadeBridgeClosedEvent():
        // ditto
        break;
      case RelayedStreamEvent():
        // Observability-only; not surfaced to WS clients.
        break;
      case ShardClosedEvent():
        closeAll();
    }
  }

  void _sendTo(String uid, Map<String, Object?> msg) {
    final ws = sockets[uid];
    if (ws == null || ws.readyState != WebSocket.open) return;
    ws.add(jsonEncode(msg));
  }

  void closeAll() {
    for (final ws in sockets.values) {
      if (ws.readyState == WebSocket.open) {
        ws.close();
      }
    }
    sockets.clear();
  }
}

/// Glue between one WebSocket and one peer in a [SessionShard].
class _IonPeerSession {
  final WebSocket ws;
  final ShardedSfu sharded;
  final _SessionRouter router;
  final String sid;
  final bool quiet;
  final int maxPeersPerRoom;

  SessionShard? _shard;
  String? _uid;

  _IonPeerSession({
    required this.ws,
    required this.sharded,
    required this.router,
    required this.sid,
    this.quiet = false,
    this.maxPeersPerRoom = 0,
  });

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
        case 'offer':
          await _onOffer(msg);
        case 'answer':
          await _onAnswer(msg);
        case 'trickle':
          await _onTrickle(msg);
        case 'leave':
          await _leaveAndClose();
      }
    } catch (e, st) {
      if (!quiet) stderr.writeln('signaling error ($type): $e\n$st');
    }
  }

  Future<void> _onJoin(Map<String, Object?> msg) async {
    if (_shard != null) return;
    final uid = (msg['uid'] as String?) ??
        'peer-${DateTime.now().microsecondsSinceEpoch}';
    _uid = uid;

    if (maxPeersPerRoom > 0) {
      final existing = router.sockets.length;
      if (existing >= maxPeersPerRoom) {
        _send({
          'type': 'error',
          'reason': 'maxPeersReached',
          'limit': maxPeersPerRoom,
        });
        await ws.close();
        return;
      }
    }

    final shard = await sharded.getOrCreate(sid);
    _shard = shard;
    router.register(uid, ws);
    await shard.join(uid);
    _send({'type': 'joined', 'uid': uid, 'sid': sid});
  }

  Future<void> _onOffer(Map<String, Object?> msg) async {
    final target = msg['target'] as String? ?? 'pub';
    final sdp = msg['sdp'] as String?;
    if (sdp == null) return;
    if (target != 'pub') return;
    final answer = await _shard!.applyPublisherOffer(_uid!, sdp);
    _send({'type': 'answer', 'target': 'pub', 'sdp': answer});
  }

  Future<void> _onAnswer(Map<String, Object?> msg) async {
    final target = msg['target'] as String? ?? 'sub';
    final sdp = msg['sdp'] as String?;
    if (sdp == null) return;
    if (target != 'sub') return;
    await _shard!.applySubscriberAnswer(_uid!, sdp);
  }

  Future<void> _onTrickle(Map<String, Object?> msg) async {
    final target = msg['target'] as String? ?? 'pub';
    final candidate = msg['candidate'] as String?;
    if (candidate == null) return;
    await _shard!.trickle(
      _uid!,
      target,
      candidate: candidate,
      sdpMid: msg['sdpMid']?.toString(),
      sdpMLineIndex: (msg['sdpMLineIndex'] as num?)?.toInt(),
    );
  }

  Future<void> _leaveAndClose() async {
    final uid = _uid;
    final shard = _shard;
    if (uid != null && shard != null) {
      router.deregister(uid);
      try {
        await shard.leave(uid);
      } catch (_) {
        // shard may already be gone
      }
    }
    await ws.close();
  }

  Future<void> _onClose() async {
    if (_uid != null && !quiet) stdout.writeln('[$_uid] ws closed');
    final uid = _uid;
    final shard = _shard;
    if (uid != null) router.deregister(uid);
    if (uid != null && shard != null) {
      try {
        await shard.leave(uid);
      } catch (_) {}
    }
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
