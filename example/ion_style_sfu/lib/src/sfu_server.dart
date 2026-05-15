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

/// Hard cap on a single inbound WebSocket signaling frame. SDPs in
/// the 8-16 KB range are normal for simulcast offers; ICE trickles
/// are tiny. 256 KB leaves head-room for ridiculous browser quirks
/// while still blocking a client from streaming GBs into our
/// `jsonDecode`. Frames over the cap close the socket.
const int _maxSignalingFrameBytes = 256 * 1024;

/// Sliding-window rate limit on inbound signaling messages, per WS.
/// A real client sends one offer + a handful of trickles + one
/// answer; even with restarts it never approaches this rate. Bursts
/// past the cap close the socket.
const int _maxSignalingMsgsPerWindow = 64;
const Duration _signalingRateWindow = Duration(seconds: 5);

/// Hard cap on identifiers we put into the routing maps. The shard
/// uses these as JSON keys and as map keys, so unbounded strings are
/// a memory-DoS vector even before they hit any media path.
const int _maxIdLen = 128;

/// Conservative WS keepalive. Dart sets up matching pong handling on
/// both sides automatically. Without it a half-open TCP connection
/// (laptop lid closed, hard NAT timeout) keeps the peer alive on the
/// server forever.
const Duration _wsPingInterval = Duration(seconds: 20);

/// Returns true iff [s] is a non-empty, length-bounded ASCII id
/// containing only `[A-Za-z0-9._:\-]`. Rejects control chars,
/// whitespace, NULs, surrogate pairs, and path-traversal sequences.
bool _isValidId(String s) {
  if (s.isEmpty || s.length > _maxIdLen) return false;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    final ok = (c >= 0x30 && c <= 0x39) || // 0-9
        (c >= 0x41 && c <= 0x5a) || // A-Z
        (c >= 0x61 && c <= 0x7a) || // a-z
        c == 0x2d || // -
        c == 0x2e || // .
        c == 0x3a || // :
        c == 0x5f; // _
    if (!ok) return false;
  }
  return true;
}

/// Constant-time comparison of two UTF-8 strings. Used for the bearer
/// token check so an attacker can't recover the token character by
/// character via response-time differences.
bool _constantTimeEquals(String a, String b) {
  final ab = utf8.encode(a);
  final bb = utf8.encode(b);
  // Pad the shorter side to avoid leaking the real length when the
  // attacker submits a token of the wrong size.
  final n = ab.length > bb.length ? ab.length : bb.length;
  var diff = ab.length ^ bb.length;
  for (var i = 0; i < n; i++) {
    final x = i < ab.length ? ab[i] : 0;
    final y = i < bb.length ? bb[i] : 0;
    diff |= x ^ y;
  }
  return diff == 0;
}

/// Lifecycle handle returned by [runIonStyleSfuServer].
class IonSfuServerHandle {
  final HttpServer http;
  final ShardedSfu sharded;
  final ClusterCoordinator? cluster;
  IonSfuServerHandle(this.http, this.sharded, [this.cluster]);

  int get port => http.port;

  /// Phase 26 — once true, /healthz returns 503 and new /ws/
  /// upgrade requests are rejected with 503. Existing WebSocket
  /// sessions keep running so peers can finish their calls. Set via
  /// [drain] or the POST /admin/drain endpoint.
  bool draining = false;

