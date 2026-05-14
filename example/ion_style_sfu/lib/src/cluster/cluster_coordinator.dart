// Phase 12 — main-isolate orchestrator that bridges the per-session
// worker shards to the cluster's UDP relay hub.
//
// Responsibilities:
//   * For sessions whose owner (per [RoomLocator]) is not us: ensure
//     the shard's `ShardConfig` carries the upstream cascade fields
//     so the worker auto-attaches an outbound relay bridge on boot.
//   * For inbound `cascade-hello`s from unknown SFUs: get-or-create
//     the matching shard, attach an inbound relay bridge, and start
//     pumping packets between the UDP socket and the worker.
//   * For every [CascadeOutboundEvent] surfaced by a worker: ship the
//     payload over the corresponding UDP relay endpoint.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../cascade_event.dart';
import '../session_shard.dart';
import '../sharded_sfu.dart';
import 'locator.dart';
import 'udp_relay_transport.dart';

/// Snapshot record for `/healthz`-style introspection.
class CascadeBridgeSnapshot {
  final String sessionId;
  final String bridgeId;
  final CascadeBridgeRole role;
  final String remoteHost;
  final int remotePort;
  const CascadeBridgeSnapshot({
    required this.sessionId,
    required this.bridgeId,
    required this.role,
    required this.remoteHost,
    required this.remotePort,
  });

  Map<String, Object?> toJson() => {
        'sessionId': sessionId,
        'bridgeId': bridgeId,
        'role': role.name,
        'remote': '$remoteHost:$remotePort',
      };
}

class _BridgeRoute {
  final SessionShard shard;
  final String bridgeId;
  final InternetAddress host;
  final int port;
  _BridgeRoute(this.shard, this.bridgeId, this.host, this.port);
}

class ClusterCoordinator {
  final ShardedSfu sharded;
  final UdpRelayHub hub;
  final RoomLocator locator;
  final void Function(String line) log;

  /// endpointKey (`host:port`) → route record. Used to forward inbound
  /// UDP packets to the right worker bridge.
  final Map<String, _BridgeRoute> _byEndpoint = {};

  /// `${sessionId}:${bridgeId}` → endpointKey for outbound shipping.
  final Map<String, String> _byBridge = {};

  /// Phase 22 — in-flight upstream-reconnect attempts keyed by
  /// `${sessionId}:${bridgeId}`. Each entry tracks the timer plus
  /// the consecutive-failure count, used to grow the backoff.
  final Map<String, _ReconnectAttempt> _reconnects = {};

  /// Phase 23 — consecutive-failure tally per upstream bridge
  /// (`sessionId`). Reset to 0 on the first successful establish;
  /// drives the backoff in [_scheduleUpstreamReconnect] and the
  /// circuit breaker in [upstreamReconnectMaxAttempts].
  final Map<String, int> _consecutiveFailures = {};

  /// Phase 22 — maximum reconnect backoff (ms). Capped to keep
  /// recovery snappy after a transient blip.
  static const int _reconnectMaxDelayMs = 5000;

  /// Phase 22 — base backoff for the first retry; doubled on every
  /// consecutive failure up to [_reconnectMaxDelayMs].
  static const int _reconnectBaseDelayMs = 100;

  /// Phase 23 — give up on an upstream bridge after this many
  /// consecutive failed reconnect attempts. Null = retry forever.
  /// Configurable per coordinator instance.
  final int? upstreamReconnectMaxAttempts;

  /// Phase 22 — monotonic counters surfaced via [/cluster] and
  /// Prometheus.
  int upstreamReconnectAttempts = 0;
  int upstreamReconnectsSucceeded = 0;

  /// Phase 23 — number of upstream bridges abandoned after hitting
  /// [upstreamReconnectMaxAttempts].
  int upstreamReconnectsGivenUp = 0;

  bool _closed = false;

