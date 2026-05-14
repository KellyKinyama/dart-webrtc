// Phase 2 — Stable per-subscriber SSRC remapping.
//
// Mirrors the [`SsrcAllocator`] in `example/sfu/lib/basic_sfu.dart`,
// scoped to ion-style's `(subscriberId, originalSsrc)` keying.

import 'dart:math';

class SsrcAllocator {
  final Random _rng;

  /// subscriberId -> originalSsrc -> rewrittenSsrc.
  final Map<String, Map<int, int>> _byReceiver = {};

  /// subscriberId -> rewrittenSsrc -> originalSsrc (reverse map for feedback).
  final Map<String, Map<int, int>> _reverse = {};

  /// subscriberId -> rewrittenSsrc set (collision avoidance).
  final Map<String, Set<int>> _allocated = {};

  SsrcAllocator({Random? rng}) : _rng = rng ?? Random.secure();

  /// Get (or allocate) the rewritten SSRC for [originalSsrc] on
  /// [subscriberId]. Idempotent.
  int rewrite(String subscriberId, int originalSsrc) {
    final perSub = _byReceiver.putIfAbsent(subscriberId, () => {});
    final cached = perSub[originalSsrc];
    if (cached != null) return cached;

    final used = _allocated.putIfAbsent(subscriberId, () => <int>{});
    int candidate;
    do {
      candidate = _rng.nextInt(0xFFFFFFFF);
      if (candidate == 0) continue;
    } while (used.contains(candidate));
    used.add(candidate);
    perSub[originalSsrc] = candidate;
    _reverse.putIfAbsent(subscriberId, () => {})[candidate] = originalSsrc;
    return candidate;
  }

  /// Allocate an RTX SSRC paired with the rewritten primary, ensuring
  /// the primary exists first.
  int rewriteRtx(
      String subscriberId, int originalPrimarySsrc, int originalRtxSsrc) {
    rewrite(subscriberId, originalPrimarySsrc);
    return rewrite(subscriberId, originalRtxSsrc);
  }

  /// Reverse lookup: given the SSRC the [subscriberId] sees, return the
  /// original sender SSRC, or null if no mapping exists.
  int? originalFor(String subscriberId, int rewrittenSsrc) =>
      _reverse[subscriberId]?[rewrittenSsrc];

  /// Forget every mapping for [subscriberId] (called on peer leave).
  void forget(String subscriberId) {
    _byReceiver.remove(subscriberId);
    _reverse.remove(subscriberId);
    _allocated.remove(subscriberId);
  }
}
