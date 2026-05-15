// Phase 11 — per-session worker isolate that owns the
// PeerConnections.
//
// Each `SessionShard` runs in a dedicated isolate. The worker hosts an
// isolate-local `Sfu` whose only session is the one this shard is
// responsible for. PeerConnections (publisher + subscriber per peer)
// live entirely inside the worker, so PC compute / event-loop pressure
// is isolated to that worker.
//
// The main isolate communicates with each shard via a tagged
// request/reply RPC plus a separate one-way event channel for things
// the worker pushes asynchronously (gathered ICE candidates, server-
// initiated subscriber offers, peer joins/leaves observed inside the
// session, ICE connection state changes, snapshot deltas).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

import 'cascade_event.dart';
import 'peer.dart';
import 'relay/relay.dart';
import 'session.dart';
import 'sfu.dart';
import 'stats/stats.dart';

/// Discriminator for the codecs the shard's `Sfu` should be configured
/// with. Codec class instances aren't sendable across isolates, so the
/// main isolate ships a tag and the worker reconstructs the instance.
enum ShardCodec { vp8, vp9, h264, pcmu, pcma }

/// Boot configuration for a [SessionShard]. All fields must be primitive
/// or otherwise sendable across isolate boundaries.
class ShardConfig {
  final String sessionId;

  /// Address the shard's UDP transports bind on.
  final String bindAddress;

  /// First UDP port available to this shard. The shard's [Sfu]
  /// allocates `rtpBasePort + i` per transport. The orchestrator must
  /// hand out non-overlapping ranges per shard.
  final int rtpBasePort;

  /// Optional override for the host candidate IP.
  final String? announceAddress;

  final List<ShardCodec> videoCodecs;
  final List<ShardCodec> audioCodecs;

  /// Quiet mode (suppress chatty stdout in the worker).
  final bool quiet;

  /// Phase 12 — when this SFU is *not* the owner of [sessionId], the
  /// id of the local SFU node (used to tag the cascade so the owner
  /// can deduplicate). Pair with [upstreamSfuId] / [upstreamHost] /
  /// [upstreamPort] to make the worker auto-attach an outbound
  /// cascade bridge on boot.
  final String? selfSfuId;

  /// Phase 12 — owner SFU id (for log/diagnostic tagging only).
  final String? upstreamSfuId;

  /// Phase 12 — owner SFU's relay UDP host. When non-null the worker
  /// emits a [CascadeOutboundEvent] for every relay frame it wants to
  /// send upstream, tagged with bridgeId 'upstream'. Main routes that
  /// to the actual UDP socket.
  final String? upstreamHost;

  /// Phase 12 — owner SFU's relay UDP port.
  final int? upstreamPort;

  /// Phase 15 — when non-null, the worker scans its cascade bridges
  /// every few seconds and closes any whose last inbound activity
  /// (control / RTP / RTCP) is older than this many milliseconds.
  /// `null` (default) disables the reaper. Closure runs through the
  /// usual `bridgeClosed` event path so the coordinator reclaims the
  /// hub endpoint exactly as it would for a remote `bye`.
  final int? bridgeIdleTimeoutMs;

  /// Phase 19 — when non-null, every established cascade bridge
  /// emits a relay-level `ping` every this many milliseconds. The
  /// remote side replies with `pong`, and the inbound delivery
  /// resets the bridge's `lastInboundAt` so the [bridgeIdleTimeoutMs]
  /// reaper does not tear down healthy-but-silent links.
  final int? bridgeKeepaliveMs;

  /// Phase 25 — hard cap on simultaneous peers in this session.
  /// `null` (default) disables the cap. The worker rejects further
  /// `join` calls past the cap with [SessionFullException], which
  /// the orchestrator translates to a 4xx for the client.
  final int? maxPeersPerSession;

  /// Phase 29 — when non-null, the worker periodically checks
  /// whether the session has had zero peers and zero cascade
  /// bridges continuously for this many milliseconds, and if so
  /// triggers an [ShardCloseReason.idle] shutdown. Useful for
  /// reaping shards that were spawned (e.g. by an inbound cascade
  /// hello or a stalled join) but never accumulated activity.
  /// Independent of [bridgeIdleTimeoutMs] which only reaps
  /// individual silent bridges.
  final int? idleSessionTimeoutMs;

  /// STUN / TURN URLs propagated to every Publisher / Subscriber
  /// `RTCPeerConnection` as `RTCConfiguration.iceServers`. Today only
  /// `stun:` URLs are honoured; each one yields a server-reflexive
  /// (`srflx`) candidate trickled to the client over the existing
  /// signaling channel. Strings (rather than the codec-style enum tags)
  /// because URLs are already isolate-sendable primitives.
  final List<String> iceServerUrls;

  const ShardConfig({
    required this.sessionId,
    required this.bindAddress,
    required this.rtpBasePort,
    this.announceAddress,
    this.videoCodecs = const [ShardCodec.vp8],
    this.audioCodecs = const [ShardCodec.pcmu],
    this.quiet = false,
    this.selfSfuId,
    this.upstreamSfuId,
    this.upstreamHost,
    this.upstreamPort,
    this.bridgeIdleTimeoutMs,
    this.bridgeKeepaliveMs,
    this.maxPeersPerSession,
    this.idleSessionTimeoutMs,
    this.iceServerUrls = const [],
  });
}

/// Phase 25 — thrown from the worker when a join would push the
/// session past [ShardConfig.maxPeersPerSession]. Surfaced to main
/// as the rejected RPC's error string.
class SessionFullException implements Exception {
  final String sessionId;
  final int cap;
  const SessionFullException(this.sessionId, this.cap);
  @override
  String toString() =>
      'SessionFullException: session $sessionId is full (cap=$cap)';
}

/// Reasons a [SessionShard] may close itself.
enum ShardCloseReason {
  idle,
  mainRequested,
  error,
  // Phase 24 — the cluster's upstream-reconnect circuit breaker
  // tripped, so this non-owner shard can never reach its owner.
  upstreamUnreachable,
}

