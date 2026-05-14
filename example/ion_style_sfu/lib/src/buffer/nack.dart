// Phase 2 — NACK responder.
//
// Subscribers' RTPFB FMT=1 feedback enters via [Subscriber.handleFeedback];
// for each missing seq the responder either:
//   * Replays the cached packet from the [JitterBuffer], OR
//   * Asks the upstream publisher to retransmit (when not cached).

import 'dart:typed_data';

import 'buffer.dart';

class NackResponder {
  final JitterBuffer buffer;

  /// Counters surfaced via stats.
  int retransmits = 0;
  int upstreamRequested = 0;

  NackResponder({required this.buffer});

  /// Try to satisfy [missing] from the jitter buffer. Returns the
  /// retransmittable packets and the still-missing sequence numbers
  /// the caller must escalate upstream.
  ({List<Uint8List> hits, List<int> stillMissing}) lookup(List<int> missing) {
    final hits = <Uint8List>[];
    final still = <int>[];
    for (final seq in missing) {
      final p = buffer.get(seq);
      if (p != null) {
        hits.add(p);
        retransmits++;
      } else {
        still.add(seq);
      }
    }
    if (still.isNotEmpty) upstreamRequested += still.length;
    return (hits: hits, stillMissing: still);
  }
}