  /// Phase 26 — mark the node as draining (no new sessions, no new
  /// peers). Idempotent. Does not close existing sockets; pair with
  /// [close] once the operator's drain window has elapsed.
  void drain() {
    draining = true;
  }

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
  // Phase 23 — give up on an upstream bridge after this many
  // consecutive reconnect failures. Null = retry forever (the
  // pre-Phase-23 default).
  int? upstreamReconnectMaxAttempts,
  // Phase 25 — node-wide cap on simultaneous sessions. Null = no cap.
  int? maxSessions,
  // Phase 25 — per-session cap on simultaneous peers. Null = no cap.
  int? maxPeersPerSession,
  // Phase 29 — when non-null, every shard's worker periodically
  // closes itself with reason 'idle' if it has been fully empty
  // (no peers, no cascade bridges) for this many milliseconds.
  // Independent of [bridgeIdleTimeoutMs] which only reaps silent
  // bridges within a session.
  int? idleSessionTimeoutMs,
  // Phase 26 — when true, install SIGINT/SIGTERM handlers that
  // call [IonSfuServerHandle.drain] (first signal) then [close]
  // (second signal). Off by default so tests don't fight the
  // process-wide signal listeners.
  bool installSignalHandlers = false,
  // Phase 27 — caller-supplied structured logger. When null we
  // build a [Logger] using stdout/stderr (or [Logger.silent] when
  // [quiet] is true) so the operator-visible behaviour is unchanged.
  Logger? logger,
  // STUN / TURN URLs propagated to every Publisher / Subscriber
  // `RTCPeerConnection` so they gather server-reflexive (`srflx`)
  // candidates in addition to the host candidate. Empty by default;
  // pass e.g. `['stun:stun.l.google.com:19302']` to enable.
  Iterable<String> iceServerUrls = const [],
}) async {
  final log = logger ?? (quiet ? Logger.silent() : Logger());
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
    maxSessions: maxSessions,
    maxPeersPerSession: maxPeersPerSession,
    idleSessionTimeoutMs: idleSessionTimeoutMs,
    iceServerUrls: iceServerUrls.toList(growable: false),
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
      upstreamReconnectMaxAttempts: upstreamReconnectMaxAttempts,
    );
    if (!quiet) {
      log.info('cluster mode online', {
        'self': selfClusterId,
        'peers': peersList.length,
        'relayUdp': hub.port,
        'authenticated': relaySecret != null,
      });
    }
  }

  final http = await HttpServer.bind(bindAddr, port);
  final handle = IonSfuServerHandle(http, sharded, cluster);
  if (!quiet) {
    log.info('sfu listening', {
      'wsUrl': 'ws://$advertisedIp:${http.port}/ws/<sessionId>',
      'rtpBase': rtpBase,
      'announce': advertisedIp,
    });
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
              upstreamReconnectsGivenUp: cluster.upstreamReconnectsGivenUp,
              sessionsRejectedAtCap: sharded.sessionsRejectedAtCap,
              sessionCap: maxSessions,
              peerCap: maxPeersPerSession,
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
      // Phase 26 — drained nodes report 503 so an upstream load
      // balancer / orchestrator stops sending new sessions.
      final draining = handle.draining;
      req.response
        ..statusCode = draining ? HttpStatus.serviceUnavailable : HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'status': draining ? 'draining' : 'ok',
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
    if (req.uri.path == '/admin/drain' && req.method == 'POST') {
      // Phase 26 — admin trigger to start draining. Token-protected
      // when authToken is set; otherwise open (operator's choice).
      if (authToken != null) {
        final got = req.uri.queryParameters['token'] ??
            _bearerHeader(req.headers.value(HttpHeaders.authorizationHeader));
        if (got == null || !_constantTimeEquals(got, authToken)) {
          req.response.statusCode = HttpStatus.unauthorized;
          req.response.close();
          return;
        }
      }
      handle.drain();
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'draining': true}));
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
              // Phase 23 — circuit-breaker give-up count.
              'givenUp': c.upstreamReconnectsGivenUp,
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
      // Phase 26 — a draining node refuses new WebSocket upgrades.
      if (handle.draining) {
        req.response.statusCode = HttpStatus.serviceUnavailable;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'error': 'draining'}));
        req.response.close();
        return;
      }
      final sid = req.uri.path.substring('/ws/'.length);
      if (sid.isEmpty || !_isValidId(Uri.decodeComponent(sid))) {
        req.response.statusCode = HttpStatus.badRequest;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'error': 'invalidSessionId'}));
        req.response.close();
        return;
      }
      if (authToken != null) {
        final got = req.uri.queryParameters['token'] ??
            _bearerHeader(req.headers.value(HttpHeaders.authorizationHeader));
        if (got == null || !_constantTimeEquals(got, authToken)) {
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
        (ws) {
          // Server-driven keepalive so half-open TCP connections
          // (closed laptop, NAT idle reset) eventually surface as
          // an `onDone` instead of a stuck peer.
          ws.pingInterval = _wsPingInterval;
          return _IonPeerSession(
            ws: ws,
            sharded: sharded,
            router: routerFor(sid),
            sid: sid,
            quiet: quiet,
            maxPeersPerRoom: maxPeersPerRoom,
          ).run();
        },
        onError: (e) {
          if (!quiet) log.warn('ws upgrade error', {'error': '$e'});
        },
      );
      return;
    }
    req.response.statusCode = HttpStatus.notFound;
    req.response.close();
  });

  // Phase 26 — optional graceful-shutdown signal handlers. First
  // signal flips drain mode; a second signal triggers a hard close.
  if (installSignalHandlers) {
    var armed = false;
    void wire(ProcessSignal sig) {
      try {
        sig.watch().listen((_) {
          if (!armed) {
            armed = true;
            handle.drain();
            if (!quiet) {
              log.info(
                  'signal received — draining', {'signal': sig.toString()});
            }
          } else {
            if (!quiet) {
              log.info('signal received again — closing',
                  {'signal': sig.toString()});
            }
            handle.close();
          }
        });
      } catch (_) {
        // SIGTERM is unsupported on Windows — silently ignore.
      }
    }

    wire(ProcessSignal.sigint);
    wire(ProcessSignal.sigterm);
  }

  return handle;
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

  /// Sliding-window timestamps of the last N inbound messages,
  /// used to enforce [_maxSignalingMsgsPerWindow] /
  /// [_signalingRateWindow]. Old entries are pruned on each
  /// arrival so the list never grows past the cap.
  final List<DateTime> _recentMsgs = [];

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
    // Reject binary frames outright — the signaling protocol is
    // strictly TEXT JSON.
    if (raw is! String) {
      if (raw is List<int>) {
        // Some clients (and load tools) accidentally send TEXT as
        // bytes. Don't even try to decode — just close.
        await _closeWithError(
            WebSocketStatus.unsupportedData, 'binary not supported');
      }
      return;
    }
    // Frame size cap. UTF-8 expansion is at worst 4x the code-unit
    // length, but `String.length` is the canonical wire estimate
    // for our JSON payloads (almost pure ASCII).
    if (raw.length > _maxSignalingFrameBytes) {
      await _closeWithError(
          WebSocketStatus.messageTooBig, 'frame too large');
      return;
    }
    // Sliding-window rate limit. Drops the socket on burst rather
    // than just dropping the message — a real client never bursts
    // this hard, and accepting more would let a noisy peer crowd
    // out the shard's run loop.
    final now = DateTime.now();
    final cutoff = now.subtract(_signalingRateWindow);
    _recentMsgs.removeWhere((t) => t.isBefore(cutoff));
    if (_recentMsgs.length >= _maxSignalingMsgsPerWindow) {
      await _closeWithError(
          WebSocketStatus.policyViolation, 'rate limit exceeded');
      return;
    }
    _recentMsgs.add(now);

    Map<String, Object?> msg;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return;
      msg = decoded;
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

  Future<void> _closeWithError(int statusCode, String reason) async {
    if (ws.readyState == WebSocket.open) {
      try {
        ws.add(jsonEncode({'type': 'error', 'reason': reason}));
      } catch (_) {}
      try {
        await ws.close(statusCode, reason);
      } catch (_) {}
    }
  }

  Future<void> _onJoin(Map<String, Object?> msg) async {
    if (_shard != null) return;
    final rawUid = msg['uid'] as String?;
    final uid = rawUid ??
        'peer-${DateTime.now().microsecondsSinceEpoch}';
    if (rawUid != null && !_isValidId(rawUid)) {
      _send({'type': 'error', 'reason': 'invalidUid'});
      await ws.close();
      return;
    }
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

    final SessionShard shard;
    try {
      shard = await sharded.getOrCreate(sid);
    } on SfuOverloadedException catch (e) {
      // Phase 25 — node session cap reached.
      _send(
          {'type': 'error', 'reason': 'serverOverloaded', 'detail': e.message});
      await ws.close();
      return;
    }
    _shard = shard;
    // Reject duplicates instead of silently clobbering. Two clients
    // joining the same room with the same uid would otherwise leave
    // an orphan PC pair on the server and route signaling only to
    // whichever socket registered last.
    if (router.sockets.containsKey(uid)) {
      _send({'type': 'error', 'reason': 'uidInUse', 'uid': uid});
      await ws.close();
      return;
    }
    router.register(uid, ws);
    try {
      await shard.join(uid);
    } catch (e) {
      // Phase 25 — translate cap exceptions to a clean client error.
      if (e is SessionFullException ||
          e.toString().contains('SessionFullException')) {
        _send({
          'type': 'error',
          'reason': 'sessionFull',
          'limit': e is SessionFullException ? e.cap : null,
        });
        router.deregister(uid);
        await ws.close();
        return;
      }
      rethrow;
    }
    _send({'type': 'joined', 'uid': uid, 'sid': sid});
  }

  /// Generous SDP cap. Even fully-loaded simulcast offers sit well
  /// under 32 KB; anything larger is almost certainly malformed or
  /// hostile.
  static const int _maxSdpBytes = 64 * 1024;

  /// Cap on a single ICE candidate line. Real candidates are
  /// typically <200 bytes; we allow a kilobyte for crazy
  /// extensions / future-proofing.
  static const int _maxCandidateBytes = 1024;

  Future<void> _onOffer(Map<String, Object?> msg) async {
    final shard = _shard;
    final uid = _uid;
    if (shard == null || uid == null) return; // not joined
    final target = msg['target'] as String? ?? 'pub';
    final sdp = msg['sdp'] as String?;
    if (sdp == null || sdp.length > _maxSdpBytes) return;
    if (target != 'pub') return;
    final answer = await shard.applyPublisherOffer(uid, sdp);
    _send({'type': 'answer', 'target': 'pub', 'sdp': answer});
  }

  Future<void> _onAnswer(Map<String, Object?> msg) async {
    final shard = _shard;
    final uid = _uid;
    if (shard == null || uid == null) return; // not joined
    final target = msg['target'] as String? ?? 'sub';
    final sdp = msg['sdp'] as String?;
    if (sdp == null || sdp.length > _maxSdpBytes) return;
    if (target != 'sub') return;
    await shard.applySubscriberAnswer(uid, sdp);
  }

  Future<void> _onTrickle(Map<String, Object?> msg) async {
    final shard = _shard;
    final uid = _uid;
    if (shard == null || uid == null) return; // not joined
    final target = msg['target'] as String? ?? 'pub';
    if (target != 'pub' && target != 'sub') return;
    final candidate = msg['candidate'] as String?;
    if (candidate == null || candidate.length > _maxCandidateBytes) return;
    // RFC 5245: a real ICE candidate line either starts with
    // "candidate:" or is the empty end-of-candidates marker. Drop
    // anything else without bothering the shard.
    if (candidate.isNotEmpty && !candidate.startsWith('candidate:')) {
      return;
    }
    await shard.trickle(
      uid,
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