/// Events the worker emits asynchronously back to the main isolate.
sealed class ShardEvent {
  final String sessionId;
  const ShardEvent(this.sessionId);
}

/// Trickle ICE candidate gathered on a peer's PC.
class IceCandidateEvent extends ShardEvent {
  final String uid;
  final String target; // 'pub' | 'sub'
  final String? candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
  const IceCandidateEvent({
    required String sessionId,
    required this.uid,
    required this.target,
    required this.candidate,
    required this.sdpMid,
    required this.sdpMLineIndex,
  }) : super(sessionId);
}

/// Server-initiated subscriber offer that must be sent to the client.
class SubscriberOfferEvent extends ShardEvent {
  final String uid;
  final String sdp;
  const SubscriberOfferEvent({
    required String sessionId,
    required this.uid,
    required this.sdp,
  }) : super(sessionId);
}

/// Lifecycle event observed inside the session.
class PeerLifecycleEvent extends ShardEvent {
  final String uid;
  final bool joined;
  const PeerLifecycleEvent({
    required String sessionId,
    required this.uid,
    required this.joined,
  }) : super(sessionId);
}

/// ICE connection-state change observed on either PC.
class IceStateEvent extends ShardEvent {
  final String uid;
  final String target;
  final String state;
  const IceStateEvent({
    required String sessionId,
    required this.uid,
    required this.target,
    required this.state,
  }) : super(sessionId);
}

/// Worker has shut itself down. After this no further events arrive
/// and any RPC will throw.
class ShardClosedEvent extends ShardEvent {
  final ShardCloseReason reason;
  final String? message;
  const ShardClosedEvent({
    required String sessionId,
    required this.reason,
    this.message,
  }) : super(sessionId);
}

/// Cluster cascade frame the worker wants to ship out over the main-
/// isolate UDP relay hub. Tagged with [bridgeId] so main can route to
/// the right remote SFU endpoint.
class CascadeOutboundEvent extends ShardEvent {
  final String bridgeId;
  final CascadeRelayKind kind;
  final List<int> bytes;
  const CascadeOutboundEvent({
    required String sessionId,
    required this.bridgeId,
    required this.kind,
    required this.bytes,
  }) : super(sessionId);
}

/// Worker telling main that an inbound cascade bridge is no longer
/// needed (the underlying [RelayPeer] closed). Main may reclaim its
/// endpoint mapping.
class CascadeBridgeClosedEvent extends ShardEvent {
  final String bridgeId;
  const CascadeBridgeClosedEvent({
    required String sessionId,
    required this.bridgeId,
  }) : super(sessionId);
}

/// A remote SFU announced a stream over a cascade bridge and the
/// worker just published it into the local session as a relayed
/// receiver. Useful for tests and for cluster-wide observability.
class RelayedStreamEvent extends ShardEvent {
  final String bridgeId;
  final String mid;
  final String kind; // 'audio' | 'video'
  final int primarySsrc;
  const RelayedStreamEvent({
    required String sessionId,
    required this.bridgeId,
    required this.mid,
    required this.kind,
    required this.primarySsrc,
  }) : super(sessionId);
}

/// Main-isolate handle to a per-session worker isolate. Spawn via
/// [SessionShard.spawn], drive signaling via the methods below, and
/// observe asynchronous notifications via [events].
class SessionShard {
  final String sessionId;
  final ShardConfig config;
  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  final Map<int, Completer<Object?>> _pending = {};
  final StreamController<ShardEvent> _events =
      StreamController<ShardEvent>.broadcast();
  int _nextReqId = 1;
  bool _closed = false;
  // Captured when the worker self-closes so [_call] / [close] can
  // surface the actual root cause (e.g. uncaught isolate error)
  // instead of a generic "closed" message. See _onEvent('closed').
  ShardCloseReason? _closeReason;
  String? _closeMessage;

  SessionShard._(this.sessionId, this.config, this._isolate, this._toWorker,
      this._fromWorker) {
    _fromWorker.listen(_onMessage);
  }

  /// Stream of asynchronous events emitted by the worker.
  Stream<ShardEvent> get events => _events.stream;

  /// `true` once [close] has been called or the worker self-closed.
  bool get isClosed => _closed;

  /// Spawn a new worker isolate dedicated to [config.sessionId].
  static Future<SessionShard> spawn(ShardConfig config) async {
    final handshake = ReceivePort();
    final replies = ReceivePort();
    final iso = await Isolate.spawn<_BootMsg>(
      _workerMain,
      _BootMsg(config, handshake.sendPort, replies.sendPort),
      debugName: 'session-shard:${config.sessionId}',
      errorsAreFatal: false,
    );
    final toWorker = await handshake.first as SendPort;
    handshake.close();
    return SessionShard._(config.sessionId, config, iso, toWorker, replies);
  }

  // ----- RPC ----------------------------------------------------------

  /// Create a Peer in the worker for [uid].
  Future<void> join(String uid,
      {bool noPublish = false, bool noSubscribe = false}) async {
    await _call('join', {
      'uid': uid,
      'noPublish': noPublish,
      'noSubscribe': noSubscribe,
    });
  }

  /// Apply the client's publisher offer; returns the server-side answer SDP.
  Future<String> applyPublisherOffer(String uid, String offerSdp) async {
    final r = await _call('pubOffer', {'uid': uid, 'sdp': offerSdp}) as String;
    return r;
  }

  /// Apply the client's answer to a server-issued subscriber offer.
  Future<void> applySubscriberAnswer(String uid, String answerSdp) async {
    await _call('subAnswer', {'uid': uid, 'sdp': answerSdp});
  }

