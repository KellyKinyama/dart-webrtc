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

  bool _closed = false;

  ClusterCoordinator({
    required this.sharded,
    required this.hub,
    required this.locator,
    void Function(String line)? log,
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
      );
    };
    // Wire up the upstream endpoint as soon as the shard is born.
    sharded.onShardCreated = (shard) {
      final owner = locator.ownerOf(shard.sessionId);
      if (owner == null || owner.id == locator.selfId) return;
      final host = InternetAddress(owner.host);
      _registerOutboundRoute(
        shard: shard,
        bridgeId: 'upstream',
        host: host,
        port: owner.relayPort,
      );
      // Trigger the worker-side attach now that we're already
      // subscribed to its event stream.
      shard
          .cascadeAttach(
        bridgeId: 'upstream',
        role: CascadeBridgeRole.outbound,
        remoteId: 'cluster:${locator.selfId}:${shard.sessionId}',
      )
          .catchError((Object e) {
        this.log('upstream attach failed for ${shard.sessionId}: $e');
      });
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
        },
      });
    }
    return out;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
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
  }

  void _reapShard(String sessionId) {
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
