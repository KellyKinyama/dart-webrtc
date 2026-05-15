// Phase 11 — sharded SFU registry. The only top-level SFU object the
// signaling server should hold; spawns and reaps one [SessionShard]
// per session id.
//
// Each shard owns a non-overlapping slice of UDP ports starting at
// `rtpBasePort + slot * portsPerShard`. The orchestrator hands out
// slots monotonically; freed slots are not currently reused (Dart
// transports are short-lived enough that exhausting the 16-bit port
// space requires sustained churn — when that becomes a real concern
// we can add a free-list).

import 'dart:async';
import 'dart:io';

import 'session_shard.dart';
import 'stats/stats.dart';

/// Per-shard configuration template. A new [ShardConfig] is built per
/// session by combining this template with the session id and an
/// allocated port slot.
class ShardConfigTemplate {
  final String bindAddress;
  final int rtpBasePort;
  final String? announceAddress;
  final List<ShardCodec> videoCodecs;
  final List<ShardCodec> audioCodecs;
  final int portsPerShard;
  final bool quiet;

  /// Phase 15 — propagated as [ShardConfig.bridgeIdleTimeoutMs].
  final int? bridgeIdleTimeoutMs;

  /// Phase 19 — propagated as [ShardConfig.bridgeKeepaliveMs].
  final int? bridgeKeepaliveMs;

  /// Phase 25 — hard cap on the number of live shards (sessions)
  /// per node. Null = unlimited (the pre-Phase-25 default). Hitting
  /// the cap causes [ShardedSfu.getOrCreate] to throw
  /// [SfuOverloadedException], which the signaling layer translates
  /// to HTTP 503.
  final int? maxSessions;

  /// Phase 25 — propagated as [ShardConfig.maxPeersPerSession].
  /// Null = unlimited. Worker rejects further join() calls past this
  /// cap with a SessionFullException.
  final int? maxPeersPerSession;

  /// Phase 29 — propagated as [ShardConfig.idleSessionTimeoutMs].
  /// Null = disabled. Worker periodically closes shards that have
  /// been fully empty (no peers, no cascade bridges) for longer
  /// than this many milliseconds.
  final int? idleSessionTimeoutMs;

  /// STUN / TURN URLs propagated to every Publisher / Subscriber
  /// `RTCPeerConnection` as `RTCConfiguration.iceServers`. Drives
  /// server-reflexive (`srflx`) candidate gathering on each PC; the
  /// gathered candidates are trickled to clients via the existing
  /// `IceCandidateEvent` → `trickle` signaling path.
  final List<String> iceServerUrls;

  const ShardConfigTemplate({
    required this.bindAddress,
    required this.rtpBasePort,
    this.announceAddress,
    this.videoCodecs = const [ShardCodec.vp8],
    this.audioCodecs = const [ShardCodec.pcmu],
    this.portsPerShard = 64,
    this.quiet = false,
    this.bridgeIdleTimeoutMs,
    this.bridgeKeepaliveMs,
    this.maxSessions,
    this.maxPeersPerSession,
    this.idleSessionTimeoutMs,
    this.iceServerUrls = const [],
  });
}

/// Phase 25 — thrown by [ShardedSfu.getOrCreate] when the per-node
/// session cap is reached. Translated to HTTP 503 by the signaling
/// layer.
class SfuOverloadedException implements Exception {
  final String message;
  const SfuOverloadedException(this.message);
  @override
  String toString() => 'SfuOverloadedException: $message';
}

/// Per-session-isolate registry.
class ShardedSfu {
  final ShardConfigTemplate template;
  final Map<String, SessionShard> _shards = {};
  final Map<String, Future<SessionShard>> _spawning = {};
  int _nextSlot = 0;
  bool _closed = false;

  /// Optional global event listener, invoked for *every* shard's
  /// events. Useful for the signaling layer's WS broadcast logic.
  void Function(ShardEvent event)? onEvent;

  /// Optional callback invoked when a shard self-closes (peer count
  /// dropped to zero). The orchestrator reaps the shard and removes
  /// it from the registry; this hook lets the signaling layer drop
  /// any remaining bookkeeping.
  void Function(String sessionId)? onShardClosed;

  /// Optional callback invoked the first time a shard is materialised
  /// for a given session id. The cluster coordinator uses this to
  /// open the upstream cascade bridge when this SFU isn't the owner.
  void Function(SessionShard shard)? onShardCreated;