  /// Add a trickled ICE candidate. [target] is `'pub'` or `'sub'`.
  Future<void> trickle(
    String uid,
    String target, {
    required String? candidate,
    required String? sdpMid,
    required int? sdpMLineIndex,
  }) async {
    await _call('trickle', {
      'uid': uid,
      'target': target,
      'candidate': candidate,
      'sdpMid': sdpMid,
      'sdpMLineIndex': sdpMLineIndex,
    });
  }

  /// Drop a peer from the session.
  Future<void> leave(String uid) async {
    await _call('leave', {'uid': uid});
  }

  /// Snapshot stats for this shard's session.
  Future<Map<String, Object?>> snapshotJson() async {
    final r = await _call('snapshot') as Map<dynamic, dynamic>;
    return r.cast<String, Object?>();
  }

  /// Phase 12 — attach a new cascade bridge inside the worker.
  ///
  /// The worker creates a synthetic [RelayTransport] that emits
  /// [CascadeOutboundEvent]s back to main and accepts inbound bytes
  /// via [deliverRelayInbound]. [role] picks whether the worker
  /// initiates the relay handshake (outbound) or waits for it
  /// (inbound).
  Future<void> cascadeAttach({
    required String bridgeId,
    required CascadeBridgeRole role,
    required String remoteId,
  }) async {
    await _call('bridgeAttach', {
      'bridgeId': bridgeId,
      'role': role.index,
      'remoteId': remoteId,
    });
  }

  /// Phase 12 — detach (and close) a cascade bridge.
  Future<void> cascadeDetach(String bridgeId) async {
    await _call('bridgeDetach', {'bridgeId': bridgeId});
  }

  /// Phase 13 — snapshot of every cascade bridge inside the worker.
  /// Each entry exposes role, RTP packet count, established flag, and
  /// the number of exported / relayed receivers.
  Future<List<Map<String, Object?>>> cascadeBridgeStats() async {
    final r = await _call('bridgeStats') as List;
    return r
        .map((e) => (e as Map).cast<String, Object?>())
        .toList(growable: false);
  }

  /// Phase 12 — inject a relay frame received on the main-isolate UDP
  /// hub for [bridgeId].
  Future<void> deliverRelayInbound(
    String bridgeId,
    CascadeRelayKind kind,
    Uint8List bytes,
  ) async {
    await _call('relayIn', {
      'bridgeId': bridgeId,
      'kind': kind.index,
      'bytes': bytes,
    });
  }

  /// Tear the worker down. Idempotent; safe to call after the worker
  /// has self-closed.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _call('close').timeout(const Duration(seconds: 3));
    } catch (_) {
      // worker may already be gone
    }
    await _events.close();
    _fromWorker.close();
    _isolate.kill(priority: Isolate.immediate);
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError(_closedErrorMessage()));
      }
    }
    _pending.clear();
  }

  String _closedErrorMessage() {
    final reason = _closeReason;
    final msg = _closeMessage;
    final base = 'SessionShard($sessionId) closed';
    if (reason == null && msg == null) return base;
    final parts = <String>[base];
    if (reason != null) parts.add('reason=${reason.name}');
    if (msg != null && msg.isNotEmpty) parts.add('message=$msg');
    return parts.join(' ');
  }

  // ----- internals ---------------------------------------------------

  void _onMessage(dynamic msg) {
    if (msg is! Map) return;
    final id = msg['id'];
    if (id is int) {
      final c = _pending.remove(id);
      if (c == null) return;
      final err = msg['error'];
      if (err != null) {
        c.completeError(StateError(err.toString()));
      } else {
        c.complete(msg['result']);
      }
      return;
    }
    final ev = msg['event'];
    if (ev is String) {
      _onEvent(ev, (msg['data'] as Map).cast<String, Object?>());
    }
  }

  void _onEvent(String event, Map<String, Object?> data) {
    switch (event) {
      case 'ice':
        _events.add(IceCandidateEvent(
          sessionId: sessionId,
          uid: data['uid'] as String,
          target: data['target'] as String,
          candidate: data['candidate'] as String?,
          sdpMid: data['sdpMid'] as String?,
          sdpMLineIndex: data['sdpMLineIndex'] as int?,
        ));
      case 'subOffer':
        _events.add(SubscriberOfferEvent(
          sessionId: sessionId,
          uid: data['uid'] as String,
          sdp: data['sdp'] as String,
        ));
      case 'peerJoined':
        _events.add(PeerLifecycleEvent(
          sessionId: sessionId,
          uid: data['uid'] as String,
          joined: true,
        ));
      case 'peerLeft':
        _events.add(PeerLifecycleEvent(
          sessionId: sessionId,
          uid: data['uid'] as String,
          joined: false,
        ));
      case 'iceState':
        _events.add(IceStateEvent(
          sessionId: sessionId,
          uid: data['uid'] as String,
          target: data['target'] as String,
          state: data['state'] as String,
        ));
      case 'closed':
        final reason = ShardCloseReason.values[data['reason'] as int];
        final message = data['message'] as String?;
        _closeReason = reason;
        _closeMessage = message;
        _events.add(ShardClosedEvent(
          sessionId: sessionId,
          reason: reason,
          message: message,
        ));
        _closed = true;
      case 'relayOut':
        _events.add(CascadeOutboundEvent(
          sessionId: sessionId,
          bridgeId: data['bridgeId'] as String,
          kind: CascadeRelayKind.values[data['kind'] as int],
          bytes: (data['bytes'] as List).cast<int>(),
        ));
      case 'bridgeClosed':
        _events.add(CascadeBridgeClosedEvent(
          sessionId: sessionId,
          bridgeId: data['bridgeId'] as String,
        ));
      case 'relayedStream':
        _events.add(RelayedStreamEvent(
          sessionId: sessionId,
          bridgeId: data['bridgeId'] as String,
          mid: data['mid'] as String,
          kind: data['kind'] as String,
          primarySsrc: data['primarySsrc'] as int,
        ));
    }
  }

  Future<Object?> _call(String op, [Object? payload]) {
    if (_closed) {
      throw StateError(_closedErrorMessage());
    }
    final id = _nextReqId++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _toWorker.send({'id': id, 'op': op, 'payload': payload});
    return c.future;
  }
}

