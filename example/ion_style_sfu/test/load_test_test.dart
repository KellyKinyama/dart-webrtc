import 'package:pure_dart_webrtc_ion_style_sfu/src/load_test.dart';
import 'package:test/test.dart';

void main() {
  test('load harness produces a coherent report', () async {
    final cfg = LoadTestConfig(
      rooms: 1,
      publishersPerRoom: 2,
      subscribersPerPublisher: 2,
      packetsPerSecondPerPublisher: 100,
      payloadBytes: 200,
      duration: const Duration(milliseconds: 500),
      warmup: const Duration(milliseconds: 100),
    );
    final report = await LoadTestHarness(cfg).run();

    expect(report.elapsed.inMilliseconds, greaterThan(400));
    expect(report.generatedPackets, greaterThan(50));
    // Fan-out should match generated × subs/pub almost exactly.
    expect(
      report.forwardedPackets,
      closeTo(
        report.generatedPackets * cfg.subscribersPerPublisher,
        cfg.subscribersPerPublisher * 5,
      ),
    );
    expect(report.fanoutCompleteness, greaterThan(0.95));
    // The rewriter never drops valid input in this synthetic test.
    expect(report.droppedPackets, 0);
    // Some pool activity must have happened.
    expect(report.poolHits + report.poolMisses, greaterThan(0));
    expect(report.fanoutLatency.samples, equals(report.forwardedPackets));
  });

  test('disabling the pool reports zero hit-rate', () async {
    final cfg = LoadTestConfig(
      rooms: 1,
      publishersPerRoom: 1,
      subscribersPerPublisher: 1,
      packetsPerSecondPerPublisher: 50,
      duration: const Duration(milliseconds: 250),
      warmup: const Duration(milliseconds: 50),
      usePool: false,
    );
    final report = await LoadTestHarness(cfg).run();
    expect(report.poolHits, 0);
    expect(report.poolHitRate, 0);
    expect(report.poolMisses, greaterThan(0));
  });
}
