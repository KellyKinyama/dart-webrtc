// load_test.dart pure-data coverage: histogram getters/percentiles,
// LoadTestConfig derived getters, LoadTestReport.toJson + renderHuman,
// _onDrop seam (via JitterBuffer overflow path).

import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/src/load_test.dart';
import 'package:test/test.dart';

void main() {
  group('LatencyHistogram', () {
    test('empty histogram returns zeros', () {
      final h = LatencyHistogram();
      expect(h.samples, 0);
      expect(h.maxMicros, 0);
      expect(h.meanMicros, 0);
      expect(h.percentileMicros(0.5), 0);
      expect(h.percentileMicros(0.99), 0);
      final j = h.toJson();
      expect(j['samples'], 0);
      expect(j['max_us'], 0);
    });

    test('percentiles cross every bucket boundary', () {
      final h = LatencyHistogram();
      // One sample in each bucket including overflow (>100000us).
      const buckets = [
        25,
        75,
        150,
        300,
        800,
        1500,
        3000,
        7000,
        15000,
        30000,
        80000,
        200000
      ];
      for (final v in buckets) {
        h.record(v);
      }
      expect(h.samples, buckets.length);
      expect(h.maxMicros, 200000);
      expect(h.meanMicros, greaterThan(0));
      // p50 should land in middle bucket.
      expect(h.percentileMicros(0.50), greaterThan(0));
      expect(h.percentileMicros(0.95), greaterThanOrEqualTo(50000));
      expect(h.percentileMicros(0.99), greaterThanOrEqualTo(50000));
      final j = h.toJson();
      expect(j['samples'], buckets.length);
      expect((j['counts'] as List).length, greaterThan(0));
      expect(j['buckets_us'], isA<List>());
    });
  });

  group('LoadTestConfig derived getters', () {
    test('fanoutEdges / targetGenPps / targetFanoutPps math is right', () {
      const c = LoadTestConfig(
        rooms: 3,
        publishersPerRoom: 4,
        subscribersPerPublisher: 5,
        packetsPerSecondPerPublisher: 30,
      );
      expect(c.fanoutEdges, 3 * 4 * 5);
      expect(c.targetGenPps, 3 * 4 * 30);
      expect(c.targetFanoutPps, 3 * 4 * 30 * 5);
    });
  });

  group('LoadTestReport JSON + renderHuman', () {
    test('toJson + renderHuman cover every formatted field', () async {
      // Tiny but non-zero run so all counters are populated.
      final h = LoadTestHarness(const LoadTestConfig(
        rooms: 1,
        publishersPerRoom: 1,
        subscribersPerPublisher: 1,
        packetsPerSecondPerPublisher: 100,
        payloadBytes: 64,
        warmup: Duration(milliseconds: 30),
        duration: Duration(milliseconds: 120),
        jitterCapacity: 16,
      ));
      final report = await h.run();

      // toJson
      final j = report.toJson();
      expect(j['config'], isA<Map>());
      final cfg = j['config']! as Map;
      expect(cfg['rooms'], 1);
      expect(cfg['fanoutEdges'], 1);
      expect(cfg['targetGenPps'], 100);
      expect(cfg['targetFanoutPps'], 100);
      expect(j['elapsedMs'], greaterThan(0));
      expect(j['generated'], greaterThanOrEqualTo(0));
      expect(j['forwarded'], greaterThanOrEqualTo(0));
      expect(j['fanoutCompleteness'], isA<num>());
      expect(j['genPpsDeficit'], isA<num>());
      expect((j['pool'] as Map)['hitRate'], isA<num>());
      expect(j['fanoutLatency'], isA<Map>());

      // renderHuman — exercise every line of the multi-line report.
      final text = report.renderHuman();
      expect(text, contains('== load test report =='));
      expect(text, contains('config:'));
      expect(text, contains('target:'));
      expect(text, contains('duration:'));
      expect(text, contains('generated:'));
      expect(text, contains('forwarded:'));
      expect(text, contains('fan-out cov:'));
      expect(text, contains('dropped:'));
      expect(text, contains('pool:'));
      expect(text, contains('latency:'));
    });

    test('zero-elapsed report renders without div-by-zero', () {
      // Build a hand-rolled report with elapsed=0 to force the ternary
      // branches in renderHuman.
      final hist = LatencyHistogram();
      const cfg = LoadTestConfig(
        rooms: 1,
        publishersPerRoom: 1,
        subscribersPerPublisher: 1,
        warmup: Duration.zero,
        duration: Duration.zero,
      );
      final report = LoadTestReport(
        config: cfg,
        elapsed: Duration.zero,
        generatedPackets: 0,
        forwardedPackets: 0,
        forwardedBytes: 0,
        droppedPackets: 0,
        poolHits: 0,
        poolMisses: 0,
        poolReleases: 0,
        poolOversizedDrops: 0,
        poolParked: 0,
        fanoutLatency: hist,
      );
      final text = report.renderHuman();
      expect(text, contains('== load test report =='));
      // Pool hint warns about pool=on but no releases.
      expect(text, contains('pool:'));
      // Bytes Uint8List import keeps the linker happy.
      expect(Uint8List(0).lengthInBytes, 0);
    });
  });
}