class _BootMsg {
  final ShardConfig config;
  final SendPort handshake;
  final SendPort replies;
  const _BootMsg(this.config, this.handshake, this.replies);
}

// ===================================================================
// Worker side (runs in the spawned isolate).
// ===================================================================

void _workerMain(_BootMsg boot) {
  // Phase 28 — crash containment. Any uncaught error inside the
  // worker isolate is converted into a `closed` event with reason
  // [ShardCloseReason.error] so the orchestrator can react (the
  // ClusterCoordinator currently treats it the same as a circuit-
  // breaker trip), and the isolate exits cleanly instead of taking
  // the whole SFU process down via Isolate.current.kill().
  runZonedGuarded(() {
    final inbox = ReceivePort();
    boot.handshake.send(inbox.sendPort);
    final worker = _ShardWorker(boot.config, boot.replies, inbox);
    worker.start();
  }, (e, st) {
    try {
      boot.replies.send({
        'event': 'closed',
        'data': {
          'reason': ShardCloseReason.error.index,
          'message': 'uncaught: $e\n$st',
        },
      });
    } catch (_) {
      // The reply port may already be torn down; nothing more to do.
    }
  });
}

class _ShardWorker {
  final ShardConfig config;
  final SendPort replies;
  final ReceivePort inbox;
  late final Sfu sfu;
  final Map<String, Peer> peers = {};
  final Map<String, _CascadeBridge> bridges = {};
  bool closed = false;

  /// Phase 15 — periodic idle-bridge sweeper. Created on demand
  /// when the first bridge is attached if [ShardConfig.bridgeIdleTimeoutMs]
  /// is non-null.
  Timer? _bridgeReaper;

  /// Phase 19 — periodic keepalive ping emitter for established
  /// bridges. Created on demand when the first bridge is attached if
  /// [ShardConfig.bridgeKeepaliveMs] is non-null.
  Timer? _bridgeKeepalive;
  int _keepaliveNonce = 0;

  /// Phase 29 — periodic idle-session sweeper. Created in [start]
  /// when [ShardConfig.idleSessionTimeoutMs] is non-null. Closes the
  /// shard with [ShardCloseReason.idle] when it has had zero peers
  /// AND zero bridges for [_idleSinceMs] longer than the configured
  /// timeout.
  Timer? _idleSessionReaper;

  /// Phase 29 — wall-clock ms when the worker first observed both
  /// `peers` and `bridges` empty. Reset to the current time on
  /// every transition into the empty state. `null` means we have
  /// peers and/or bridges right now.
  int? _idleSinceMs;

  _ShardWorker(this.config, this.replies, this.inbox);

  Session? get _session {
    for (final p in peers.values) {
      final s = p.session;
      if (s != null) return s;
    }
    // No peers yet — force-create the session so cascade bridges have
    // somewhere to publish into. Idempotent in the underlying Sfu.
    return sfu.getSession(config.sessionId);
  }

  void start() {
    sfu = Sfu(WebRTCTransportConfig(
      bindAddress: InternetAddress(config.bindAddress),
      rtpBasePort: config.rtpBasePort,
      announceAddress: config.announceAddress == null
          ? null
          : InternetAddress(config.announceAddress!),
      defaultVideoCodecs: _materialiseCodecs(config.videoCodecs),
      defaultAudioCodecs: _materialiseCodecs(config.audioCodecs),
      iceServerUrls: config.iceServerUrls,
    ));
    inbox.listen((msg) => _onMessage(msg));
    // Phase 29 — start the idle-session reaper if configured. The
    // shard is born empty, so seed the marker and let the timer
    // reap it if no one ever joins / no bridge ever attaches.
    final idleTimeout = config.idleSessionTimeoutMs;
    if (idleTimeout != null && idleTimeout > 0) {
      _idleSinceMs = DateTime.now().millisecondsSinceEpoch;
      final tickMs = (idleTimeout ~/ 4).clamp(100, 5000);
      _idleSessionReaper = Timer.periodic(Duration(milliseconds: tickMs), (_) {
        _checkIdleSession(idleTimeout);
      });
    }
    // Note: any upstream cascade bridge is attached explicitly by the
    // main-isolate orchestrator after it subscribes to the event
    // stream — otherwise the initial cascade-hello relayOut event
    // would be dropped by the (broadcast) event controller.
  }

  Future<void> _onMessage(dynamic msg) async {
    if (msg is! Map) return;
    final id = msg['id'] as int?;
    final op = msg['op'] as String?;
    final payload = msg['payload'];
    if (id == null || op == null) return;

    Object? result;
    String? error;
    try {
      switch (op) {
        case 'join':
          await _join((payload as Map).cast<String, Object?>());
          result = null;
        case 'pubOffer':
          result = await _pubOffer((payload as Map).cast<String, Object?>());
        case 'subAnswer':
          await _subAnswer((payload as Map).cast<String, Object?>());
          result = null;
        case 'trickle':
          await _trickle((payload as Map).cast<String, Object?>());
          result = null;
        case 'leave':
          await _leave((payload as Map).cast<String, Object?>());
          result = null;
        case 'snapshot':
          result = snapshotSfu(sfu).toJson();
        case 'bridgeStats':
          result = _bridgeStats();
        case 'bridgeAttach':
          _bridgeAttach((payload as Map).cast<String, Object?>());
          result = null;
        case 'bridgeDetach':
          await _bridgeDetach((payload as Map).cast<String, Object?>());
          result = null;
        case 'relayIn':
          _relayIn((payload as Map).cast<String, Object?>());
          result = null;
        case 'close':
          result = null;
          replies.send({'id': id, 'result': result});
          await _shutdown(ShardCloseReason.mainRequested);
          return;
        default:
          error = 'unknown op: $op';
      }
    } catch (e, st) {
      error = '$e\n$st';
    }
    replies.send({'id': id, 'result': result, 'error': error});
  }