  ClusterCoordinator({
    required this.sharded,
    required this.hub,
    required this.locator,
    void Function(String line)? log,
    this.upstreamReconnectMaxAttempts,
  }) : log = log ?? ((l) => stderr.writeln('[cluster] $l')) {
    // Inject upstream cascade fields into every non-owner shard.
    sharded.configure = (base) {
      final owner = locator.ownerOf(base.sessionId);
      if (owner == null || owner.id == locator.selfId) return base;
      return ShardConfig(
        sessionId: base.sessionId,
        bindAddress: base.bindAddress,
        rtpBasePort: base.rtpBasePort,
        announceAddress: base.announceAddress,
        videoCodecs: base.videoCodecs,
        audioCodecs: base.audioCodecs,
        quiet: base.quiet,
        selfSfuId: locator.selfId,
        upstreamSfuId: owner.id,
        upstreamHost: owner.host,
        upstreamPort: owner.relayPort,
        bridgeIdleTimeoutMs: base.bridgeIdleTimeoutMs,
        bridgeKeepaliveMs: base.bridgeKeepaliveMs,
        maxPeersPerSession: base.maxPeersPerSession,
      );
    };
    // Wire up the upstream endpoint as soon as the shard is born.
    sharded.onShardCreated = (shard) {
      final owner = locator.ownerOf(shard.sessionId);
      if (owner == null || owner.id == locator.selfId) return;
      final host = InternetAddress(owner.host);
      // Phase 23 — go through the verified-attach path so the
      // probe-then-detect-failure flow runs on the first try too.
      // _attemptUpstreamReconnect handles route registration and
      // failure-counter bookkeeping in one place. The initial
      // attach is *not* a reconnect, so suppress the reconnect
      // counter bump.
      _attemptUpstreamReconnect(shard, host, owner.relayPort, 0,
          isReconnect: false);
    };
    // Inbound: stranger sent us a control frame. We only attach if
    // it's a cascade-hello (we need a session id).
    hub.onUnknownPeer = _onUnknownPeer;
    // Surface every worker's outbound cascade events to UDP.
    final prev = sharded.onEvent;
    sharded.onEvent = (event) {
      prev?.call(event);
      if (event is CascadeOutboundEvent) {
        _onCascadeOutbound(event);
      } else if (event is CascadeBridgeClosedEvent) {
        _onBridgeClosed(event.sessionId, event.bridgeId);
      } else if (event is ShardClosedEvent) {
        _reapShard(event.sessionId);
      }
    };
  }

  /// Snapshot of every active bridge. Cheap; safe for `/healthz`.
  List<CascadeBridgeSnapshot> snapshot() {
    final out = <CascadeBridgeSnapshot>[];
    for (final r in _byEndpoint.values) {
      out.add(CascadeBridgeSnapshot(
        sessionId: r.shard.sessionId,
        bridgeId: r.bridgeId,
        role: r.bridgeId == 'upstream'
            ? CascadeBridgeRole.outbound
            : CascadeBridgeRole.inbound,
        remoteHost: r.host.address,
        remotePort: r.port,
      ));
    }
    return out;
  }

  /// Phase 15 — detailed snapshot. Combines the coordinator's route
  /// view (host:port) with each worker's per-bridge stats (RTP
  /// counters, established flag, last inbound timestamp). Async
  /// because it RPCs into every shard with a live bridge.
  Future<List<Map<String, Object?>>> detailedSnapshot() async {
    if (_byEndpoint.isEmpty) return const [];
    final bySession = <String, _BridgeRoute>{};
    final routes = <_BridgeRoute>[];
    final shards = <SessionShard>{};
    for (final r in _byEndpoint.values) {
      routes.add(r);
      bySession['${r.shard.sessionId}:${r.bridgeId}'] = r;
      shards.add(r.shard);
    }
    // One RPC per shard, in parallel.
    final perShard = await Future.wait(
      shards.map((s) => s.cascadeBridgeStats().then(
            (stats) => MapEntry(s.sessionId, stats),
            onError: (Object _) =>
                MapEntry<String, List<Map<String, Object?>>>(s.sessionId, []),
          )),
    );
    final statByKey = <String, Map<String, Object?>>{};
    for (final entry in perShard) {
      for (final s in entry.value) {
        final bid = s['bridgeId'] as String?;
        if (bid == null) continue;
        statByKey['${entry.key}:$bid'] = s;
      }
    }
    final out = <Map<String, Object?>>[];
    for (final r in routes) {
      final key = '${r.shard.sessionId}:${r.bridgeId}';
      final s = statByKey[key];
      out.add({
        'sessionId': r.shard.sessionId,
        'bridgeId': r.bridgeId,
        'role': (r.bridgeId == 'upstream'
                ? CascadeBridgeRole.outbound
                : CascadeBridgeRole.inbound)
            .name,
        'remote': '${r.host.address}:${r.port}',
        if (s != null) ...{
          'remoteId': s['remoteId'],
          'established': s['established'],
          'exports': s['exports'],
          'relayedReceivers': s['relayedReceivers'],
          'inboundRtpPackets': s['inboundRtpPackets'],
          'createdAtMs': s['createdAtMs'],
          'lastInboundAtMs': s['lastInboundAtMs'],
          'idleMs': s['idleMs'],
          // Phase 20 — relay RTT measured from keepalive ping/pong.
          'lastRttMs': s['lastRttMs'],
          'rttEwmaMs': s['rttEwmaMs'],
          'pendingPings': s['pendingPings'],
          // Phase 21 — throughput counters (TX/RX × control/RTP/RTCP).
          'txControlPackets': s['txControlPackets'],
          'txControlBytes': s['txControlBytes'],
          'txRtpPackets': s['txRtpPackets'],
          'txRtpBytes': s['txRtpBytes'],
          'txRtcpPackets': s['txRtcpPackets'],
          'txRtcpBytes': s['txRtcpBytes'],
          'rxControlPackets': s['rxControlPackets'],
          'rxControlBytes': s['rxControlBytes'],
          'rxRtpPackets': s['rxRtpPackets'],
          'rxRtpBytes': s['rxRtpBytes'],
          'rxRtcpPackets': s['rxRtcpPackets'],
          'rxRtcpBytes': s['rxRtcpBytes'],
        },
      });
    }
    return out;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // Phase 22 — cancel any pending reconnect timers.
    for (final r in _reconnects.values) {
      r.timer.cancel();
    }
    _reconnects.clear();
    _byEndpoint.clear();
    _byBridge.clear();
    await hub.close();
  }

