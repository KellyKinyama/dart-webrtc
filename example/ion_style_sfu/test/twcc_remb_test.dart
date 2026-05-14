// Phase 5 — REMB and TWCC parse/build round-trip tests.

import 'package:pure_dart_webrtc_ion_style_sfu/src/rtcp.dart';
import 'package:test/test.dart';

void main() {
  group('REMB', () {
    test('build → parse round-trip preserves bps and SSRCs', () {
      final pkt = buildRemb(0xdeadbeef, 2_000_000, [111, 222, 333]);
      final fb = parseFeedback(pkt).whereType<RembFeedback>().single;
      expect(fb.senderSsrc, 0xdeadbeef);
      // 18-bit mantissa + 6-bit exp may round; expect within 0.5%.
      expect(fb.bps, closeTo(2_000_000, 10_000));
      expect(fb.ssrcs, [111, 222, 333]);
    });

    test('small values fit without exponent shift', () {
      final pkt = buildRemb(1, 100_000, [42]);
      final fb = parseFeedback(pkt).whereType<RembFeedback>().single;
      expect(fb.bps, 100_000);
      expect(fb.ssrcs, [42]);
    });

    test('large values round but stay close', () {
      final pkt = buildRemb(1, 50_000_000, [42]);
      final fb = parseFeedback(pkt).whereType<RembFeedback>().single;
      expect((fb.bps - 50_000_000).abs() < 50_000_000 * 0.01, isTrue);
    });

    test('non-REMB PSFB FMT=15 is ignored', () {
      // Crafted: PT=206 FMT=15 but no 'REMB' magic.
      final pkt = buildRemb(1, 1_000_000, [1]);
      // Overwrite magic to break it.
      pkt[12] = 0;
      expect(parseFeedback(pkt).whereType<RembFeedback>(), isEmpty);
    });
  });

  group('TWCC', () {
    test('build → parse round-trip preserves seq + arrival deltas', () {
      // Base arrival 1_000_000us; subsequent arrivals at 1ms increments
      // (delta = 1000us = 4 quarter-ms units → small-delta).
      final arrivals = <(int, int)>[
        (1000, 1_000_000),
        (1001, 1_001_000),
        (1002, 1_002_000),
        (1004, 1_004_500), // gap at 1003
      ];
      final pkt = buildTwcc(
        senderSsrc: 1,
        mediaSsrc: 2,
        fbPktCount: 7,
        arrivals: arrivals,
      )!;
      final fb = parseFeedback(pkt).whereType<TwccFeedback>().single;
      expect(fb.baseSeq, 1000);
      expect(fb.packetCount, 5); // seqs 1000..1004 inclusive
      expect(fb.fbPacketCount, 7);
      // statuses: [received, received, received, NOT, received]
      expect(fb.statuses, [1, 1, 1, 0, 1]);
      // deltaUs: first delta is relative to 64ms-aligned anchor, so it
      // can include a sub-64ms initial offset. We assert subsequent
      // deltas only.
      expect(fb.deltaUs[1], 1_000); // ~1ms
      expect(fb.deltaUs[2], 1_000);
      expect(fb.deltaUs[3], isNull); // dropped
      // 1004 arrived 2500us after 1002 (since 1003 dropped).
      expect(fb.deltaUs[4], 2_500);
    });

    test('build returns null for empty arrivals', () {
      expect(
        buildTwcc(
          senderSsrc: 1, mediaSsrc: 2, fbPktCount: 0, arrivals: [],
        ),
        isNull,
      );
    });

    test('large negative delta uses 16-bit signed encoding', () {
      // Two arrivals where the second arrives 1 second EARLIER (clock
      // jump). Should encode as status=2.
      final arrivals = <(int, int)>[
        (100, 2_000_000),
        (101, 1_000_000),
      ];
      final pkt = buildTwcc(
        senderSsrc: 1, mediaSsrc: 2, fbPktCount: 1, arrivals: arrivals,
      )!;
      final fb = parseFeedback(pkt).whereType<TwccFeedback>().single;
      expect(fb.statuses.length, 2);
      expect(fb.statuses[1], 2);
      expect(fb.deltaUs[1], lessThan(0));
    });
  });
}