  Future<void> _join(Map<String, Object?> p) async {
    final uid = p['uid'] as String;
    if (peers.containsKey(uid)) return;
    // Phase 25 — enforce the per-session peer cap *before* allocating
    // any PC resources. New uids past the cap are rejected; existing
    // uids re-joining are tolerated above (the early-return).
    final cap = config.maxPeersPerSession;
    if (cap != null && peers.length >= cap) {
      throw SessionFullException(config.sessionId, cap);
    }
    final noPublish = (p['noPublish'] as bool?) ?? false;
    final noSubscribe = (p['noSubscribe'] as bool?) ?? false;
    final peer = Peer(sfu);
    peer.onPublisherIceCandidate = (c) => _emitIce(uid, 'pub', c);
    peer.onSubscriberIceCandidate = (c) => _emitIce(uid, 'sub', c);
    peer.onSubscriberNegotiationNeeded = () => _emitSubOffer(uid);
    peer.onIceConnectionStateChange =
        (target, s) => _emitIceState(uid, target, s);
    await peer.join(
      sid: config.sessionId,
      uid: uid,
      joinConfig:
          PeerJoinConfig(noPublish: noPublish, noSubscribe: noSubscribe),
    );
    peers[uid] = peer;
    _markActivity();
    _emitEvent('peerJoined', {'uid': uid});

    // Hook session-level events (idempotent — addPeer fires once per peer).
    final session = peer.session;
    if (session != null) {
      session.onPeerLeft ??= (gone) {
        _emitEvent('peerLeft', {'uid': gone.id});
      };
    }
  }

  Future<String> _pubOffer(Map<String, Object?> p) async {
    final uid = p['uid'] as String;
    final sdp = p['sdp'] as String;
    final peer = peers[uid];
    if (peer == null) {
      throw StateError('unknown uid $uid');
    }
    final answer = await peer.answerPublisherOffer(sdp);
    return answer.sdp;
  }

  Future<void> _subAnswer(Map<String, Object?> p) async {
    final uid = p['uid'] as String;
    final sdp = p['sdp'] as String;
    final peer = peers[uid];
    if (peer == null) return;
    await peer.setSubscriberAnswer(sdp);
  }

  Future<void> _trickle(Map<String, Object?> p) async {
    final uid = p['uid'] as String;
    final target = p['target'] as String;
    final cand = RTCIceCandidate(
      candidate: (p['candidate'] as String?) ?? '',
      sdpMid: p['sdpMid'] as String?,
      sdpMLineIndex: p['sdpMLineIndex'] as int?,
    );
    final peer = peers[uid];
    if (peer == null) return;
    if (target == 'pub') {
      await peer.addPublisherIceCandidate(cand);
    } else {
      await peer.addSubscriberIceCandidate(cand);
    }
  }

  Future<void> _leave(Map<String, Object?> p) async {
    final uid = p['uid'] as String;
    final peer = peers.remove(uid);
    if (peer == null) return;
    await peer.close();
    _markIdleIfEmpty();
    if (peers.isEmpty) {
      // Session is empty — let the orchestrator reap us.
      await _shutdown(ShardCloseReason.idle);
    }
  }

  void _emitIce(String uid, String target, RTCIceCandidate? c) {
    if (c == null) return;
    _emitEvent('ice', {
      'uid': uid,
      'target': target,
      'candidate': c.candidate,
      'sdpMid': c.sdpMid,
      'sdpMLineIndex': c.sdpMLineIndex,
    });
  }

  void _emitSubOffer(String uid) {
    final peer = peers[uid];
    if (peer == null) return;
    // Build asynchronously — negotiationneeded callback is sync void.
    () async {
      try {
        final offer = await peer.createSubscriberOffer();
        _emitEvent('subOffer', {'uid': uid, 'sdp': offer.sdp});
      } catch (e) {
        // Best-effort; surface as an iceState-style event for visibility.
        _emitEvent('iceState',
            {'uid': uid, 'target': 'sub', 'state': 'subOfferError:$e'});
      }
    }();
  }

  void _emitIceState(String uid, String target, RTCIceConnectionState state) {
    _emitEvent('iceState', {'uid': uid, 'target': target, 'state': state.name});
  }

  void _emitEvent(String name, Map<String, Object?> data) {
    if (closed) return;
    replies.send({'event': name, 'data': data});
  }

  Future<void> _shutdown(ShardCloseReason reason, [String? message]) async {
    if (closed) return;
    closed = true;
    _bridgeReaper?.cancel();
    _bridgeReaper = null;
    _bridgeKeepalive?.cancel();
    _bridgeKeepalive = null;
    _idleSessionReaper?.cancel();
    _idleSessionReaper = null;
    try {
      for (final b in bridges.values.toList()) {
        await b.close();
      }
      bridges.clear();
      for (final p in peers.values.toList()) {
        await p.close();
      }
      peers.clear();
      await sfu.close();
    } catch (_) {
      // best-effort
    }
    replies.send({
      'event': 'closed',
      'data': {'reason': reason.index, 'message': message},
    });
    inbox.close();
  }

  // ---- Phase 12 cascade bridges -----------------------------------

  void _bridgeAttach(Map<String, Object?> p) {
    final bridgeId = p['bridgeId'] as String;
    final role = CascadeBridgeRole.values[p['role'] as int];
    final remoteId = p['remoteId'] as String;
    _attachBridge(bridgeId: bridgeId, role: role, remoteId: remoteId);
  }

