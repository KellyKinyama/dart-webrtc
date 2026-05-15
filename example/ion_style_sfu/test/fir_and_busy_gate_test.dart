// Tests for the small ion-sfu-inspired hardening batch:
//   * RTCP FIR (RFC 5104 §4.3.1.1) parser + builder
//   * SimulcastRewriter.switchInFlight gate (the "busy" state used
//     to reject overlapping layer switches)
//
// The PLI-rate-limit + FIR-escalation behaviour on Subscriber is
// covered in pli_rate_limit_test.dart, which exercises the actual
// `_sendUpstreamPli` path through public DownTrack state.

import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/src/rtcp.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/src/simulcast_rewriter.dart';
import 'package:test/test.dart';

Uint8List _rtp({
  required int seq,
  required int ts,
  required int ssrc,
}) {
  final out = Uint8List(12);
  out[0] = 0x80;
  out[1] = 96;
  out[2] = (seq >> 8) & 0xff;
  out[3] = seq & 0xff;
  out[4] = (ts >> 24) & 0xff;
  out[5] = (ts >> 16) & 0xff;
  out[6] = (ts >> 8) & 0xff;
  out[7] = ts & 0xff;
  out[8] = (ssrc >> 24) & 0xff;
  out[9] = (ssrc >> 16) & 0xff;
  out[10] = (ssrc >> 8) & 0xff;
  out[11] = ssrc & 0xff;
  return out;
}

void main() {
  group('FIR (RFC 5104)', () {
    test('buildFir produces a 20-byte PSFB FMT=4 packet', () {
      final pkt = buildFir(0xAAAAAAAA, 0xDEADBEEF, 7);
      expect(pkt.length, 20);
      // Byte 0: V=2 (top 2 bits = 10), FMT=4 (low 5 bits).
      expect(pkt[0] & 0xc0, 0x80);
      expect(pkt[0] & 0x1f, 4);
      // Byte 1: PT = 206 (PSFB).
      expect(pkt[1], 206);
      // Length in 32-bit words, minus 1 = 4 (i.e. 20-byte packet).
      expect((pkt[2] << 8) | pkt[3], 4);
      // Sender SSRC.
      expect(
          (pkt[4] << 24) | (pkt[5] << 16) | (pkt[6] << 8) | pkt[7], 0xAAAAAAAA);
      // Media SSRC field (FIR uses per-FCI target instead, this is 0).
      expect((pkt[8] << 24) | (pkt[9] << 16) | (pkt[10] << 8) | pkt[11], 0);
      // FCI: 4B target SSRC + 1B seq + 3B reserved.
      expect((pkt[12] << 24) | (pkt[13] << 16) | (pkt[14] << 8) | pkt[15],
          0xDEADBEEF);
      expect(pkt[16], 7);
    });

    test('parseFeedback round-trips a single-target FIR', () {
      final pkt = buildFir(0x11111111, 0x22222222, 3);
      final fbs = parseFeedback(pkt).toList();
      expect(fbs, hasLength(1));
      final fir = fbs.first;
      expect(fir, isA<FirFeedback>());
      fir as FirFeedback;
      expect(fir.senderSsrc, 0x11111111);
      expect(fir.targetSsrcs, [0x22222222]);
    });

    test('parseFeedback decodes a multi-target FIR', () {
      // Hand-roll a 3-target FIR (header 12B + 3*8B FCIs = 36B = 9 words).
      final out = Uint8List(36);
      out[0] = 0x80 | 4;
      out[1] = 206;
      out[2] = 0;
      out[3] = 8; // length-1 in words
      // sender ssrc
      out[4] = 0xCA;
      out[5] = 0xFE;
      out[6] = 0xBA;
      out[7] = 0xBE;
      // media ssrc (unused)
      // FCIs
      void putFci(int o, int ssrc, int seq) {
        out[o] = (ssrc >> 24) & 0xff;
        out[o + 1] = (ssrc >> 16) & 0xff;
        out[o + 2] = (ssrc >> 8) & 0xff;
        out[o + 3] = ssrc & 0xff;
        out[o + 4] = seq & 0xff;
      }

      putFci(12, 0xAAA1, 1);
      putFci(20, 0xAAA2, 2);
      putFci(28, 0xAAA3, 3);

      final fbs = parseFeedback(out).toList();
      expect(fbs, hasLength(1));
      final fir = fbs.single as FirFeedback;
      expect(fir.targetSsrcs, [0xAAA1, 0xAAA2, 0xAAA3]);
    });

    test('FIR coexists with PLI/NACK in a compound RTCP buffer', () {
      final pli = buildPli(1, 0xAAA1);
      final fir = buildFir(1, 0xBBB1, 5);
      final compound = Uint8List(pli.length + fir.length)
        ..setRange(0, pli.length, pli)
        ..setRange(pli.length, pli.length + fir.length, fir);
      final fbs = parseFeedback(compound).toList();
      expect(fbs, hasLength(2));
      expect(fbs[0], isA<PliFeedback>());
      expect(fbs[1], isA<FirFeedback>());
    });
  });

  group('SimulcastRewriter.switchInFlight (busy-gate)', () {
    test(
        'starts true (no primary forwarded yet) and clears after first'
        ' primary on the current layer', () {
      final r = SimulcastRewriter(
        rewrittenPrimarySsrc: 0x1111,
        rewrittenRtxSsrc: 0x2222,
        currentLayer: 'f',
      );
      expect(r.switchInFlight, isTrue);
      r.rewrite(rid: 'f', isRtx: false, rtp: _rtp(seq: 100, ts: 1000, ssrc: 1));
      expect(r.switchInFlight, isFalse);
    });

    test('setCurrentLayer to a new RID re-arms switchInFlight', () {
      final r = SimulcastRewriter(
        rewrittenPrimarySsrc: 0x1111,
        rewrittenRtxSsrc: 0x2222,
        currentLayer: 'f',
      );
      r.rewrite(rid: 'f', isRtx: false, rtp: _rtp(seq: 1, ts: 1, ssrc: 1));
      expect(r.switchInFlight, isFalse);
      expect(r.setCurrentLayer('q'), isTrue);
      expect(r.switchInFlight, isTrue);
      r.rewrite(rid: 'q', isRtx: false, rtp: _rtp(seq: 999, ts: 9999, ssrc: 2));
      expect(r.switchInFlight, isFalse);
    });

    test('setCurrentLayer to the same RID is a no-op and does not re-arm', () {
      final r = SimulcastRewriter(
        rewrittenPrimarySsrc: 0x1111,
        rewrittenRtxSsrc: 0x2222,
        currentLayer: 'f',
      );
      r.rewrite(rid: 'f', isRtx: false, rtp: _rtp(seq: 1, ts: 1, ssrc: 1));
      expect(r.switchInFlight, isFalse);
      expect(r.setCurrentLayer('f'), isFalse);
      expect(r.switchInFlight, isFalse);
    });
  });
}