  /// Optional override for the per-shard config produced by
  /// [getOrCreate]. Receives the default [ShardConfig] and returns a
  /// possibly-augmented one (used to inject upstream cascade fields).
  ShardConfig Function(ShardConfig base)? configure;

  ShardedSfu(this.template);

  /// Phase 25 — monotonic counter of session-spawn attempts that
  /// were rejected because the per-node cap was already hit.
  int sessionsRejectedAtCap = 0;

  /// Live shards (snapshot).
  Iterable<SessionShard> get shards => _shards.values;
  int get shardCount => _shards.length;

  /// Get-or-create a shard for [sessionId].
  Future<SessionShard> getOrCreate(String sessionId) {
    if (_closed) {
      throw StateError('ShardedSfu is closed');
    }
    final existing = _shards[sessionId];
    if (existing != null) return Future.value(existing);
    final pending = _spawning[sessionId];
    if (pending != null) return pending;
    // Phase 25 — honour the per-node session cap.
    final cap = template.maxSessions;
    if (cap != null && _shards.length + _spawning.length >= cap) {
      sessionsRejectedAtCap++;
      throw SfuOverloadedException(
          'session cap reached ($cap) — cannot spawn $sessionId');
    }
    final slot = _nextSlot++;
    final base = ShardConfig(
      sessionId: sessionId,
      bindAddress: template.bindAddress,
      rtpBasePort: template.rtpBasePort + slot * template.portsPerShard,
      announceAddress: template.announceAddress,
      videoCodecs: template.videoCodecs,
      audioCodecs: template.audioCodecs,
      quiet: template.quiet,
      bridgeIdleTimeoutMs: template.bridgeIdleTimeoutMs,
      bridgeKeepaliveMs: template.bridgeKeepaliveMs,
      maxPeersPerSession: template.maxPeersPerSession,
      idleSessionTimeoutMs: template.idleSessionTimeoutMs,
      iceServerUrls: template.iceServerUrls,
    );
    final cfg = configure?.call(base) ?? base;
    final f = SessionShard.spawn(cfg).then((shard) {
      _shards[sessionId] = shard;
      _spawning.remove(sessionId);
      shard.events.listen(
        (e) => _onShardEvent(shard, e),
        onError: (_) {},
      );
      onShardCreated?.call(shard);
      return shard;
    }, onError: (e) {
      _spawning.remove(sessionId);
      throw e;
    });
    _spawning[sessionId] = f;
    return f;
  }

  /// Look up an existing shard without spawning.
  SessionShard? get(String sessionId) => _shards[sessionId];

  /// Phase 24 — sessions whose close event we already synthesized
  /// via [closeShard]. The worker's own ShardClosedEvent that
  /// arrives a moment later is suppressed so subscribers don't see
  /// the close twice.
  final Set<String> _suppressNextCloseEvent = {};

  /// Tear a single shard down.
  ///
  /// [reason] is surfaced to subscribers via a synthetic
  /// [ShardClosedEvent] so callers can distinguish, e.g., a Phase 24
  /// circuit-breaker close from a normal idle shutdown. Defaults to
  /// [ShardCloseReason.mainRequested] for backwards compatibility.
  Future<void> closeShard(
    String sessionId, {
    ShardCloseReason reason = ShardCloseReason.mainRequested,
    String? message,
  }) async {
    final s = _shards.remove(sessionId);
    if (s == null) return;
    // Emit the synthetic close event *before* the actual teardown so
    // subscribers always see the reason we intended (the worker's
    // own close path would surface mainRequested).
    _suppressNextCloseEvent.add(sessionId);
    onEvent?.call(ShardClosedEvent(
      sessionId: sessionId,
      reason: reason,
      message: message,
    ));
    onShardClosed?.call(sessionId);
    await s.close();
  }