  void _attachBridge({
    required String bridgeId,
    required CascadeBridgeRole role,
    required String remoteId,
  }) {
    if (bridges.containsKey(bridgeId)) return;
    final session = _session;
    if (session == null) return;
    final transport = _BridgeTransport(
      bridgeId: bridgeId,
      worker: this,
    );
    final relay = RelayPeer.over(
      remoteId: remoteId,
      session: session,
      transport: transport,
    );
    final bridge = _CascadeBridge(
      bridgeId: bridgeId,
      role: role,
      transport: transport,
      relay: relay,
      session: session,
    );
    bridges[bridgeId] = bridge;
    _markActivity();
    relay.onEstablished = () => bridge.exportLocalProducers();
    relay.onRelayedStream = (recv) {
      // Count every RTP packet that arrives on this relayed receiver
      // so tests / observability can verify the data plane.
      recv.addRtpTap((_) => bridge.inboundRtpPackets++);
      _emitEvent('relayedStream', {
        'bridgeId': bridgeId,
        'mid': recv.stream.mid,
        'kind': recv.stream.kind,
        'primarySsrc': recv.primarySsrc,
      });
      // Re-export this newly-arrived stream over every *other* bridge
      // so true cluster fan-out works (A → owner → B). The per-bridge
      // loop-prevention in [exportLocalProducers] skips the bridge
      // that originated the stream.
      for (final other in bridges.values) {
        if (identical(other, bridge)) continue;
        if (!other._established) continue;
        other.exportLocalProducers();
      }
    };
    relay.onClosed = () {
      // Either the remote sent `bye` or we shut down locally. Drop
      // our bookkeeping and tell main so it can reclaim the route.
      if (bridges.remove(bridgeId) != null) {
        _markIdleIfEmpty();
        _emitEvent('bridgeClosed', {'bridgeId': bridgeId});
      }
    };
    if (role == CascadeBridgeRole.outbound) {
      // Send the cascade-hello so the owner can find us.
      transport.sendControl({
        'type': 'cascade-hello',
        'sessionId': config.sessionId,
        'fromSfu': config.selfSfuId,
      });
    }
    relay.start();
    _ensureBridgeReaper();
    _ensureBridgeKeepalive();
  }

  Future<void> _bridgeDetach(Map<String, Object?> p) async {
    final bridgeId = p['bridgeId'] as String;
    final b = bridges.remove(bridgeId);
    if (b == null) return;
    _markIdleIfEmpty();
    // Phase 22 — emit `bridgeClosed` so main can reclaim the route
    // and (for upstream bridges) trigger an auto-reconnect. The
    // RelayPeer.onClosed handler is a no-op now because we already
    // removed the bridge above.
    _emitEvent('bridgeClosed', {'bridgeId': bridgeId});
    await b.close();
  }

  void _relayIn(Map<String, Object?> p) {
    final bridgeId = p['bridgeId'] as String;
    final kind = CascadeRelayKind.values[p['kind'] as int];
    final raw = p['bytes'];
    final bytes =
        raw is Uint8List ? raw : Uint8List.fromList((raw as List).cast<int>());
    final b = bridges[bridgeId];
    if (b == null) return;
    b.lastInboundAtMs = DateTime.now().millisecondsSinceEpoch;
    // Phase 21 — RX throughput accounting (split by frame kind).
    switch (kind) {
      case CascadeRelayKind.control:
        b.rxControlPackets++;
        b.rxControlBytes += bytes.length;
      case CascadeRelayKind.rtp:
        b.rxRtpPackets++;
        b.rxRtpBytes += bytes.length;
      case CascadeRelayKind.rtcp:
        b.rxRtcpPackets++;
        b.rxRtcpBytes += bytes.length;
    }
    // Phase 20 — peek at control frames so we can resolve pong
    // replies to the keepalive pings we sent and update RTT before
    // handing the frame off to the RelayPeer (which treats pong as
    // a no-op).
    if (kind == CascadeRelayKind.control) {
      _maybeRecordPongRtt(b, bytes);
    }
    b.transport.receive(kind, bytes);
  }

