// Phase 10 — load-test harness ("test drive").
//
// Drives the RTP forwarding hot path *without* a live PeerConnection.
// Each synthetic publisher generates RTP packets at a configured rate;
// every packet is fanned out to S synthetic subscribers, each running
// the same [SimulcastRewriter] + [JitterBuffer] + [BytePool] pipeline
// the production [DownTrack] uses. The driver collects:
//
//   - throughput (packets/sec, bytes/sec) per publisher and aggregate
//   - drops (rewriter rejections + sink overflows)
//   - end-to-end fan-out latency histogram (publisher write → sink callback)
//   - allocation stats from [BytePool]
//
// This isolates the SFU's serialised in-isolate fan-out cost — the
// dominant per-room scaling bottleneck — from the SRTP/UDP path that
// pure_dart_webrtc owns.
//
// The harness is intentionally allocation-light: the publisher reuses
// a single template buffer per stream and writes the per-packet
// sequence + timestamp + send-clock in place.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'buffer/buffer.dart';
import 'byte_pool.dart';
import 'simulcast_rewriter.dart';

/// Knobs for one [LoadTestHarness] run.
class LoadTestConfig {
  /// Number of independent rooms.
  final int rooms;

  /// Publishers per room. Each owns one synthetic stream.
  final int publishersPerRoom;

  /// Subscribers per publisher (= per-publisher fan-out factor).
  /// Total fan-out edges per room = publishersPerRoom * subscribersPerPublisher.
  final int subscribersPerPublisher;

  /// Packets per second per publisher. 30 fps video ≈ 30; 50 pps audio
  /// at 20 ms; for video codecs that send multiple packets per frame
  /// scale up accordingly.
  final int packetsPerSecondPerPublisher;

  /// Payload bytes per packet (excluding the 12-byte RTP header).
  final int payloadBytes;

  /// How long to run the steady-state phase.
  final Duration duration;

  /// Optional warm-up before measurement starts.
  final Duration warmup;

  /// Rewriter jitter buffer capacity (matches DownTrack default).
  final int jitterCapacity;

  /// True to use the per-isolate [BytePool] (the production path).
  /// Set false to measure the no-pool baseline.
  final bool usePool;

  const LoadTestConfig({
    this.rooms = 1,
    this.publishersPerRoom = 4,
    this.subscribersPerPublisher = 3,
    this.packetsPerSecondPerPublisher = 30,
    this.payloadBytes = 1100,
    this.duration = const Duration(seconds: 5),
    this.warmup = const Duration(milliseconds: 500),
    this.jitterCapacity = 512,
    this.usePool = true,
  });

  /// Total fan-out edges driven by this config.
  int get fanoutEdges => rooms * publishersPerRoom * subscribersPerPublisher;

  /// Target aggregate packets-per-second (publisher generation).
  int get targetGenPps =>
      rooms * publishersPerRoom * packetsPerSecondPerPublisher;

  /// Target aggregate fan-out packets-per-second.
  int get targetFanoutPps => targetGenPps * subscribersPerPublisher;
}

/// Fixed-bucket latency histogram in microseconds. Bucket boundaries
/// chosen for the SFU hot path (sub-ms typical, multi-ms during GC).
class LatencyHistogram {
  static const _bucketBoundsMicros = <int>[
    50,
    100,
    200,
    500,
    1000,
    2000,
    5000,
    10000,
    20000,
    50000,
    100000,
  ];

  final List<int> _counts = List<int>.filled(_bucketBoundsMicros.length + 1, 0);
  int _samples = 0;
  int _sumMicros = 0;
  int _maxMicros = 0;

  void record(int micros) {
    _samples++;
    _sumMicros += micros;
    if (micros > _maxMicros) _maxMicros = micros;
    var i = 0;
    while (i < _bucketBoundsMicros.length && micros > _bucketBoundsMicros[i]) {
      i++;
    }
    _counts[i]++;
  }

  int get samples => _samples;
  int get maxMicros => _maxMicros;
  double get meanMicros => _samples == 0 ? 0 : _sumMicros / _samples;

