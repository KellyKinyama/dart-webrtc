import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

void main() {
  group('buildNack / parseFeedback round-trip', () {
    test('single missing seq', () {
      final pkt = buildNack(0xAAAAAAAA, 0xBBBBBBBB, [42]);
      final fbs = parseFeedback(pkt).toList();
      expect(fbs, hasLength(1));
      final nack = fbs.single as NackFeedback;
      expect(nack.senderSsrc, 0xAAAAAAAA);
      expect(nack.mediaSsrc, 0xBBBBBBBB);
      expect(nack.allMissing(), [42]);
    });

    test('contiguous seqs fold into one FCI', () {
      final missing = [100, 101, 102, 103];
      final pkt = buildNack(1, 2, missing);
      // length = 12-byte header + 4-byte FCI
      expect(pkt.length, 16);
      final nack = parseFeedback(pkt).single as NackFeedback;
      expect(nack.allMissing(), missing);
    });

    test('17+ seq spread emits multiple FCIs', () {
      final missing = List<int>.generate(20, (i) => 1000 + i);
      final pkt = buildNack(1, 2, missing);
      final nack = parseFeedback(pkt).single as NackFeedback;
      expect(nack.allMissing()..sort(), missing);
    });

    test('non-contiguous seqs preserved', () {
      final missing = [10, 12, 50];
      final pkt = buildNack(1, 2, missing);
      final nack = parseFeedback(pkt).single as NackFeedback;
      final got = nack.allMissing()..sort();
      expect(got, [10, 12, 50]);
    });
  });

  group('buildPli / parseFeedback', () {
    test('round-trip', () {
      final pkt = buildPli(0x11223344, 0x55667788);
      expect(pkt.length, 12);
      final fbs = parseFeedback(pkt).toList();
      expect(fbs, hasLength(1));
      final pli = fbs.single as PliFeedback;
      expect(pli.senderSsrc, 0x11223344);
      expect(pli.mediaSsrc, 0x55667788);
    });
  });

  group('parseFeedback compound', () {
    test('walks NACK + PLI in one buffer', () {
      final nack = buildNack(1, 100, [5, 6]);
      final pli = buildPli(1, 100);
      final compound = Uint8List.fromList([...nack, ...pli]);
      final fbs = parseFeedback(compound).toList();
      expect(fbs, hasLength(2));
      expect(fbs[0], isA<NackFeedback>());
      expect(fbs[1], isA<PliFeedback>());
    });

    test('skips unknown packet types (e.g. SR)', () {
      // V=2, PT=200 (SR), length=1 word (8 bytes total).
      final sr = <int>[
        0x80,
        200,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x01,
      ];
      final nack = buildNack(1, 2, [7]);
      final compound = Uint8List.fromList([...sr, ...nack]);
      final fbs = parseFeedback(compound).toList();
      expect(fbs, hasLength(1));
      expect(fbs.single, isA<NackFeedback>());
    });
  });

  group('SeqGapDetector', () {
    test('first packet emits no gap', () {
      final d = SeqGapDetector();
      expect(d.feed(100), isEmpty);
    });

    test('in-order packets emit no gap', () {
      final d = SeqGapDetector();
      d.feed(100);
      expect(d.feed(101), isEmpty);
      expect(d.feed(102), isEmpty);
    });

    test('skip of 3 emits the missing 2 in between', () {
      final d = SeqGapDetector();
      d.feed(100);
      expect(d.feed(103), [101, 102]);
    });

    test('reordered (older) packet ignored', () {
      final d = SeqGapDetector();
      d.feed(100);
      d.feed(105);
      expect(d.feed(102), isEmpty);
    });

    test('gap larger than maxGap is treated as restart', () {
      final d = SeqGapDetector(maxGap: 4);
      d.feed(100);
      expect(d.feed(200), isEmpty);
      expect(d.lastSeq, 200);
    });

    test('16-bit wrap is handled', () {
      final d = SeqGapDetector();
      d.feed(0xFFFE);
      expect(d.feed(0x0001), [0xFFFF, 0x0000]);
    });
  });
}
