// Phase 5 — Bandwidth estimation and simulcast layer selection.
//
// One [BandwidthEstimator] per subscriber. It accepts feedback from
// the subscriber side (REMB and/or TWCC parsed out of inbound RTCP)
// and exposes a smoothed estimate in bits-per-second. A
// [LayerSelector] reads that estimate and picks a target RID for each
// of the subscriber's DownTracks.
//
// This is deliberately conservative: ion-sfu uses Google's GCC for
// TWCC-based delay estimation, but the layer-selection threshold model
// is decoupled from the estimator. For Phase 5 we feed `BandwidthEstimator`
// directly from REMB readings (the simple case) and from a coarse
// receive-rate proxy derived from TWCC arrival-time gaps (a stand-in
// for a full delay-based controller).

import 'dart:async';
import 'dart:math' as math;

import 'rtcp.dart';

/// Bitrate thresholds (bps) above which the next simulcast layer
/// becomes affordable. Tuned for 360p/720p/1080p VP8 simulcast.
class LayerBitrateThresholds {
  /// Minimum bps to keep `q` (lowest). Below this we still send `q`.
  final int qMinBps;

  /// Minimum bps to upgrade `q → h`.
  final int hMinBps;

  /// Minimum bps to upgrade `h → f`.
  final int fMinBps;

  const LayerBitrateThresholds({
    this.qMinBps = 150 * 1000,
    this.hMinBps = 500 * 1000,
    this.fMinBps = 1500 * 1000,
  });

  /// Pick the highest [rid] from [availableRids] whose threshold is
  /// satisfied by [bps]. [availableRids] is ordered low → high
  /// (`['q','h','f']` by convention).
  String pickRid(int bps, List<String> availableRids) {
    String chosen = availableRids.first;
    for (final r in availableRids) {
      final t = switch (r) {
        'q' => qMinBps,
        'h' => hMinBps,
        'f' => fMinBps,
        _ => 0,
      };
      if (bps >= t) chosen = r;
    }
    return chosen;
  }
}

class BandwidthEstimator {
  /// EMA smoothing factor in (0, 1]; higher == more reactive.
  final double smoothing;

  /// Most recent smoothed estimate, in bits-per-second. Zero until the
  /// first feedback arrives.
  int currentBps = 0;

  /// Wall-clock of the last update. Useful for staleness checks.
  DateTime? lastUpdate;

  BandwidthEstimator({this.smoothing = 0.3})
      : assert(smoothing > 0 && smoothing <= 1, 'smoothing in (0,1]');

  /// Set the estimate directly. Mostly for tests.
  void setBps(int bps) {
    currentBps = bps;
    lastUpdate = DateTime.now();
  }

  /// Feed a REMB reading. Updates [currentBps] via EMA.
  void onRemb(RembFeedback r) {
    final next = currentBps == 0
        ? r.bps
        : (currentBps + smoothing * (r.bps - currentBps)).round();
    currentBps = next;
    lastUpdate = DateTime.now();
  }

  /// Feed a TWCC feedback packet. Estimates receive-rate from the
  /// reported arrival deltas. This is *not* a delay-based controller —
  /// it's the simplest stand-in: total payload-byte budget hint from
  /// the timing window.
  ///
  /// [byteBudget] is the number of payload bytes the feedback covers
  /// (caller passes the running sum since the previous TWCC). Returns
  /// the new estimate.
  int onTwcc(TwccFeedback fb, int byteBudget) {
    // Window length in microseconds = sum of non-null deltas.
    var totalUs = 0;
    var received = 0;
    for (final d in fb.deltaUs) {
      if (d == null) continue;
      totalUs += d.abs();
      received++;
    }
    if (totalUs <= 0 || received == 0 || byteBudget <= 0) {
      return currentBps;
    }
    final bps = ((byteBudget * 8) * 1000000 / totalUs).round();
    final next = currentBps == 0
        ? bps
        : (currentBps + smoothing * (bps - currentBps)).round();
    currentBps = next;
    lastUpdate = DateTime.now();
    return currentBps;
  }
}

/// Picks one RID per receiver based on a [BandwidthEstimator]. Calls
/// [onLayerChange] whenever a different layer is preferred.
class LayerSelector {
  final BandwidthEstimator estimator;
  final LayerBitrateThresholds thresholds;

  /// receiverId → list of available RIDs (low → high).
  final Map<String, List<String>> _availableLayers = {};

  /// receiverId → currently-selected RID.
  final Map<String, String> _current = {};

  /// Headroom hint per active downtrack (bps) — the estimator's budget
  /// is divided by this many to allow several video tracks to share
  /// one downlink.
  int activeVideoDownTracks = 1;

  /// Called whenever the selector picks a different RID for a
  /// receiver. [receiverId] is the producer id and [rid] is the new
  /// target.
  void Function(String receiverId, String rid)? onLayerChange;

  LayerSelector({
    required this.estimator,
    this.thresholds = const LayerBitrateThresholds(),
  });

  void register(String receiverId, List<String> availableRids,
      {required String initialRid}) {
    if (availableRids.isEmpty) return;
    _availableLayers[receiverId] = List<String>.from(availableRids);
    _current[receiverId] = initialRid;
  }

  void unregister(String receiverId) {
    _availableLayers.remove(receiverId);
    _current.remove(receiverId);
  }

  String? currentLayer(String receiverId) => _current[receiverId];

  /// Run one selection pass. For every registered receiver the layer is
  /// updated based on the most recent BWE reading.
  void tick() {
    final perTrack = math.max(1, activeVideoDownTracks);
    final budget = estimator.currentBps ~/ perTrack;
    for (final entry in _availableLayers.entries) {
      final rids = entry.value;
      if (rids.length < 2) continue;
      final target = thresholds.pickRid(budget, rids);
      final cur = _current[entry.key];
      if (cur != target) {
        _current[entry.key] = target;
        onLayerChange?.call(entry.key, target);
      }
    }
  }
}

/// Periodically calls [selector].tick(). Cheap wrapper so callers
/// don't have to manage a Timer themselves.
class LayerSelectorTimer {
  final LayerSelector selector;
  final Duration interval;
  Timer? _timer;

  LayerSelectorTimer({
    required this.selector,
    this.interval = const Duration(milliseconds: 1000),
  });

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => selector.tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