  /// Return the smallest bucket boundary whose cumulative count covers
  /// [percentile] (0..1). Returns the last boundary as the worst case.
  int percentileMicros(double p) {
    if (_samples == 0) return 0;
    final target = (p * _samples).ceil();
    var cum = 0;
    for (var i = 0; i < _bucketBoundsMicros.length; i++) {
      cum += _counts[i];
      if (cum >= target) return _bucketBoundsMicros[i];
    }
    return _maxMicros;
  }

  Map<String, Object?> toJson() => {
        'samples': _samples,
        'mean_us': meanMicros.round(),
        'max_us': _maxMicros,
        'p50_us': percentileMicros(0.50),
        'p95_us': percentileMicros(0.95),
        'p99_us': percentileMicros(0.99),
        'buckets_us': _bucketBoundsMicros,
        'counts': List<int>.from(_counts),
      };
}

class LoadTestReport {
  final LoadTestConfig config;
  final Duration elapsed;
  final int generatedPackets;
  final int forwardedPackets;
  final int forwardedBytes;
  final int droppedPackets;
  final int poolHits;
  final int poolMisses;
  final int poolReleases;
  final int poolOversizedDrops;
  final int poolParked;
  final LatencyHistogram fanoutLatency;

  const LoadTestReport({
    required this.config,
    required this.elapsed,
    required this.generatedPackets,
    required this.forwardedPackets,
    required this.forwardedBytes,
    required this.droppedPackets,
    required this.poolHits,
    required this.poolMisses,
    required this.poolReleases,
    required this.poolOversizedDrops,
    required this.poolParked,
    required this.fanoutLatency,
  });

  /// Difference between target generation rate and what we actually
  /// pushed. Positive = we fell behind schedule (publisher loop
  /// couldn't keep up).
  int get genPpsDeficit =>
      config.targetGenPps -
      (generatedPackets * 1000 ~/ math.max(1, elapsed.inMilliseconds));

  double get poolHitRate =>
      poolHits + poolMisses == 0 ? 0 : poolHits / (poolHits + poolMisses);

  double get fanoutCompleteness =>
      generatedPackets * config.subscribersPerPublisher == 0
          ? 0
          : forwardedPackets /
              (generatedPackets * config.subscribersPerPublisher);

  Map<String, Object?> toJson() => {
        'config': {
          'rooms': config.rooms,
          'publishersPerRoom': config.publishersPerRoom,
          'subscribersPerPublisher': config.subscribersPerPublisher,
          'packetsPerSecondPerPublisher': config.packetsPerSecondPerPublisher,
          'payloadBytes': config.payloadBytes,
          'durationMs': config.duration.inMilliseconds,
          'usePool': config.usePool,
          'targetGenPps': config.targetGenPps,
          'targetFanoutPps': config.targetFanoutPps,
          'fanoutEdges': config.fanoutEdges,
        },
        'elapsedMs': elapsed.inMilliseconds,
        'generated': generatedPackets,
        'forwarded': forwardedPackets,
        'forwardedBytes': forwardedBytes,
        'dropped': droppedPackets,
        'fanoutCompleteness': fanoutCompleteness,
        'genPpsDeficit': genPpsDeficit,
        'pool': {
          'hits': poolHits,
          'misses': poolMisses,
          'releases': poolReleases,
          'oversized': poolOversizedDrops,
          'parked': poolParked,
          'hitRate': poolHitRate,
        },
        'fanoutLatency': fanoutLatency.toJson(),
      };

