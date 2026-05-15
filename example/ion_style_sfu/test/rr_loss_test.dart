// Tests for the small ion-sfu-inspired observability + adaptation
// batch:
//   * RFC 3550 §6.4.2 Receiver Report parsing (RrFeedback)
//   * BandwidthEstimator.onRr loss-based back-off
//   * Receiver.jitterMs EMA against synthetic primary RTP arrivals
//
// All three changes ride alongside the existing TWCC-driven path; the
// goal is "still works when TWCC is silent" (real-world: callers that
// don't negotiate transport-cc, or a brief gap in feedback).

import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/src/bwe.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/src/rtcp.dart';
import 'package:test/test.dart';

/// Build a minimal RR (PT=201) with one report block carrying the
/// supplied [fractionLost] (0..255) and [jitter] (RTP units).
Uint8List _rr({
  required int reporterSsrc,
  required int sourceSsrc,
  required int fractionLost,
  int cumulativeLost = 0,
  int jitter = 0,
}) {
  // Header (8B) + 1 report block (24B) = 32B = 8 32-bit words.
  final out = Uint8List(32);
  final bd = ByteData.sublistView(out);
  out[0] = 0x80 | 1; // V=2, RC=1
  out[1] = 201;
  bd.setUint16(2, 7, Endian.big); // length-1 in words
  bd.setUint32(4, reporterSsrc, Endian.big);
  bd.setUint32(8, sourceSsrc, Endian.big);
  out[12] = fractionLost & 0xff;
  out[13] = (cumulativeLost >> 16) & 0xff;
  out[14] = (cumulativeLost >> 8) & 0xff;
  out[15] = cumulativeLost & 0xff;
  bd.setUint32(16, 0, Endian.big); // highest seq
  bd.setUint32(20, jitter, Endian.big);
  bd.setUint32(24, 0, Endian.big); // lsr
  bd.setUint32(28, 0, Endian.big); // dlsr
  return out;
}

void main() {
  group('RR parsing', () {
    test('decodes a one-block RR', () {
      final rr = _rr(
        reporterSsrc: 0xAAAAAAAA,
        sourceSsrc: 0xBBBBBBBB,
        fractionLost: 64, // 25%
        cumulativeLost: 12,
        jitter: 4500,
      );
      final fbs = parseFeedback(rr).toList();
      expect(fbs, hasLength(1));
      final r = fbs.single as RrFeedback;
      expect(r.senderSsrc, 0xAAAAAAAA);
      expect(r.blocks, hasLength(1));
      final b = r.blocks.single;
      expect(b.sourceSsrc, 0xBBBBBBBB);
      expect(b.fractionLost, 64);
      expect(b.fractionLostUnit, closeTo(0.25, 1e-9));
      expect(b.cumulativeLost, 12);
      expect(b.jitter, 4500);
    });

    test('coexists with NACK / PLI in a compound RTCP buffer', () {
      final rr = _rr(reporterSsrc: 1, sourceSsrc: 2, fractionLost: 0);
      final pli = buildPli(1, 2);
      final compound = Uint8List(rr.length + pli.length)
        ..setRange(0, rr.length, rr)
        ..setRange(rr.length, rr.length + pli.length, pli);
      final fbs = parseFeedback(compound).toList();
      expect(fbs, hasLength(2));
      expect(fbs[0], isA<RrFeedback>());
      expect(fbs[1], isA<PliFeedback>());
    });
  });

  group('BandwidthEstimator.onRr', () {
    test('records lastFractionLost and stamps lastRrAt', () {
      final bwe = BandwidthEstimator()..setBps(1000000);
      bwe.onRr(RrFeedback(senderSsrc: 1, blocks: [
        const RrReportBlock(
            sourceSsrc: 1,
            fractionLost: 32, // ~12.5%
            cumulativeLost: 0,
            highestSeq: 0,
            jitter: 0,
            lsr: 0,
            dlsr: 0),
      ]));
      expect(bwe.lastFractionLost, closeTo(32 / 256.0, 1e-9));
      expect(bwe.lastRrAt, isNotNull);
      expect(bwe.hasFreshRr, isTrue);
    });

    test('picks the worst-case block across simulcast layers', () {
      final bwe = BandwidthEstimator()..setBps(1000000);
      bwe.onRr(RrFeedback(senderSsrc: 1, blocks: const [
        RrReportBlock(
            sourceSsrc: 1,
            fractionLost: 5, // ~2%
            cumulativeLost: 0,
            highestSeq: 0,
            jitter: 0,
            lsr: 0,
            dlsr: 0),
        RrReportBlock(
            sourceSsrc: 2,
            fractionLost: 80, // ~31% — this one wins
            cumulativeLost: 0,
            highestSeq: 0,
            jitter: 0,
            lsr: 0,
            dlsr: 0),
      ]));
      expect(bwe.lastFractionLost, closeTo(80 / 256.0, 1e-9));
    });

    test('above 10% loss triggers a multiplicative back-off', () {
      final bwe = BandwidthEstimator()..setBps(1000000);
      // 30% loss: well above the 10% threshold.
      bwe.onRr(RrFeedback(senderSsrc: 1, blocks: const [
        RrReportBlock(
            sourceSsrc: 1,
            fractionLost: 77, // 30.1%
            cumulativeLost: 0,
            highestSeq: 0,
            jitter: 0,
            lsr: 0,
            dlsr: 0),
      ]));
      // Default decreaseFactor = 0.85.
      expect(bwe.currentBps, 850000);
    });

    test('below 10% loss leaves currentBps untouched', () {
      final bwe = BandwidthEstimator()..setBps(1000000);
      bwe.onRr(RrFeedback(senderSsrc: 1, blocks: const [
        RrReportBlock(
            sourceSsrc: 1,
            fractionLost: 12, // ~4.7%
            cumulativeLost: 0,
            highestSeq: 0,
            jitter: 0,
            lsr: 0,
            dlsr: 0),
      ]));
      expect(bwe.currentBps, 1000000);
      expect(bwe.lastFractionLost, closeTo(12 / 256.0, 1e-9));
    });

    test('does not back off when currentBps is still 0 (no baseline)', () {
      final bwe = BandwidthEstimator();
      bwe.onRr(RrFeedback(senderSsrc: 1, blocks: const [
        RrReportBlock(
            sourceSsrc: 1,
            fractionLost: 200, // ~78% loss
            cumulativeLost: 0,
            highestSeq: 0,
            jitter: 0,
            lsr: 0,
            dlsr: 0),
      ]));
      // Still 0 — multiplicative back-off on 0 yields 0; we recorded
      // the loss reading but didn't fabricate an estimate.
      expect(bwe.currentBps, 0);
      expect(bwe.lastFractionLost, closeTo(200 / 256.0, 1e-9));
    });

    test('empty-block RR is a silent no-op', () {
      final bwe = BandwidthEstimator()..setBps(1000000);
      bwe.onRr(const RrFeedback(senderSsrc: 1, blocks: []));
      expect(bwe.currentBps, 1000000);
      expect(bwe.lastRrAt, isNull);
    });
  });
}
