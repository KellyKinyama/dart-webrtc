// Phase 10 — cross-host scaling primitives.
//
// [RoomLocator] decides which SFU in a cluster is the "owner" of a
// given session id. Each SFU in the cluster runs the same locator
// configured with the same peer list, so every node agrees on the
// owner without any coordination protocol.
//
// We use a consistent-hash ring (jump-consistent variant via a
// hash-ring with virtual nodes) so that adding/removing one SFU only
// reshuffles roughly `1/N` of the rooms. In production this is
// usually sufficient because SFUs are long-lived; for blue/green
// deploys, drain one SFU at a time so its rooms migrate to the next
// owner via the cascade subsystem rather than being dropped.

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// One SFU in the cluster.
class ClusterPeer {
  /// Stable id (typically `host:port`).
  final String id;

  /// Hostname or IP for control-plane (HTTP) and relay (UDP).
  final String host;

  /// HTTP/WebSocket port.
  final int httpPort;

  /// UDP port for SFU-to-SFU relay traffic.
  final int relayPort;

  const ClusterPeer({
    required this.id,
    required this.host,
    required this.httpPort,
    required this.relayPort,
  });

  /// Parse `host:httpPort:relayPort` (relay defaults to httpPort+1
  /// when omitted, mirroring the `--relay-port` CLI default).
  factory ClusterPeer.parse(String spec) {
    final parts = spec.split(':');
    if (parts.length < 2 || parts.length > 3) {
      throw FormatException('cluster peer spec must be host:httpPort'
          '[:relayPort], got "$spec"');
    }
    final host = parts[0];
    final http = int.parse(parts[1]);
    final relay = parts.length == 3 ? int.parse(parts[2]) : http + 1;
    return ClusterPeer(
      id: '$host:$http',
      host: host,
      httpPort: http,
      relayPort: relay,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'host': host,
        'httpPort': httpPort,
        'relayPort': relayPort,
      };

  @override
  String toString() => 'ClusterPeer($id, relay:$relayPort)';
}

/// Consistent-hash ring over [ClusterPeer]s. Stateless once
/// constructed; safe to share across isolates.
class RoomLocator {
  /// Number of virtual nodes per peer. Higher → smoother distribution
  /// and smaller resharding when membership changes; default 64 keeps
  /// the ring small enough for `O(log N)` lookups even with hundreds
  /// of peers.
  final int virtualNodesPerPeer;

  /// Stable membership snapshot. Keyed by id for [self] lookups.
  final Map<String, ClusterPeer> peers;

  /// This SFU's own id. May be absent from [peers] for read-only
  /// callers (e.g. a CLI tool that only inspects the cluster).
  final String? selfId;

  // (hash, peer-id) pairs sorted by hash. Built once at construction.
  final List<int> _ringHashes;
  final List<String> _ringPeerIds;

  RoomLocator({
    required Iterable<ClusterPeer> peers,
    this.selfId,
    this.virtualNodesPerPeer = 64,
  })  : peers = {for (final p in peers) p.id: p},
        _ringHashes = <int>[],
        _ringPeerIds = <String>[] {
    final ring = <_RingPoint>[];
    for (final p in this.peers.values) {
      for (var i = 0; i < virtualNodesPerPeer; i++) {
        ring.add(_RingPoint(_hash('${p.id}#$i'), p.id));
      }
    }
    ring.sort((a, b) => a.hash.compareTo(b.hash));
    for (final r in ring) {
      _ringHashes.add(r.hash);
      _ringPeerIds.add(r.peerId);
    }
  }

  /// Number of peers in the cluster (counting self if it's in [peers]).
  int get size => peers.length;

  /// Owner of [sessionId]. Returns null only when the cluster is
  /// empty.
  ClusterPeer? ownerOf(String sessionId) {
    if (_ringHashes.isEmpty) return null;
    final h = _hash(sessionId);
    final idx = _lowerBound(_ringHashes, h);
    final pickIdx = idx == _ringHashes.length ? 0 : idx;
    return peers[_ringPeerIds[pickIdx]];
  }

  /// True iff this SFU owns [sessionId].
  bool isOwner(String sessionId) {
    final id = selfId;
    if (id == null) return false;
    final owner = ownerOf(sessionId);
    return owner != null && owner.id == id;
  }

  /// 32-bit unsigned int derived from the first four bytes of
  /// SHA-256(s). Picked over a hand-rolled hash because the cluster
  /// ring needs a uniform distribution across short strings — FNV-1a
  /// gives very uneven placement when the inputs share long prefixes
  /// (e.g. `host:port#i`).
  static int _hash(String s) {
    final d = sha256.convert(utf8.encode(s)).bytes;
    return ((d[0] << 24) | (d[1] << 16) | (d[2] << 8) | d[3]) & 0xffffffff;
  }

  /// Standard lower_bound on a sorted int list.
  static int _lowerBound(List<int> sorted, int target) {
    var lo = 0;
    var hi = sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sorted[mid] < target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

class _RingPoint {
  final int hash;
  final String peerId;
  const _RingPoint(this.hash, this.peerId);
}