  String renderHuman() {
    final pps = elapsed.inMilliseconds == 0
        ? 0
        : (forwardedPackets * 1000 / elapsed.inMilliseconds).round();
    final mbps = elapsed.inMilliseconds == 0
        ? '0.0'
        : (forwardedBytes * 8 * 1000 / elapsed.inMilliseconds / 1e6)
            .toStringAsFixed(1);
    final poolHint = (config.usePool && poolReleases == 0)
        ? '  [jitter buffer not yet wrapped — '
            'increase --duration or --pps, or lower --jitter]'
        : '';
    final lines = <String>[
      '== load test report ==',
      'config:        rooms=${config.rooms} pubs=${config.publishersPerRoom}'
          ' subs/pub=${config.subscribersPerPublisher}'
          ' pps/pub=${config.packetsPerSecondPerPublisher}',
      'target:        ${config.targetGenPps} gen-pps,'
          ' ${config.targetFanoutPps} fan-out pps,'
          ' ${config.fanoutEdges} edges',
      'duration:      ${elapsed.inMilliseconds} ms (warmup excluded)',
      'generated:     $generatedPackets pkts'
          ' (deficit $genPpsDeficit pps vs target)',
      'forwarded:     $forwardedPackets pkts ($pps pps, $mbps Mbps)',
      'fan-out cov:   ${(fanoutCompleteness * 100).toStringAsFixed(2)}%'
          ' (1.00 = no drops)',
      'dropped:       $droppedPackets pkts',
      'pool:          hit-rate ${(poolHitRate * 100).toStringAsFixed(1)}%'
          ' (${poolHits}h/${poolMisses}m/${poolReleases}r,'
          ' parked $poolParked)$poolHint',
      'latency:       p50=${fanoutLatency.percentileMicros(0.5)}us'
          ' p95=${fanoutLatency.percentileMicros(0.95)}us'
          ' p99=${fanoutLatency.percentileMicros(0.99)}us'
          ' max=${fanoutLatency.maxMicros}us'
          ' mean=${fanoutLatency.meanMicros.round()}us',
    ];
    return lines.join('\n');
  }
}

/// Synthetic publisher → fan-out edges driver. Use [run] for a one-shot
/// measurement.
class LoadTestHarness {
  final LoadTestConfig config;
  final BytePool pool;

  // Aggregate counters.
  int _generated = 0;
  int _forwarded = 0;
  int _forwardedBytes = 0;
  int _dropped = 0;
  final LatencyHistogram _latency = LatencyHistogram();

  // One template buffer per publisher (header + payload). Publisher
  // writes per-packet seq/ts/clock in place; rewriter copies into a
  // pooled buffer for each fan-out edge.
  late final List<_Publisher> _publishers;

  LoadTestHarness(this.config, {BytePool? pool})
      : pool = pool ??
            (config.usePool ? BytePool.instance : BytePool(perBucketCap: 0)) {
    _publishers = _buildPublishers();
  }

  List<_Publisher> _buildPublishers() {
    final out = <_Publisher>[];
    var ssrc = 0xCAFE0000;
    for (var room = 0; room < config.rooms; room++) {
      for (var p = 0; p < config.publishersPerRoom; p++) {
        final publisherSsrc = ssrc++;
        final fanouts = <_Fanout>[];
        for (var s = 0; s < config.subscribersPerPublisher; s++) {
          final rewrittenSsrc = ssrc++;
          final rewriter = SimulcastRewriter(
            rewrittenPrimarySsrc: rewrittenSsrc,
            rewrittenRtxSsrc: null,
            currentLayer: '',
            pool: pool,
          );
          final jitter = JitterBuffer(
            capacity: config.jitterCapacity,
            onEvict: (buf) => pool.release(buf),
          );
          fanouts.add(_Fanout(
            rewriter: rewriter,
            jitter: jitter,
            onForward: _onForward,
            onDrop: _onDrop,
          ));
        }
        out.add(_Publisher(
          ssrc: publisherSsrc,
          payloadBytes: config.payloadBytes,
          packetsPerSecond: config.packetsPerSecondPerPublisher,
          fanouts: fanouts,
          onGen: _onGen,
        ));
      }
    }
    return out;
  }

  void _onGen() => _generated++;
  void _onDrop() => _dropped++;

  void _onForward(Uint8List rewritten, int micros) {
    _forwarded++;
    _forwardedBytes += rewritten.length;
    _latency.record(micros);
  }