  /// Phase 20 — if [bytes] decodes to `{type: pong, nonce: N}` and N
  /// matches an outstanding keepalive ping, record the round-trip
  /// time on the bridge.
  void _maybeRecordPongRtt(_CascadeBridge b, Uint8List bytes) {
    Object? decoded;
    try {
      decoded = utf8JsonDecode(bytes);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    if (decoded['type'] != RelayMsgType.pong) return;
    final nonce = decoded['nonce'];
    if (nonce is! int) return;
    final sentAt = b.pendingPings.remove(nonce);
    if (sentAt == null) return;
    final rtt = DateTime.now().millisecondsSinceEpoch - sentAt;
    if (rtt < 0) return;
    b.lastRttMs = rtt;
    final prev = b.rttEwmaMs;
    // Standard EWMA, alpha = 0.25 — same shape as TCP's SRTT.
    b.rttEwmaMs = (prev == null) ? rtt.toDouble() : (prev * 0.75 + rtt * 0.25);
  }

  List<Map<String, Object?>> _bridgeStats() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      for (final b in bridges.values)
        {
          'bridgeId': b.bridgeId,
          'role': b.role.index,
          'remoteId': b.relay.remoteId,
          'exports': b.exports.length,
          'inboundRtpPackets': b.inboundRtpPackets,
          'relayedReceivers': b.relay.relayedReceivers.length,
          'established': b.relay.established,
          'createdAtMs': b.createdAtMs,
          'lastInboundAtMs': b.lastInboundAtMs,
          'idleMs': now - b.lastInboundAtMs,
          // Phase 20 — relay RTT (ms) measured from keepalive
          // ping/pong. Null until the first pong arrives.
          'lastRttMs': b.lastRttMs,
          'rttEwmaMs': b.rttEwmaMs,
          'pendingPings': b.pendingPings.length,
          // Phase 21 — throughput counters split by direction +
          // frame kind.
          'txControlPackets': b.txControlPackets,
          'txControlBytes': b.txControlBytes,
          'txRtpPackets': b.txRtpPackets,
          'txRtpBytes': b.txRtpBytes,
          'txRtcpPackets': b.txRtcpPackets,
          'txRtcpBytes': b.txRtcpBytes,
          'rxControlPackets': b.rxControlPackets,
          'rxControlBytes': b.rxControlBytes,
          'rxRtpPackets': b.rxRtpPackets,
          'rxRtpBytes': b.rxRtpBytes,
          'rxRtcpPackets': b.rxRtcpPackets,
          'rxRtcpBytes': b.rxRtcpBytes,
        }
    ];
  }

  void emitRelayOut(String bridgeId, CascadeRelayKind kind, Uint8List bytes) {
    if (closed) return;
    // Phase 21 — TX throughput accounting (split by frame kind).
    final b = bridges[bridgeId];
    if (b != null) {
      switch (kind) {
        case CascadeRelayKind.control:
          b.txControlPackets++;
          b.txControlBytes += bytes.length;
        case CascadeRelayKind.rtp:
          b.txRtpPackets++;
          b.txRtpBytes += bytes.length;
        case CascadeRelayKind.rtcp:
          b.txRtcpPackets++;
          b.txRtcpBytes += bytes.length;
      }
    }
    _emitEvent('relayOut', {
      'bridgeId': bridgeId,
      'kind': kind.index,
      'bytes': bytes,
    });
  }

  /// Phase 29 — called when peers/bridges may have transitioned to
  /// non-empty. Clears the idle marker so the reaper sees activity.
  void _markActivity() {
    _idleSinceMs = null;
  }

  /// Phase 29 — called when peers/bridges may have transitioned to
  /// empty. Stamps `_idleSinceMs` if (and only if) the shard is now
  /// fully idle. No-op if the reaper is disabled.
  void _markIdleIfEmpty() {
    if (config.idleSessionTimeoutMs == null) return;
    if (peers.isEmpty && bridges.isEmpty) {
      _idleSinceMs ??= DateTime.now().millisecondsSinceEpoch;
    } else {
      _idleSinceMs = null;
    }
  }

  /// Phase 29 — periodic check; closes the shard with reason
  /// [ShardCloseReason.idle] if it has been fully empty for the
  /// configured timeout.
  void _checkIdleSession(int timeoutMs) {
    if (closed) return;
    final since = _idleSinceMs;
    if (since == null) return;
    if (peers.isNotEmpty || bridges.isNotEmpty) {
      _idleSinceMs = null;
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - since >= timeoutMs) {
      _shutdown(ShardCloseReason.idle);
    }
  }

  /// Phase 15 — schedule the idle-bridge sweeper if configured and
  /// not already running.
  void _ensureBridgeReaper() {
    final timeoutMs = config.bridgeIdleTimeoutMs;
    if (timeoutMs == null || timeoutMs <= 0) return;
    if (_bridgeReaper != null) return;
    // Sweep at ~1/4 of the timeout so worst-case lateness ≤ timeout/4.
    final sweepMs = (timeoutMs ~/ 4).clamp(250, 5000);
    _bridgeReaper = Timer.periodic(
      Duration(milliseconds: sweepMs),
      (_) => _reapIdleBridges(timeoutMs),
    );
  }

  void _reapIdleBridges(int timeoutMs) {
    if (closed || bridges.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final stale = <_CascadeBridge>[];
    for (final b in bridges.values) {
      if (now - b.lastInboundAtMs > timeoutMs) stale.add(b);
    }
    for (final b in stale) {
      // close() drives RelayPeer.onClosed → our onClosed handler
      // removes [b] from [bridges] and emits the bridgeClosed event.
      b.close();
    }
  }

  /// Phase 19 — schedule the keepalive emitter if configured.
  void _ensureBridgeKeepalive() {
    final intervalMs = config.bridgeKeepaliveMs;
    if (intervalMs == null || intervalMs <= 0) return;
    if (_bridgeKeepalive != null) return;
    _bridgeKeepalive = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) => _emitKeepalivePings(),
    );
  }

  void _emitKeepalivePings() {
    if (closed || bridges.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final b in bridges.values) {
      if (!b.relay.established) continue;
      final nonce = ++_keepaliveNonce;
      try {
        b.transport.sendControl({
          'type': RelayMsgType.ping,
          'nonce': nonce,
        });
      } catch (_) {
        continue;
      }
      // Phase 20 — remember when we sent each ping so we can compute
      // RTT when the pong arrives. Cap the outstanding map so a
      // wedged peer can't grow it without bound.
      b.pendingPings[nonce] = now;
      if (b.pendingPings.length > 64) {
        final oldest = b.pendingPings.keys.first;
        b.pendingPings.remove(oldest);
      }
    }
  }

  static List<SdpCodec> _materialiseCodecs(List<ShardCodec> tags) {
    final out = <SdpCodec>[];
    for (final t in tags) {
      switch (t) {
        case ShardCodec.vp8:
          out.add(Vp8Codec());
        case ShardCodec.vp9:
          out.add(Vp9Codec());
        case ShardCodec.h264:
          out.add(H264Codec());
        case ShardCodec.pcmu:
          out.add(PcmuCodec());
        case ShardCodec.pcma:
          out.add(PcmaCodec());
      }
    }
    return out;
  }
}

// ===================================================================
// Worker-side cascade bridge plumbing.
// ===================================================================

/// Synthetic [RelayTransport] living inside the worker. Every send
/// becomes a [CascadeOutboundEvent] back to main; every receive
/// arriving via the `relayIn` RPC is fanned into the appropriate
/// [RelayPeer] callback.
class _BridgeTransport implements RelayTransport {
  final String bridgeId;
  final _ShardWorker worker;

  void Function(Map<String, Object?> msg)? _onControl;
  void Function(Uint8List pkt)? _onRtp;
  void Function(Uint8List pkt)? _onRtcp;
  bool _closed = false;

  _BridgeTransport({required this.bridgeId, required this.worker});

  @override
  set onControl(void Function(Map<String, Object?> msg) cb) => _onControl = cb;

  @override
  set onRtp(void Function(Uint8List pkt) cb) => _onRtp = cb;