  // -----------------------------------------------------------------

  void _registerOutboundRoute({
    required SessionShard shard,
    required String bridgeId,
    required InternetAddress host,
    required int port,
  }) {
    final key = '${host.address}:$port';
    _byEndpoint[key] = _BridgeRoute(shard, bridgeId, host, port);
    _byBridge['${shard.sessionId}:$bridgeId'] = key;
    _bindEndpointCallbacks(host, port, shard, bridgeId);
  }

  void _bindEndpointCallbacks(
    InternetAddress host,
    int port,
    SessionShard shard,
    String bridgeId,
  ) {
    final ep = hub.endpointTo(host, port);
    ep
      ..onControl = (msg) {
        try {
          final json = utf8.encode(jsonEncode(msg));
          shard.deliverRelayInbound(
            bridgeId,
            CascadeRelayKind.control,
            Uint8List.fromList(json),
          );
        } catch (_) {}
      }
      ..onRtp = (pkt) {
        shard.deliverRelayInbound(bridgeId, CascadeRelayKind.rtp, pkt);
      }
      ..onRtcp = (pkt) {
        shard.deliverRelayInbound(bridgeId, CascadeRelayKind.rtcp, pkt);
      };
  }

  void _onCascadeOutbound(CascadeOutboundEvent ev) {
    final key = _byBridge['${ev.sessionId}:${ev.bridgeId}'];
    if (key == null) return;
    final route = _byEndpoint[key];
    if (route == null) return;
    final ep = hub.endpointTo(route.host, route.port);
    final bytes = ev.bytes is Uint8List
        ? ev.bytes as Uint8List
        : Uint8List.fromList(ev.bytes);
    switch (ev.kind) {
      case CascadeRelayKind.control:
        try {
          final m = jsonDecode(utf8.decode(bytes));
          if (m is Map<String, Object?>) ep.sendControl(m);
        } catch (_) {}
      case CascadeRelayKind.rtp:
        ep.sendRtp(bytes);
      case CascadeRelayKind.rtcp:
        ep.sendRtcp(bytes);
    }
  }

  void _onBridgeClosed(String sessionId, String bridgeId) {
    final key = _byBridge.remove('$sessionId:$bridgeId');
    if (key == null) return;
    final route = _byEndpoint.remove(key);
    if (route != null) {
      // Drop the hub endpoint as well so a subsequent packet from
      // the same host:port surfaces as `onUnknownPeer` rather than
      // landing on the dead endpoint's callbacks.
      hub.closeEndpoint(route.host, route.port);
    }
    // Phase 22 — if this was the upstream bridge for a still-live
    // shard whose owner is still in the locator, schedule a
    // re-attach with capped exponential backoff. Inbound bridges
    // are not retried (the remote side will re-hello).
    if (bridgeId == 'upstream' && route != null) {
      final attempts = _consecutiveFailures[sessionId] ?? 0;
      _scheduleUpstreamReconnect(
        shard: route.shard,
        host: route.host,
        port: route.port,
        attempts: attempts,
      );
    }
  }

