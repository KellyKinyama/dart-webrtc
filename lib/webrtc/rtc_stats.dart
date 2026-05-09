// `RTCStats` skeleton.
//
// Mirrors the browser's `RTCStatsReport` shape (a map keyed by stats id),
// with one entry per inbound/outbound RTP stream. The actual counter
// plumbing reads from the per-peer SRTP context and the bound transport.

/// One stats record. Mirrors W3C's `RTCStats` dictionary loosely.
class RTCStats {
  /// `transport`, `inbound-rtp`, `outbound-rtp`, `peer-connection`, ...
  final String type;

  /// Stable id used as the map key in [RTCStatsReport.stats].
  final String id;

  /// Wall-clock timestamp the values were sampled at.
  final DateTime timestamp;

  /// Free-form values. Keys follow the W3C dictionary names where sensible
  /// (e.g. `bytesSent`, `packetsSent`, `bytesReceived`, `packetsReceived`).
  final Map<String, Object?> values;

  RTCStats({
    required this.type,
    required this.id,
    required this.values,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Browser-style stats report. Iteration order mirrors insertion order.
class RTCStatsReport {
  final Map<String, RTCStats> stats;
  RTCStatsReport(this.stats);

  Iterable<RTCStats> ofType(String type) =>
      stats.values.where((s) => s.type == type);

  RTCStats? operator [](String id) => stats[id];

  int get length => stats.length;
}
