// Phase B-quick — exercise the TWCC parser branches the existing
// build/parse round-trip tests don't reach: run-length status chunks
// (T=0), 1-bit status-vector chunks (T=1, sym1=0), and the
// truncated-delta paths that emit deltaUs.add(null).

import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

/// Build a minimal TWCC packet with one status chunk and the given
/// delta bytes appended after the 8-byte FCI base. [length] is the
/// RFC-3550 length field in 32-bit words minus 1; caller picks it so
/// the parser sees the expected `pktLen` end-of-record.
Uint8List _twcc({
  required int senderSsrc,
  required int mediaSsrc,
  required int baseSeq,
  required int pktCount,
  required int chunk,
  required List<int> deltaBytes,
}) {
  // 12B header + 8B base + 2B chunk + N deltas, padded to 4B.
  final bodyLen = 8 + 2 + deltaBytes.length;
  final padded = (bodyLen + 3) & ~3;
  final total = 12 + padded;
  final out = Uint8List(total);
  final bd = ByteData.sublistView(out);
  out[0] = 0x80 | 15; // V=2, FMT=15
  out[1] = 205; // PT
  bd.setUint16(2, (total ~/ 4) - 1, Endian.big);
  bd.setUint32(4, senderSsrc, Endian.big);
  bd.setUint32(8, mediaSsrc, Endian.big);
  bd.setUint16(12, baseSeq, Endian.big);
  bd.setUint16(14, pktCount, Endian.big);
  // 3-byte refTime + 1-byte fbPktCount.
  out[16] = 0;
  out[17] = 0;
  out[18] = 0;
  out[19] = 1; // fbPktCount
  out[20] = (chunk >> 8) & 0xff;
  out[21] = chunk & 0xff;
  for (var i = 0; i < deltaBytes.length; i++) {
    out[22 + i] = deltaBytes[i];
  }
  return out;
}

void main() {
  group('parseFeedback TWCC parser branches', () {
    test('decodes a run-length chunk (T=0, status=1, runLen=4)', () {
      // Chunk: 0_01_0000000000100 = 0x2004.
      // Status 1 = received small (1-byte delta).
      final pkt = _twcc(
        senderSsrc: 0xAAAA,
        mediaSsrc: 0xBBBB,
        baseSeq: 100,
        pktCount: 4,
        chunk: 0x2004,
        deltaBytes: [10, 20, 30, 40],
      );
      final fb = parseFeedback(pkt).whereType<TwccFeedback>().single;
      expect(fb.statuses, [1, 1, 1, 1]);
      expect(fb.deltaUs, [10 * 250, 20 * 250, 30 * 250, 40 * 250]);
    });

    test('decodes a run-length of NOT-received (status=0)', () {
      // Chunk: T=0, S=00, L=3 → 0x0003. No deltas required (status 0).
      final pkt = _twcc(
        senderSsrc: 1,
        mediaSsrc: 2,
        baseSeq: 0,
        pktCount: 3,
        chunk: 0x0003,
        deltaBytes: const [],
      );
      final fb = parseFeedback(pkt).whereType<TwccFeedback>().single;
      expect(fb.statuses, [0, 0, 0]);
      expect(fb.deltaUs, [null, null, null]);
    });

    test('decodes a 1-bit status-vector chunk (T=1, sym1=0)', () {
      // Chunk: 10_00_0000000000_1111 = 0x800F (last 4 bits = 1).
      // Parser walks k=13..0; pktCount=4 means it consumes bits at
      // k=13,12,11,10 which are all 0 above. To get [1,1,1,1] place the
      // 4 received markers in the high bits: 0x80 00 with bits 13..10
      // set = 0x80 | (1<<13)|(1<<12)|(1<<11)|(1<<10) = 0x80 | 0x3C00
      // = 0xBC00. Wait — chunk is 16 bits; high bit (bit 15) = T,
      // bit 14 = sym1. So 0b10_1111_0000000000 = 0xBC00.
      final pkt = _twcc(
        senderSsrc: 1,
        mediaSsrc: 2,
        baseSeq: 0,
        pktCount: 4,
        chunk: 0xBC00,
        deltaBytes: [5, 6, 7, 8],
      );
      final fb = parseFeedback(pkt).whereType<TwccFeedback>().single;
      expect(fb.statuses, [1, 1, 1, 1]);
      expect(fb.deltaUs, [5 * 250, 6 * 250, 7 * 250, 8 * 250]);
    });

    test('truncated 1-byte delta yields null', () {
      // Run-length status=1, runLen=2 → chunk 0x2002. Provide ONLY 1
      // delta byte; the second should hit `ci+1 > off+pktLen` and emit
      // null.
      // bodyLen = 8 + 2 + 1 = 11 → padded 12 → total 24, length=5.
      // The padding byte at offset 23 is zero, but pktLen counts it
      // as in-record, so the check sees `ci+1 > off+pktLen` only if
      // the 2nd delta read would step past the record. With just one
      // padding byte, ci=23 and ci+1=24 > off+pktLen=24 is FALSE
      // (24 > 24 is false). So we need to truncate further: status=2
      // (2-byte delta) where only 1 padding byte is left.
      // bodyLen = 8 + 2 + 0 = 10 → padded 12 → 2 padding bytes. status=2
      // means parser tries to read 2 bytes at ci=22, ci+2=24 >
      // off+pktLen=24 is false → reads 2 zero bytes.
      // To FORCE the null branch, build a packet where the parser
      // claims more statuses than the buffer can hold: run-length
      // status=1, runLen=3, but only deliver 1 delta byte. The
      // padding gives us 1 extra byte (so 2 reads succeed reading
      // padding). We need runLen=4 with 0 deltas, so even the first
      // delta read fails: 8+2+0=10, padded 12 → 2 padding bytes
      // available. ci=22, first read ok (ci+1=23 ≤ 24); ci=23, second
      // read ci+1=24 ≤ 24 is true — also passes. Third: ci=24, ci+1=25
      // > 24 → null.
      final pkt = _twcc(
        senderSsrc: 1,
        mediaSsrc: 2,
        baseSeq: 0,
        pktCount: 3,
        chunk: 0x2003, // T=0, S=01, L=3
        deltaBytes: const [],
      );
      // Body bytes available for deltas: padded(10)-10 = 2 padding.
      // Reads at ci=22 (ok), ci=23 (ok), ci=24 → null.
      final fb = parseFeedback(pkt).whereType<TwccFeedback>().single;
      expect(fb.statuses, [1, 1, 1]);
      expect(fb.deltaUs.length, 3);
      expect(fb.deltaUs[2], isNull);
    });

    test('truncated 2-byte delta yields null', () {
      // Run-length status=2, runLen=2 → chunk 0x4002 (T=0, S=10, L=2).
      // Deliver 0 delta bytes: 8+2+0=10, padded 12 → 2 padding bytes.
      // First read needs 2 bytes (ci=22, ci+2=24 ≤ 24) → reads padding.
      // Second read: ci=24, ci+2=26 > 24 → null.
      final pkt = _twcc(
        senderSsrc: 1,
        mediaSsrc: 2,
        baseSeq: 0,
        pktCount: 2,
        chunk: 0x4002,
        deltaBytes: const [],
      );
      final fb = parseFeedback(pkt).whereType<TwccFeedback>().single;
      expect(fb.statuses, [2, 2]);
      expect(fb.deltaUs.length, 2);
      expect(fb.deltaUs[1], isNull);
    });
  });
}