  // ---- Phase 22 — upstream auto-reconnect ----

  void _scheduleUpstreamReconnect({
    required SessionShard shard,
    required InternetAddress host,
    required int port,
    required int attempts,
  }) {
    if (_closed) return;
    // Re-check ownership: if the locator no longer points at this
    // host:port (e.g. owner was removed from the cluster), abort.
    final owner = locator.ownerOf(shard.sessionId);
    if (owner == null ||
        owner.id == locator.selfId ||
        owner.host != host.address ||
        owner.relayPort != port) {
      return;
    }
    // Phase 23 — circuit breaker. After N consecutive failures, stop
    // retrying and bump the give-up counter. The shard is left in
    // place so a subsequent locator change (peer comes back) can
    // reattach explicitly via onShardCreated when the session is
    // recreated, but in the meantime we don't burn timers.
    final cap = upstreamReconnectMaxAttempts;
    if (cap != null && attempts > cap) {
      upstreamReconnectsGivenUp++;
      log('upstream reconnect giving up for ${shard.sessionId} '
          'after $attempts attempts');
      // Phase 24 — the local non-owner shard is now permanently
      // useless (no upstream means no media). Reap it so subscribers
      // see a clean ShardClosedEvent and the worker isolate is
      // freed. Best-effort: a closeShard race is harmless because
      // ShardedSfu.closeShard is idempotent on a missing session.
      _consecutiveFailures.remove(shard.sessionId);
      sharded
          .closeShard(shard.sessionId,
              reason: ShardCloseReason.upstreamUnreachable)
          .catchError((Object e) {
        log('shard close after breaker trip failed for '
            '${shard.sessionId}: $e');
      });
      return;
    }
    final delayMs = _backoffMs(attempts);
    final key = '${shard.sessionId}:upstream';
    _reconnects[key]?.timer.cancel();
    final timer = Timer(Duration(milliseconds: delayMs), () {
      _reconnects.remove(key);
      _attemptUpstreamReconnect(shard, host, port, attempts);
    });
    _reconnects[key] = _ReconnectAttempt(timer, attempts);
  }

  static int _backoffMs(int attempts) {
    var d = _reconnectBaseDelayMs << attempts;
    if (d <= 0 || d > _reconnectMaxDelayMs) d = _reconnectMaxDelayMs;
    return d;
  }

  void _attemptUpstreamReconnect(
    SessionShard shard,
    InternetAddress host,
    int port,
    int attempts, {
    bool isReconnect = true,
  }) {
    if (_closed) return;
    // Owner may have moved between scheduling and firing.
    final owner = locator.ownerOf(shard.sessionId);
    if (owner == null ||
        owner.id == locator.selfId ||
        owner.host != host.address ||
        owner.relayPort != port) {
      return;
    }
    if (isReconnect) upstreamReconnectAttempts++;
    _registerOutboundRoute(
      shard: shard,
      bridgeId: 'upstream',
      host: host,
      port: port,
    );
    shard
        .cascadeAttach(
      bridgeId: 'upstream',
      role: CascadeBridgeRole.outbound,
      remoteId: 'cluster:${locator.selfId}:${shard.sessionId}',
    )
        .then((_) async {
      // Phase 23 — wait briefly for the relay handshake to complete.
      // If the owner is unreachable, the bridge will sit there
      // un-established, and we treat that as a failure so the
      // circuit breaker can eventually trip.
      final established = await _waitForUpstreamEstablished(
        shard,
        const Duration(milliseconds: 750),
      );
      if (_closed) return;
      if (established) {
        if (isReconnect) upstreamReconnectsSucceeded++;
        _consecutiveFailures.remove(shard.sessionId);
        log('upstream ${isReconnect ? 'reconnect' : 'attach'} ok '
            'for ${shard.sessionId} (attempts=${attempts + 1})');
        return;
      }
      // Bridge never established — force a clean close so the
      // bridgeClosed event re-enters _onBridgeClosed with the new
      // failure count.
      _consecutiveFailures[shard.sessionId] = attempts + 1;
      log('upstream reconnect did not establish for '
          '${shard.sessionId} (attempts=${attempts + 1})');
      try {
        await shard.cascadeDetach('upstream');
      } catch (_) {}
    }).catchError((Object e) {
      log('upstream reconnect failed for ${shard.sessionId}: $e');
      _consecutiveFailures[shard.sessionId] = attempts + 1;
      // Roll back the route we just installed so the next attempt
      // re-binds cleanly. _onBridgeClosed won't fire again since
      // the worker never accepted the attach.
      final epKey = '${host.address}:$port';
      _byEndpoint.remove(epKey);
      _byBridge.remove('${shard.sessionId}:upstream');
      hub.closeEndpoint(host, port);
      _scheduleUpstreamReconnect(
        shard: shard,
        host: host,
        port: port,
        attempts: attempts + 1,
      );
    });
  }

