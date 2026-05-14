// Phase 7b — delay-based BWE tests (BandwidthEstimator.onTwccDelay).

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

/// Build a synthetic TwccFeedback for [seqs] with the given
/// [arrivalUs] absolute arrival times (length must match seqs).
/// Status is `1` (received) for every seq. The feedback's
/// `referenceTime` is set to the first arrival's 64ms anchor; the
/// deltaUs list reconstructs the absolute timeline.
TwccFeedback _twcc({
  required int baseSeq,
  required List<int> arrivalUs,
}) {
  // Compute referenceTime in 64ms units rounded down to the nearest
  // 64ms boundary at or below the first arrival.
  final ref64ms = arrivalUs.first ~/ (64 * 1000);
  final anchorUs = ref64ms * 64 * 1000;
  final deltas = <int?>[];
  var prev = anchorUs;
  for (final a in arrivalUs) {
    deltas.add(a - prev);
    prev = a;
  }
  return TwccFeedback(
    senderSsrc: 1,
    mediaSsrc: 2,
    baseSeq: baseSeq,
    packetCount: arrivalUs.length,
    referenceTime: ref64ms,
    fbPacketCount: 0,
    statuses: List<int>.filled(arrivalUs.length, 1),
    deltaUs: deltas,
  );
}

void main() {
  group('BandwidthEstimator.onTwccDelay', () {
    test('flat delay (arrival_delay constant) → hold, throughput EMA',
        () {
      final st = TwccStamper();
      // 10 packets at 1000us send interval, 1200-byte each.
      final seqs = <int>[];
      for (var i = 0; i < 10; i++) {
        seqs.add(st.reserve(
          sizeBytes: 1200,
          sendTimeMicros: 1_000_000 + i * 1_000,
        ));
      }
      // Arrival: constant 5000us network delay.
      final arrivals = [for (final s in seqs) 1_000_000 + s * 1_000 + 5_000];
      final fb = _twcc(baseSeq: seqs.first, arrivalUs: arrivals);
      final bwe = BandwidthEstimator();
      bwe.onTwccDelay(fb, st);
      expect(bwe.lastDecision, BweDecision.hold);
      // Send rate: 10 pkts * 1200 B * 8 bits / 9ms = ~10.67 Mbps.
      expect(bwe.lastMeasuredBps, closeTo(10_666_666, 200_000));
      // First update seeds estimate to measured.
      expect(bwe.currentBps, closeTo(bwe.lastMeasuredBps, 1));
      // Slope ~= 0.
      expect(bwe.lastSlope.abs(), lessThan(0.001));
    });

    test('growing delay → decrease decision', () {
      final st = TwccStamper();
      final seqs = <int>[];
      for (var i = 0; i < 10; i++) {
        seqs.add(st.reserve(
          sizeBytes: 1200,
          sendTimeMicros: 1_000_000 + i * 1_000,
        ));
      }
      // Arrival delay grows by 200us per packet → strong positive
      // slope (200us per 1000us send-time = 0.2 ≫ overuseSlope 0.01).
      final arrivals = [
        for (var i = 0; i < seqs.length; i++)
          1_000_000 + i * 1_000 + 5_000 + i * 200,
      ];
      final fb = _twcc(baseSeq: seqs.first, arrivalUs: arrivals);
      final bwe = BandwidthEstimator()..setBps(2_000_000);
      final before = bwe.currentBps;
      bwe.onTwccDelay(fb, st);
      expect(bwe.lastDecision, BweDecision.decrease);
      expect(bwe.lastSlope, greaterThan(0.01));
      expect(bwe.currentBps, lessThan(before));
    });

    test('shrinking delay → increase decision', () {
      final st = TwccStamper();
      final seqs = <int>[];
      for (var i = 0; i < 10; i++) {
        seqs.add(st.reserve(
          sizeBytes: 1200,
          sendTimeMicros: 1_000_000 + i * 1_000,
        ));
      }
      // Delay shrinks by 200us per packet.
      final arrivals = [
        for (var i = 0; i < seqs.length; i++)
          1_000_000 + i * 1_000 + 5_000 - i * 200,
      ];
      final fb = _twcc(baseSeq: seqs.first, arrivalUs: arrivals);
      final bwe = BandwidthEstimator()..setBps(1_000_000);
      final before = bwe.currentBps;
      bwe.onTwccDelay(fb, st);
      expect(bwe.lastDecision, BweDecision.increase);
      expect(bwe.lastSlope, lessThan(-0.01));
      expect(bwe.currentBps, greaterThan(before));
    });

    test('missing history is silently dropped', () {
      final st = TwccStamper();
      // Stamp ONE packet then immediately query about a sequence that
      // was never stamped.
      final s0 = st.reserve(sizeBytes: 1200, sendTimeMicros: 1_000_000);
      final fb = _twcc(baseSeq: s0, arrivalUs: [1_005_000, 1_006_000]);
      final bwe = BandwidthEstimator()..setBps(800_000);
      final before = bwe.currentBps;
      // Only the first sample has history; the second drops → < 2
      // samples → no update.
      bwe.onTwccDelay(fb, st);
      expect(bwe.currentBps, before);
      expect(bwe.lastDecision, BweDecision.hold);
    });

    test('all-not-received → hold, no update', () {
      final st = TwccStamper();
      st.reserve(sizeBytes: 1200, sendTimeMicros: 1_000_000);
      st.reserve(sizeBytes: 1200, sendTimeMicros: 1_001_000);
      final fb = TwccFeedback(
        senderSsrc: 1, mediaSsrc: 2,
        baseSeq: 0,
        packetCount: 2,
        referenceTime: 1_000_000 ~/ (64 * 1000),
        fbPacketCount: 0,
        statuses: const [0, 0],
        deltaUs: const [null, null],
      );
      final bwe = BandwidthEstimator()..setBps(1_500_000);
      bwe.onTwccDelay(fb, st);
      expect(bwe.lastDecision, BweDecision.hold);
      expect(bwe.currentBps, 1_500_000);
    });
  });
}
