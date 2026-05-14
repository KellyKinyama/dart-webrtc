// Phase 3b — SimulcastRewriter unit tests. Verifies SN/TS continuity
// across layer switches and RFC 4588 OSN rewriting.

import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/src/rtp_header.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/src/simulcast_rewriter.dart';
import 'package:test/test.dart';

/// Build a minimal 12-byte-header RTP packet with the given fields and
/// optional payload.
Uint8List _rtp({
  required int seq,
  required int ts,
  required int ssrc,
  int pt = 96,
  List<int> payload = const [],
}) {
  final out = Uint8List(12 + payload.length);
  out[0] = 0x80; // V=2, no padding/extension/CSRC
  out[1] = pt & 0x7f;
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
  for (var i = 0; i < payload.length; i++) {
    out[12 + i] = payload[i];
  }
  return out;
}

int _readSsrc(Uint8List p) =>
    (p[8] << 24) | (p[9] << 16) | (p[10] << 8) | p[11];

void main() {
  group('SimulcastRewriter', () {
    test('first packet establishes baseline = inbound SN/TS', () {
      final r = SimulcastRewriter(
        rewrittenPrimarySsrc: 0x11111111,
        rewrittenRtxSsrc: 0x22222222,
        currentLayer: 'f',
      );
      final p = _rtp(seq: 5000, ts: 90000, ssrc: 0xdeadbeef);
      final res = r.rewrite(rid: 'f', isRtx: false, rtp: p);

      expect(res.dropped, isFalse);
      expect(res.outSeq, 5000);
      expect(res.outTs, 90000);
      expect(_readSsrc(res.out!), 0x11111111);
      expect(rtpSeq(res.out!), 5000);
      expect(rtpTimestamp(res.out!), 90000);
    });

    test('SN/TS stay continuous across a layer switch', () {
      final r = SimulcastRewriter(
        rewrittenPrimarySsrc: 0x11111111,
        rewrittenRtxSsrc: null,
        currentLayer: 'f',
      );

      // Forward 3 packets on layer "f": in-SN 100..102, in-TS 9000+i*3000.
      for (var i = 0; i < 3; i++) {
        final res = r.rewrite(
          rid: 'f',
          isRtx: false,
          rtp: _rtp(seq: 100 + i, ts: 9000 + i * 3000, ssrc: 0xaaaaaaaa),
        );
        expect(res.outSeq, 100 + i);
        expect(res.outTs, 9000 + i * 3000);
      }

      // Switch to layer "q". Its SN/TS namespace is wildly different
      // (2000s, 50000s) — first forwarded packet must continue from
      // (lastOutSeq+1, lastOutTs+1) = (103, 15001).
      r.setCurrentLayer('q');
      final first = r.rewrite(
        rid: 'q',
        isRtx: false,
        rtp: _rtp(seq: 2000, ts: 50000, ssrc: 0xbbbbbbbb),
      );
      expect(first.outSeq, 103);
      expect(first.outTs, 15001);

      // Subsequent packet on q must keep that offset (delta within q
      // is preserved).
      final next = r.rewrite(
        rid: 'q',
        isRtx: false,
        rtp: _rtp(seq: 2001, ts: 53000, ssrc: 0xbbbbbbbb),
      );
      expect(next.outSeq, 104);
      expect(next.outTs, 18001);
    });

    test(
        'switch back to a previously-seen layer recomputes a fresh '
        'offset (does not reuse stale baseline)', () {
      final r = SimulcastRewriter(
        rewrittenPrimarySsrc: 0x11111111,
        rewrittenRtxSsrc: null,
        currentLayer: 'f',
      );
      // f: out 5000
      r.rewrite(
        rid: 'f',
        isRtx: false,
        rtp: _rtp(seq: 5000, ts: 1000, ssrc: 0xa),
      );
      // switch to q, forward in-SN 200 → out 5001
      r.setCurrentLayer('q');
      final qFirst = r.rewrite(
        rid: 'q',
        isRtx: false,
        rtp: _rtp(seq: 200, ts: 7000, ssrc: 0xb),
      );
      expect(qFirst.outSeq, 5001);
      // switch back to f. Even though f had a baseline, switching
      // forces recompute — in-SN 5005 → out 5002 (continuous).
      r.setCurrentLayer('f');
      final fAgain = r.rewrite(
        rid: 'f',
        isRtx: false,
        rtp: _rtp(seq: 5005, ts: 1500, ssrc: 0xa),
      );
      expect(fAgain.outSeq, 5002);
      expect(fAgain.outTs, 1002);
    });

    test('RTX packets shift their OSN by the layer\'s snOffset', () {
      final r = SimulcastRewriter(
        rewrittenPrimarySsrc: 0x11111111,
        rewrittenRtxSsrc: 0x22222222,
        currentLayer: 'f',
      );
      // Establish layer "f" with in-SN 100 → out 100 (no shift yet).
      r.rewrite(
        rid: 'f',
        isRtx: false,
        rtp: _rtp(seq: 100, ts: 1000, ssrc: 0xa),
      );
      // Switch to q to introduce a non-zero offset on q.
      r.setCurrentLayer('q');
      final qP = r.rewrite(
        rid: 'q',
        isRtx: false,
        rtp: _rtp(seq: 7000, ts: 50000, ssrc: 0xb),
      );
      expect(qP.outSeq, 101);
      // qOffset = 101 - 7000 = -6899 (mod 2^16 = 58637).
      // RTX packet for q with OSN=7000 should have outbound OSN=101.
      final rtx = r.rewrite(
        rid: 'q',
        isRtx: true,
        rtp: _rtp(
          seq: 33000,
          ts: 50000,
          ssrc: 0xc,
          payload: [0x1b, 0x58 /* OSN = 7000 */, 0xde, 0xad],
        ),
      );
      expect(rtx.dropped, isFalse);
      expect(rtx.isRtx, isTrue);
      expect(_readSsrc(rtx.out!), 0x22222222);
      // Read OSN from the rewritten payload (offset 12 since no CSRC,
      // no extension).
      final osn = (rtx.out![12] << 8) | rtx.out![13];
      expect(osn, 101);
    });

    test('RTX before any primary on its layer is dropped', () {
      final r = SimulcastRewriter(
        rewrittenPrimarySsrc: 0x11111111,
        rewrittenRtxSsrc: 0x22222222,
        currentLayer: 'f',
      );
      // Send an RTX for a layer (q) that has never had a primary.
      final res = r.rewrite(
        rid: 'q',
        isRtx: true,
        rtp: _rtp(seq: 1, ts: 1, ssrc: 0xc, payload: [0, 100, 0, 0]),
      );
      expect(res.dropped, isTrue);
    });

    test('setCurrentLayer reports change and increments layerSwitches', () {
      final r = SimulcastRewriter(
        rewrittenPrimarySsrc: 1,
        rewrittenRtxSsrc: null,
        currentLayer: 'f',
      );
      expect(r.setCurrentLayer('f'), isFalse);
      expect(r.layerSwitches, 0);
      expect(r.setCurrentLayer('h'), isTrue);
      expect(r.currentLayer, 'h');
      expect(r.layerSwitches, 1);
      expect(r.setCurrentLayer('q'), isTrue);
      expect(r.layerSwitches, 2);
    });

    test('SN wrap-around: outbound SN wraps cleanly past 65535', () {
      final r = SimulcastRewriter(
        rewrittenPrimarySsrc: 1,
        rewrittenRtxSsrc: null,
        currentLayer: 'f',
      );
      // First packet → out 65534.
      r.rewrite(
        rid: 'f',
        isRtx: false,
        rtp: _rtp(seq: 65534, ts: 0, ssrc: 0xa),
      );
      final w = r.rewrite(
        rid: 'f',
        isRtx: false,
        rtp: _rtp(seq: 65535, ts: 1, ssrc: 0xa),
      );
      expect(w.outSeq, 65535);
      final wrap = r.rewrite(
        rid: 'f',
        isRtx: false,
        rtp: _rtp(seq: 65536 & 0xffff, ts: 2, ssrc: 0xa),
      );
      expect(wrap.outSeq, 0);
    });
  });

  group('rtpPayloadOffset', () {
    test('plain header → 12', () {
      final p = _rtp(seq: 1, ts: 1, ssrc: 1, payload: [0, 1, 2]);
      expect(rtpPayloadOffset(p), 12);
    });

    test('one CSRC adds 4', () {
      final p = _rtp(seq: 1, ts: 1, ssrc: 1, payload: [0, 1, 2]);
      // Set CC=1 and append 4 bytes of CSRC + 3 bytes payload.
      final out = Uint8List(12 + 4 + 3);
      out.setAll(0, p.sublist(0, 12));
      out[0] = 0x81; // V=2, CC=1
      // 4-byte CSRC at 12..16, payload at 16.
      out[16] = 0x01;
      out[17] = 0x02;
      out[18] = 0x03;
      expect(rtpPayloadOffset(out), 16);
    });

    test('extension: 12 + 4 + extLen*4', () {
      final out = Uint8List(12 + 4 + 8 + 2);
      out[0] = 0x90; // V=2, X=1
      out[1] = 96;
      // Sequence/ts/ssrc don't matter for this assertion.
      // Extension header at offset 12: defined-by(2) + length(2). Set
      // length-in-32bit-words = 2.
      out[12] = 0xbe;
      out[13] = 0xde;
      out[14] = 0x00;
      out[15] = 0x02;
      // 8 bytes of extension data follow, then 2 bytes payload.
      expect(rtpPayloadOffset(out), 12 + 4 + 8);
    });
  });
}
