// Phase B7 — leaky-bucket pacer.
//
// Smooths bursty outbound RTP into a steady stream so the remote
// bandwidth estimator sees a predictable arrival pattern. This is a
// Dart port of livekit-server's `pkg/sfu/pacer/leaky_bucket.go`
// algorithm (Apache-2.0), simplified for our packet model: we accept
// already-stamped Uint8List buffers (TWCC seq, RTX OSN, etc. are
// applied by DownTrack before enqueue) and call back into a sink
// closure on dequeue.
//
// Algorithm per drain interval:
//   intervalBytes   = interval_seconds * targetBitrateBps / 8
//   maxOvershoot    = intervalBytes * maxOvershootFactor   (default 2x)
//   toSendBytes     = intervalBytes - overage              (carry-in)
//   if toSendBytes < 0 → carry the overage forward, skip this tick
//   else clamp to maxOvershoot, then drain queue:
//     - pop, sink(packet), toSendBytes -= packet.length
//     - stop when toSendBytes < 0  (record positive overage)
//     - or queue empty           (record negative "shortage" so the
//                                  next tick gets bonus headroom)
//
// Standalone module — DownTrack does NOT yet route through this
// pacer in production. Wiring is a separate change so we can ship +
// test the algorithm on its own first.

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

/// Default drain cadence. 5 ms matches livekit's leaky-bucket default
/// and Chrome's WebRTC pacer interval — small enough that visible
/// jitter is sub-frame on 30 fps video, large enough that the timer
/// overhead stays low.
const Duration kDefaultPacerInterval = Duration(milliseconds: 5);

/// Cap on per-interval send budget as a multiple of the steady-state
/// budget. Allows brief catch-up after a stall without unbounded
/// bursting that would defeat pacing.
const double kDefaultMaxOvershootFactor = 2.0;

/// Hard cap on queued packets. When exceeded the OLDEST packet is
/// dropped and [packetsDroppedOverflow] is incremented. Defaults to
/// 1024 — at 8 Mbps and 1200-byte packets that's ~1.2 seconds of
/// buffered media, plenty for any sane pacer interval.
const int kDefaultMaxQueueDepth = 1024;

/// One queued outbound packet.
class _PacedPacket {
  _PacedPacket(this.rtp, this.isRtx);
  final Uint8List rtp;
  final bool isRtx;
}

/// Leaky-bucket pacer. Owns its own [Timer.periodic] — call [close]
/// when you're done. Not isolate-safe; intended for use from a single
/// event loop.
class LeakyBucketPacer {
  /// Sink invoked on every drained packet. Called synchronously from
  /// the drain timer. Throwing here is caught by the timer; failing
  /// sinks should track their own retry / drop policy.
  final void Function(Uint8List rtp, {required bool isRtx}) sink;

  /// Steady-state target send rate, bits per second. Set to 0 to
  /// pause draining (queue keeps accepting until [maxQueueDepth]).
  int _targetBitrateBps;
  int get targetBitrateBps => _targetBitrateBps;

  /// Drain cadence.
  Duration _interval;
  Duration get interval => _interval;

  /// See [kDefaultMaxOvershootFactor].
  final double maxOvershootFactor;

  /// See [kDefaultMaxQueueDepth].
  final int maxQueueDepth;

  final Queue<_PacedPacket> _queue = Queue<_PacedPacket>();
  Timer? _timer;
  bool _closed = false;

  /// Carry-over (in bytes) between intervals. Positive = we overshot
  /// last tick and owe budget back this tick; negative = we
  /// undershot (queue was empty) and may overshoot next tick.
  int _overage = 0;

  // ---- counters ----------------------------------------------------

  /// Total packets that came in via [enqueue].
  int packetsEnqueued = 0;

  /// Total packets that the sink received.
  int packetsSent = 0;

  /// Total bytes that the sink received.
  int bytesSent = 0;

  /// Packets dropped because the queue was at [maxQueueDepth] when
  /// [enqueue] was called. The OLDEST queued packet is dropped (FIFO
  /// preferred over fresh frames).
  int packetsDroppedOverflow = 0;