  /// Phase 23 — poll the worker for an established upstream bridge
  /// up to [timeout]. Returns true on the first success, false if
  /// the timeout elapses or the shard goes away.
  Future<bool> _waitForUpstreamEstablished(
    SessionShard shard,
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (!_closed && DateTime.now().isBefore(deadline)) {
      try {
        final stats = await shard.cascadeBridgeStats();
        for (final s in stats) {
          if (s['bridgeId'] == 'upstream' && s['established'] == true) {
            return true;
          }
        }
      } catch (_) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }

  void _reapShard(String sessionId) {
    // Phase 22 — cancel any pending reconnect for this shard.
    final reKey = '$sessionId:upstream';
    _reconnects.remove(reKey)?.timer.cancel();
    // Phase 23 — forget any stale failure tally.
    _consecutiveFailures.remove(sessionId);
    final dead = <String>[];
    for (final entry in _byBridge.entries) {
      if (entry.key.startsWith('$sessionId:')) dead.add(entry.key);
    }
    for (final k in dead) {
      final epKey = _byBridge.remove(k);
      if (epKey == null) continue;
      final route = _byEndpoint.remove(epKey);
      if (route != null) {
        hub.closeEndpoint(route.host, route.port);
      }
    }
  }

  void _onUnknownPeer(
    InternetAddress addr,
    int port,
    int type,
    Uint8List payload,
  ) {
    if (_closed) return;
    // We can only meaningfully handle a control frame here — RTP/RTCP
    // from an unknown peer is meaningless without a session context.
    if (type != 0) return;
    Map<String, Object?>? msg;
    try {
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is Map<String, Object?>) msg = decoded;
    } catch (_) {
      return;
    }
    if (msg == null) return;
    if (msg['type'] != 'cascade-hello') return;
    final sid = msg['sessionId'] as String?;
    final fromSfu = msg['fromSfu'] as String?;
    if (sid == null || sid.isEmpty) return;
    // Make sure we're actually the owner of this session.
    final owner = locator.ownerOf(sid);
    if (owner == null || owner.id != locator.selfId) {
      log('rejecting cascade-hello for $sid: not owner');
      return;
    }
    final bridgeId = 'inbound:${addr.address}:$port'
        '${fromSfu != null ? ':$fromSfu' : ''}';
    () async {
      try {
        final shard = await sharded.getOrCreate(sid);
        // Bind the route *first* so the shard's own answering frames
        // (helloAck, announces) flow back to the right endpoint.
        _byEndpoint['${addr.address}:$port'] =
            _BridgeRoute(shard, bridgeId, addr, port);
        _byBridge['${shard.sessionId}:$bridgeId'] = '${addr.address}:$port';
        _bindEndpointCallbacks(addr, port, shard, bridgeId);
        await shard.cascadeAttach(
          bridgeId: bridgeId,
          role: CascadeBridgeRole.inbound,
          remoteId: 'cluster:${fromSfu ?? '?'}:$sid',
        );
        // Re-deliver the original hello so the bridge sees it.
        shard.deliverRelayInbound(
          bridgeId,
          CascadeRelayKind.control,
          payload,
        );
      } catch (e) {
        log('inbound cascade attach failed for $sid: $e');
      }
    }();
  }
}

/// Phase 22 — bookkeeping for one in-flight upstream reconnect.
class _ReconnectAttempt {
  final Timer timer;
  final int attempts;
  _ReconnectAttempt(this.timer, this.attempts);
}
