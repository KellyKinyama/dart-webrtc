// Phase B-quick — extra BWE coverage:
//   - BandwidthEstimator.onTwcc throughput-only path (cold start +
//     EMA warm path + early-return on empty/zero inputs).
//   - LayerSelectorTimer start/stop wrapper.

import 'dart:async';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

TwccFeedback _twcc(List<int?> deltaUs) => TwccFeedback(
      senderSsrc: 0xAAAA,
      mediaSsrc: 0xBBBB,
      baseSeq: 0,
      packetCount: deltaUs.length,
      referenceTime: 0,
      fbPacketCount: 1,
      statuses: [for (final d in deltaUs) d == null ? 0 : 1],
      deltaUs: deltaUs,
    );

void main() {
  group('BandwidthEstimator.onTwcc throughput-only', () {
    test('cold-start sets currentBps to the raw measurement', () {
      final bwe = BandwidthEstimator(smoothing: 0.5);
      // 1000 bytes over 8000 us = 1000*8 / 0.008 s = 1_000_000 bps.
      final n = bwe.onTwcc(_twcc([2000, 2000, 2000, 2000]), 1000);
      expect(n, 1000000);
      expect(bwe.currentBps, 1000000);
      expect(bwe.lastUpdate, isNotNull);
    });

    test('warm path applies EMA smoothing', () {
      final bwe = BandwidthEstimator(smoothing: 0.5)..setBps(2000000);
      // Same 1_000_000 bps measurement; EMA = 2_000_000 + 0.5*(1M-2M) = 1.5M.
      final n = bwe.onTwcc(_twcc([2000, 2000, 2000, 2000]), 1000);
      expect(n, 1500000);
    });

    test('empty deltas return currentBps unchanged', () {
      final bwe = BandwidthEstimator()..setBps(750000);
      final n = bwe.onTwcc(_twcc(const []), 500);
      expect(n, 750000);
    });

    test('all-null deltas return currentBps unchanged', () {
      final bwe = BandwidthEstimator()..setBps(750000);
      final n = bwe.onTwcc(_twcc(const [null, null, null]), 500);
      expect(n, 750000);
    });

    test('zero byteBudget returns currentBps unchanged', () {
      final bwe = BandwidthEstimator()..setBps(750000);
      final n = bwe.onTwcc(_twcc([1000, 1000]), 0);
      expect(n, 750000);
    });

    test('negative deltas are summed by absolute value', () {
      final bwe = BandwidthEstimator(smoothing: 1.0);
      // |-3000| + |-3000| = 6000us window, 600B → 600*8 / 0.006 = 800_000.
      final n = bwe.onTwcc(_twcc([-3000, -3000]), 600);
      expect(n, 800000);
    });
  });

  group('LayerSelectorTimer', () {
    test('start schedules ticks; stop cancels and is idempotent',
        () async {
      final bwe = BandwidthEstimator()..setBps(2000000);
      final selector = LayerSelector(estimator: bwe);
      final timer = LayerSelectorTimer(
        selector: selector,
        interval: const Duration(milliseconds: 5),
      );
      timer.start();
      // Let at least one tick fire.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      timer.stop();
      timer.stop(); // idempotent
    });

    test('start cancels any previous timer (no double-fire)', () async {
      final bwe = BandwidthEstimator()..setBps(2000000);
      final selector = LayerSelector(estimator: bwe);
      final timer = LayerSelectorTimer(
        selector: selector,
        interval: const Duration(milliseconds: 5),
      );
      timer.start();
      timer.start(); // covers `_timer?.cancel()` branch with non-null timer
      await Future<void>.delayed(const Duration(milliseconds: 20));
      timer.stop();
    });
  });
}
