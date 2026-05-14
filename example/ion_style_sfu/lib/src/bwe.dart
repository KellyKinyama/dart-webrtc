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
import 'twcc/twcc_stamper.dart';

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

  /// Phase 7b — delay-gradient threshold (dimensionless). When the
  /// fitted slope of (arrival_delay vs send_time) exceeds this value
  /// we declare congestion. Default ~ 1ms of growth per 100ms send
  /// window (= 0.01).
  final double overuseSlope;

  /// Phase 7b — multiplicative back-off applied on overuse.
  final double decreaseFactor;

  /// Phase 7b — multiplicative bump applied on underuse (slope below
  /// `-overuseSlope`). 1.0 = stay put.
  final double increaseFactor;

  /// Most recent smoothed estimate, in bits-per-second. Zero until the
  /// first feedback arrives.
  int currentBps = 0;

  /// Wall-clock of the last update. Useful for staleness checks.
  DateTime? lastUpdate;

  /// Phase 7b — last delay-based controller decision. Useful for stats
  /// and for assertions in tests.
  BweDecision lastDecision = BweDecision.hold;

  /// Phase 7b — last measured throughput in bps from TWCC arrivals,
  /// or 0 when no usable samples were available.
  int lastMeasuredBps = 0;

  /// Phase 7b — last measured delay slope (dimensionless), or 0 when
  /// no usable samples were available.
  double lastSlope = 0.0;

  BandwidthEstimator({
    this.smoothing = 0.3,
    this.overuseSlope = 0.01,
    this.decreaseFactor = 0.85,
    this.increaseFactor = 1.08,
  }) : assert(smoothing > 0 && smoothing <= 1, 'smoothing in (0,1]');

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

  /// Phase 7b — delay-based estimator. Uses [stamper]'s send-time
  /// history to map each received TWCC seq back to its egress wallclock
  /// and runs a simple Google-Congestion-Control-style decision:
  ///
  ///  - slope of (arrival_delay − send_delay) > [overuseSlope] →
  ///    *decrease* by [decreaseFactor]
  ///  - slope < -[overuseSlope] → *increase* by [increaseFactor]
  ///  - otherwise → *hold*, but bias toward the measured throughput
  ///    (EMA toward `bytes*8 / arrival_span`)
  ///
  /// Returns the new estimate. Updates [lastDecision], [lastSlope],
  /// and [lastMeasuredBps].
  int onTwccDelay(TwccFeedback fb, TwccStamper stamper) {
    final samples = _collectSamples(fb, stamper);
    if (samples.length < 2) {
      lastDecision = BweDecision.hold;
      lastSlope = 0.0;
      lastMeasuredBps = 0;
      return currentBps;
    }
    // Slope of (delay vs sendTime) — delay = arrival - send.
    final t0 = samples.first.sendUs;
    double sxy = 0, sx = 0, sy = 0, sxx = 0;
    final n = samples.length;
    for (final s in samples) {
      final x = (s.sendUs - t0).toDouble();
      final y = (s.arrivalUs - s.sendUs).toDouble();
      sxy += x * y;
      sx += x;
      sy += y;
      sxx += x * x;
    }
    final denom = (n * sxx) - (sx * sx);
    final slope = denom == 0 ? 0.0 : ((n * sxy) - (sx * sy)) / denom;
    lastSlope = slope;

    // Measured throughput.
    final arrivalSpan = samples.last.arrivalUs - samples.first.arrivalUs;
    var totalBytes = 0;
    for (final s in samples) {
      totalBytes += s.sizeBytes;
    }
    final measured = arrivalSpan > 0
        ? ((totalBytes * 8) * 1000000 / arrivalSpan).round()
        : 0;
    lastMeasuredBps = measured;

    int target;
    if (slope > overuseSlope) {
      lastDecision = BweDecision.decrease;
      final base = currentBps == 0 ? measured : currentBps;
      target = (base * decreaseFactor).round();
    } else if (slope < -overuseSlope) {
      lastDecision = BweDecision.increase;
      final base = currentBps == 0 ? measured : currentBps;
      target = (base * increaseFactor).round();
    } else {
      lastDecision = BweDecision.hold;
      target = measured > 0 ? measured : currentBps;
    }

    final next = currentBps == 0
        ? target
        : (currentBps + smoothing * (target - currentBps)).round();
    currentBps = next < 0 ? 0 : next;
    lastUpdate = DateTime.now();
    return currentBps;
  }

  /// Reconstruct absolute arrival timestamps from [fb] and look each
  /// received sequence number's send-time + byte size up in [stamper].
  /// Drops samples for which the stamper no longer has history.
  List<_TwccSample> _collectSamples(TwccFeedback fb, TwccStamper stamper) {
    final out = <_TwccSample>[];
    // Reference time is in 64ms units → microseconds.
    var arrivalUs = fb.referenceTime * 64 * 1000;
    for (var i = 0; i < fb.statuses.length; i++) {
      final d = fb.deltaUs[i];
      if (d != null) arrivalUs += d;
      if (fb.statuses[i] == 0) continue; // not received
      final seq = (fb.baseSeq + i) & 0xffff;
      final sendUs = stamper.sendTimeMicrosFor(seq);
      final size = stamper.sizeBytesFor(seq);
      if (sendUs == null || size == null) continue;
      out.add(_TwccSample(
        seq: seq,
        sendUs: sendUs,
        arrivalUs: arrivalUs,
        sizeBytes: size,
      ));
    }
    return out;
  }
}

/// Phase 7b — categorical output of the delay-based BWE controller.
enum BweDecision { hold, increase, decrease }

class _TwccSample {
  final int seq;
  final int sendUs;
  final int arrivalUs;
  final int sizeBytes;
  const _TwccSample({
    required this.seq,
    required this.sendUs,
    required this.arrivalUs,
    required this.sizeBytes,
  });
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