  /// Run warm-up + measured phase. Returns the report for the measured
  /// window only.
  Future<LoadTestReport> run() async {
    final allTimers = <Timer>[];
    void scheduleAll(bool measured) {
      for (final p in _publishers) {
        allTimers.add(p.start(measured));
      }
    }

    // warm-up
    if (config.warmup > Duration.zero) {
      scheduleAll(false);
      await Future.delayed(config.warmup);
      for (final t in allTimers) {
        t.cancel();
      }
      allTimers.clear();
    }

    // reset counters before measured phase
    _generated = 0;
    _forwarded = 0;
    _forwardedBytes = 0;
    _dropped = 0;
    final start = DateTime.now();
    scheduleAll(true);
    await Future.delayed(config.duration);
    for (final t in allTimers) {
      t.cancel();
    }
    final elapsed = DateTime.now().difference(start);

    return LoadTestReport(
      config: config,
      elapsed: elapsed,
      generatedPackets: _generated,
      forwardedPackets: _forwarded,
      forwardedBytes: _forwardedBytes,
      droppedPackets: _dropped,
      poolHits: pool.hits,
      poolMisses: pool.misses,
      poolReleases: pool.releases,
      poolOversizedDrops: pool.oversizedDrops,
      poolParked: pool.parkedCount,
      fanoutLatency: _latency,
    );
  }
}

/// Synthetic publisher. Each tick emits one RTP packet to every
/// fan-out and bumps seq/ts.
class _Publisher {
  final int ssrc;
  final int payloadBytes;
  final int packetsPerSecond;
  final List<_Fanout> fanouts;
  final void Function() onGen;

  int _seq = 0;
  int _ts = 0;
  late final Uint8List _template;
  bool _measured = false;

  _Publisher({
    required this.ssrc,
    required this.payloadBytes,
    required this.packetsPerSecond,
    required this.fanouts,
    required this.onGen,
  }) {
    _template = Uint8List(12 + payloadBytes);
    // V=2 P=0 X=0 CC=0
    _template[0] = 0x80;
    // Marker=0 PT=96
    _template[1] = 0x60;
    _template[8] = (ssrc >> 24) & 0xff;
    _template[9] = (ssrc >> 16) & 0xff;
    _template[10] = (ssrc >> 8) & 0xff;
    _template[11] = ssrc & 0xff;
    // Fill the payload with a stable pattern so any compression is
    // realistic (none here — UDP is on the wire — but at least the
    // bytes aren't all zero).
    for (var i = 12; i < _template.length; i++) {
      _template[i] = (i * 31) & 0xff;
    }
  }

  Timer start(bool measured) {
    _measured = measured;
    final intervalMicros = (1000000 / packetsPerSecond).round();
    return Timer.periodic(
      Duration(microseconds: intervalMicros),
      (_) => _tick(),
    );
  }

  void _tick() {
    _seq = (_seq + 1) & 0xffff;
    _ts = (_ts + 90000 ~/ packetsPerSecond) & 0xffffffff;
    _template[2] = (_seq >> 8) & 0xff;
    _template[3] = _seq & 0xff;
    _template[4] = (_ts >> 24) & 0xff;
    _template[5] = (_ts >> 16) & 0xff;
    _template[6] = (_ts >> 8) & 0xff;
    _template[7] = _ts & 0xff;
    final genMicros = DateTime.now().microsecondsSinceEpoch;
    if (_measured) onGen();
    for (final f in fanouts) {
      f.deliver(_template, genMicros, measured: _measured);
    }
  }
}

class _Fanout {
  final SimulcastRewriter rewriter;
  final JitterBuffer jitter;
  final void Function(Uint8List rewritten, int latencyMicros) onForward;
  final void Function() onDrop;

  _Fanout({
    required this.rewriter,
    required this.jitter,
    required this.onForward,
    required this.onDrop,
  });

  void deliver(Uint8List rtp, int genMicros, {required bool measured}) {
    final r = rewriter.rewrite(rid: '', isRtx: false, rtp: rtp);
    if (r.dropped) {
      if (measured) onDrop();
      return;
    }
    final out = r.out!;
    if (r.outSeq != null) {
      jitter.record(r.outSeq!, out);
    }
    if (measured) {
      final now = DateTime.now().microsecondsSinceEpoch;
      onForward(out, now - genMicros);
    }
  }
}