  /// Aggregate `/stats` across every live shard.
  ///
  /// Returns the same shape as [snapshotSfu], summed across shards.
  Future<Map<String, Object?>> aggregateSnapshotJson() async {
    if (_shards.isEmpty) {
      return _emptySnapshot();
    }
    final snaps = await Future.wait(
      _shards.values.map((s) => s.snapshotJson()),
    );
    var sessions = 0;
    var peers = 0;
    var routers = 0;
    var downTracks = 0;
    var bytes = 0;
    var packets = 0;
    final tracks = <Object?>[];
    final bwe = <Object?>[];
    for (final s in snaps) {
      sessions += (s['sessions'] as int? ?? 0);
      peers += (s['peers'] as int? ?? 0);
      routers += (s['routers'] as int? ?? 0);
      downTracks += (s['downTracks'] as int? ?? 0);
      bytes += (s['totalBytesForwarded'] as int? ?? 0);
      packets += (s['totalPacketsForwarded'] as int? ?? 0);
      tracks.addAll((s['tracks'] as List?) ?? const []);
      bwe.addAll((s['subscriberBwe'] as List?) ?? const []);
    }
    return {
      'sessions': sessions,
      'peers': peers,
      'routers': routers,
      'downTracks': downTracks,
      'totalBytesForwarded': bytes,
      'totalPacketsForwarded': packets,
      'tracks': tracks,
      'subscriberBwe': bwe,
    };
  }

  /// Aggregate snapshot rehydrated as a real [SfuStatsSnapshot]
  /// suitable for [formatPrometheus].
  Future<SfuStatsSnapshot> aggregateSnapshot() async {
    final j = await aggregateSnapshotJson();
    return _snapshotFromJson(j);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final all = _shards.values.toList();
    _shards.clear();
    await Future.wait(all.map((s) => s.close()));
  }

  void _onShardEvent(SessionShard shard, ShardEvent event) {
    if (event is ShardClosedEvent &&
        _suppressNextCloseEvent.remove(shard.sessionId)) {
      // Phase 24 — closeShard() already emitted the synthetic event.
      // Still need to clean up local maps.
      _shards.remove(shard.sessionId);
      return;
    }
    onEvent?.call(event);
    if (event is ShardClosedEvent) {
      _shards.remove(shard.sessionId);
      onShardClosed?.call(shard.sessionId);
    }
  }

  static Map<String, Object?> _emptySnapshot() => {
        'sessions': 0,
        'peers': 0,
        'routers': 0,
        'downTracks': 0,
        'totalBytesForwarded': 0,
        'totalPacketsForwarded': 0,
        'tracks': <Object?>[],
        'subscriberBwe': <Object?>[],
      };
}

/// Rehydrate the JSON shape produced by [snapshotSfu] / aggregation
/// into a [SfuStatsSnapshot] so [formatPrometheus] can render it.
SfuStatsSnapshot _snapshotFromJson(Map<String, Object?> j) {
  final tracks = <DownTrackStats>[];
  for (final raw in (j['tracks'] as List? ?? const [])) {
    final t = (raw as Map).cast<String, Object?>();
    tracks.add(DownTrackStats(
      trackId: t['trackId'] as String,
      sessionId: t['sessionId'] as String,
      peerId: t['peerId'] as String,
      kind: t['kind'] as String,
      trackType: t['trackType'] as String,
      currentLayer: t['currentLayer'] as String,
      layerSwitches: t['layerSwitches'] as int,
      packetsForwarded: t['packetsForwarded'] as int,
      bytesForwarded: t['bytesForwarded'] as int,
      packetsDroppedWrongLayer: t['packetsDroppedWrongLayer'] as int,
      packetsTwccStamped: t['packetsTwccStamped'] as int,
      nackRetransmits: t['nackRetransmits'] as int,
      nackUpstreamRequested: t['nackUpstreamRequested'] as int,
    ));
  }
  final bwe = <SubscriberBweStats>[];
  for (final raw in (j['subscriberBwe'] as List? ?? const [])) {
    final b = (raw as Map).cast<String, Object?>();
    bwe.add(SubscriberBweStats(
      sessionId: b['sessionId'] as String,
      peerId: b['peerId'] as String,
      currentBps: b['currentBps'] as int,
    ));
  }
  return SfuStatsSnapshot(
    sessions: j['sessions'] as int,
    peers: j['peers'] as int,
    routers: j['routers'] as int,
    downTracks: j['downTracks'] as int,
    totalBytesForwarded: j['totalBytesForwarded'] as int,
    totalPacketsForwarded: j['totalPacketsForwarded'] as int,
    tracks: tracks,
    subscriberBwe: bwe,
  );
}

/// Async sleep helper used by integration tests; kept here so it's
/// trivially importable alongside the registry.
Future<void> microPause() => Future<void>.delayed(Duration.zero);

/// Re-export so consumers don't need to import `dart:io` for the bind
/// address when they construct a [ShardConfigTemplate] from a string.
InternetAddress parseBindAddress(String s) => InternetAddress(s);