  @override
  set onRtcp(void Function(Uint8List pkt) cb) => _onRtcp = cb;

  @override
  void sendControl(Map<String, Object?> msg) {
    if (_closed) return;
    final json = utf8JsonEncode(msg);
    worker.emitRelayOut(bridgeId, CascadeRelayKind.control, json);
  }

  @override
  void sendRtp(Uint8List pkt) {
    if (_closed) return;
    worker.emitRelayOut(bridgeId, CascadeRelayKind.rtp, pkt);
  }

  @override
  void sendRtcp(Uint8List pkt) {
    if (_closed) return;
    worker.emitRelayOut(bridgeId, CascadeRelayKind.rtcp, pkt);
  }

  @override
  Future<void> close() async {
    _closed = true;
  }

  /// Called by the worker when a frame arrives from main for this
  /// bridge.
  void receive(CascadeRelayKind kind, Uint8List bytes) {
    if (_closed) return;
    switch (kind) {
      case CascadeRelayKind.control:
        final cb = _onControl;
        if (cb == null) return;
        try {
          final decoded = utf8JsonDecode(bytes);
          if (decoded is Map<String, Object?>) cb(decoded);
        } catch (_) {
          // bad control frame — drop
        }
      case CascadeRelayKind.rtp:
        _onRtp?.call(bytes);
      case CascadeRelayKind.rtcp:
        _onRtcp?.call(bytes);
    }
  }
}

/// Bookkeeping for one cascade bridge inside the worker.
class _CascadeBridge {
  final String bridgeId;
  final CascadeBridgeRole role;
  final _BridgeTransport transport;
  final RelayPeer relay;
  final Session session;
  final List<RelayExport> exports = [];

  /// Count of RTP packets received from the remote side over this
  /// bridge (origin-side: 0; downstream-side: matches what the remote
  /// SFU forwarded). Useful for end-to-end media tests.
  int inboundRtpPackets = 0;
  bool _established = false;

  /// Phase 15 — wall-clock (ms since epoch) when this bridge was
  /// attached, and when the last inbound frame (control/RTP/RTCP)
  /// arrived. Used by the worker's idle-bridge reaper and exposed
  /// via [_ShardWorker._bridgeStats].
  final int createdAtMs = DateTime.now().millisecondsSinceEpoch;
  int lastInboundAtMs = DateTime.now().millisecondsSinceEpoch;

  /// Phase 20 — outstanding keepalive pings: nonce → sentAtMs.
  /// Filled by [_ShardWorker._emitKeepalivePings] and drained by
  /// pong arrivals in [_ShardWorker._maybeRecordPongRtt].
  final Map<int, int> pendingPings = {};

  /// Phase 20 — most-recent and EWMA round-trip time (ms) measured
  /// from the keepalive ping/pong. Null until the first pong.
  int? lastRttMs;
  double? rttEwmaMs;

  /// Phase 21 — throughput counters split by direction and frame
  /// kind. TX is what we sent toward the remote (via [_BridgeTransport]
  /// send paths); RX is what arrived through the worker's `_relayIn`.
  int txControlPackets = 0;
  int txControlBytes = 0;
  int txRtpPackets = 0;
  int txRtpBytes = 0;
  int txRtcpPackets = 0;
  int txRtcpBytes = 0;
  int rxControlPackets = 0;
  int rxControlBytes = 0;
  int rxRtpPackets = 0;
  int rxRtpBytes = 0;
  int rxRtcpPackets = 0;
  int rxRtcpBytes = 0;

  _CascadeBridge({
    required this.bridgeId,
    required this.role,
    required this.transport,
    required this.relay,
    required this.session,
  });

  /// Idempotently push every (eligible) producer in the session up the
  /// relay so the remote side can fan it out. Eligibility:
  ///
  /// * Real peers' publisher receivers — always exported.
  /// * Receivers introduced by *other* cascade bridges — exported,
  /// so two non-owner SFUs cascading through the same owner can
  /// reach each other (full-mesh).
  /// * Receivers from *this* bridge's relay — skipped (loop
  /// prevention).
  void exportLocalProducers() {
    _established = true;
    final existing = exports.map((e) => e.mid).toSet();
    // Drop exports whose underlying receiver has been removed (e.g.
    // the originating bridge tore down). Cheap; runs at sweep time.
    exports.removeWhere((e) => e.isStopped);
    final selfRemote = relay.remoteId;
    for (final router in session.routers) {
      // Don't echo our own bridge's relay receivers back.
      if (router.peerId == selfRemote) continue;
      for (final recv in router.receivers) {
        final mid = recv.stream.mid;
        if (existing.contains(mid)) continue;
        try {
          final exp = relay.exportReceiver(recv);
          exports.add(exp);
          existing.add(mid);
        } catch (_) {
          // best-effort
        }
      }
    }
    // Re-sweep on every new peer that joins (covers a real publisher
    // arriving after the cascade is up).
    final prev = session.onPeerJoined;
    session.onPeerJoined = (p) {
      prev?.call(p);
      if (_established) exportLocalProducers();
    };
  }

  Future<void> close() async {
    for (final e in exports.toList()) {
      try {
        e.stop();
      } catch (_) {}
    }
    exports.clear();
    try {
      await relay.close();
    } catch (_) {}
  }
}

/// Tiny JSON helpers — kept here so we don't pull in `dart:convert` at
/// the top of the file twice.
Uint8List utf8JsonEncode(Object? value) {
  return Uint8List.fromList(_jsonUtf8.encode(value));
}

Object? utf8JsonDecode(Uint8List bytes) {
  return _jsonUtf8.decode(bytes);
}

final _jsonUtf8 = _Utf8JsonCodec();

class _Utf8JsonCodec {
  List<int> encode(Object? value) =>
      const Utf8Encoder().convert(const JsonEncoder().convert(value));
  Object? decode(List<int> bytes) =>
      const JsonDecoder().convert(const Utf8Decoder().convert(bytes));
}