  /// Drain ticks where the queue was empty.
  int idleTicks = 0;

  /// Drain ticks where the budget was exhausted before the queue was.
  int saturatedTicks = 0;

  LeakyBucketPacer({
    required this.sink,
    int targetBitrateBps = 1000000,
    Duration interval = kDefaultPacerInterval,
    this.maxOvershootFactor = kDefaultMaxOvershootFactor,
    this.maxQueueDepth = kDefaultMaxQueueDepth,
    bool autoStart = true,
  })  : assert(targetBitrateBps >= 0),
        assert(maxOvershootFactor >= 1.0),
        assert(maxQueueDepth > 0),
        _targetBitrateBps = targetBitrateBps,
        _interval = interval {
    if (autoStart) start();
  }

  /// Number of packets currently waiting in the queue.
  int get queueDepth => _queue.length;

  /// True when the drain timer is running.
  bool get isRunning => _timer != null;

  bool get isClosed => _closed;

  /// Carry-over budget in bytes. Negative means the pacer has unused
  /// headroom rolled into the next tick. Exposed for tests / stats.
  int get overageBytes => _overage;

  /// Start (or restart) the periodic drain timer. No-op if already
  /// running or [close]d.
  void start() {
    if (_closed) return;
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _drain());
  }

  /// Stop the drain timer without discarding the queue. Call [start]
  /// to resume, or [close] to tear down.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Update the target send rate. Takes effect on the next drain tick.
  void setBitrate(int bps) {
    assert(bps >= 0);
    _targetBitrateBps = bps;
  }

  /// Update the drain cadence. Restarts the timer if it was running.
  void setInterval(Duration interval) {
    assert(interval > Duration.zero);
    _interval = interval;
    if (_timer != null) start();
  }

  /// Add a packet to the queue. Returns true on success, false when
  /// the pacer is closed. When the queue is at [maxQueueDepth] the
  /// OLDEST packet is dropped first to make room (FIFO preferred —
  /// dropping fresh frames during a stall is worse for video than
  /// dropping stale ones).
  bool enqueue(Uint8List rtp, {bool isRtx = false}) {
    if (_closed) return false;
    if (_queue.length >= maxQueueDepth) {
      _queue.removeFirst();
      packetsDroppedOverflow++;
    }
    _queue.add(_PacedPacket(rtp, isRtx));
    packetsEnqueued++;
    return true;
  }

  /// Manually drain one tick's worth of budget. Exposed for tests so
  /// they can drive the algorithm without waiting on real wallclock.
  /// Production code should rely on the periodic timer started by
  /// [start].
  void drainForTest() => _drain();

  void _drain() {
    if (_closed) return;
    final intervalSeconds = _interval.inMicroseconds / 1e6;
    final intervalBytes =
        (intervalSeconds * _targetBitrateBps / 8.0).round();
    final maxOvershootBytes = (intervalBytes * maxOvershootFactor).round();

    var toSendBytes = intervalBytes - _overage;
    if (toSendBytes < 0) {
      // Too much overage from the previous tick — wait one full tick
      // before sending anything more.
      _overage = -toSendBytes;
      return;
    }
    if (toSendBytes > maxOvershootBytes) {
      toSendBytes = maxOvershootBytes;
    }

    while (true) {
      if (_queue.isEmpty) {
        // Roll the unused budget into the next tick as a credit.
        _overage = -toSendBytes;
        idleTicks++;
        return;
      }
      final p = _queue.removeFirst();
      try {
        sink(p.rtp, isRtx: p.isRtx);
      } catch (_) {
        // Sink failure is a sink concern; the pacer's job is to
        // deliver in pace, not to retry. Counters reflect a sent
        // packet because the budget was consumed regardless.
      }
      packetsSent++;
      bytesSent += p.rtp.length;
      toSendBytes -= p.rtp.length;
      if (toSendBytes < 0) {
        // Budget exhausted (with normal overshoot accounting).
        _overage = -toSendBytes;
        saturatedTicks++;
        return;
      }
    }
  }

  /// Stop the timer and discard any queued packets. Idempotent.
  void close() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _queue.clear();
  }
}
