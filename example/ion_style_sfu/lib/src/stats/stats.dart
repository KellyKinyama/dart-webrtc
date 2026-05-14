// Stats — per-peer / per-track counters surfaced via `/metrics`.
//
// Phase 1 wires basic `bytesForwarded` / `packetsForwarded` from
// [DownTrack]. Later phases extend this with PLI/NACK/RTX counters and
// per-layer throughput from simulcast.

import '../sfu.dart';

class SfuStatsSnapshot {
  final int sessions;
  final int peers;
  final int routers;
  final int downTracks;
  final int totalBytesForwarded;
  final int totalPacketsForwarded;

  const SfuStatsSnapshot({
    required this.sessions,
    required this.peers,
    required this.routers,
    required this.downTracks,
    required this.totalBytesForwarded,
    required this.totalPacketsForwarded,
  });

  Map<String, Object?> toJson() => {
        'sessions': sessions,
        'peers': peers,
        'routers': routers,
        'downTracks': downTracks,
        'totalBytesForwarded': totalBytesForwarded,
        'totalPacketsForwarded': totalPacketsForwarded,
      };
}

SfuStatsSnapshot snapshotSfu(Sfu sfu) {
  var peers = 0;
  var routers = 0;
  var downTracks = 0;
  var bytes = 0;
  var packets = 0;
  for (final s in sfu.sessions) {
    peers += s.peerCount;
    for (final r in s.routers) {
      routers++;
      for (final receiver in r.receivers) {
        for (final dt in receiver.downTracks) {
          downTracks++;
          bytes += dt.bytesForwarded;
          packets += dt.packetsForwarded;
        }
      }
    }
  }
  return SfuStatsSnapshot(
    sessions: sfu.sessions.length,
    peers: peers,
    routers: routers,
    downTracks: downTracks,
    totalBytesForwarded: bytes,
    totalPacketsForwarded: packets,
  );
}
