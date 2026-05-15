// H.264 keyframe detection + reSync gate on SimulcastRewriter.

import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/src/byte_pool.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/src/h264.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/src/simulcast_rewriter.dart';
import 'package:test/test.dart';

/// Build an RTP packet with an H.264 payload starting with [h264Bytes].
Uint8List _rtpWithH264({
  required int seq,
  required int ts,
  required List<int> h264Bytes,
  int ssrc = 0xCAFE,
  int pt = 102,
}) {
  final out = Uint8List(12 + h264Bytes.length);
  out[0] = 0x80;
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
  out.setRange(12, 12 + h264Bytes.length, h264Bytes);
  return out;
}

/// NAL header byte with F=0, NRI=3 (highest), and the given type.
int _nalHdr(int type) => 0x60 | (type & 0x1f);

void main() {
  group('isH264Keyframe — single NAL unit', () {
    test('true for IDR slice (type 5)', () {
      final pkt =
          _rtpWithH264(seq: 1, ts: 0, h264Bytes: [_nalHdr(5), 0xaa, 0xbb]);
      expect(isH264Keyframe(pkt), isTrue);
    });

    test('true for SPS (7), PPS (8), SEI (6)', () {
      for (final t in [6, 7, 8]) {
        final pkt = _rtpWithH264(seq: 1, ts: 0, h264Bytes: [_nalHdr(t), 0x00]);
        expect(isH264Keyframe(pkt), isTrue, reason: 'type=$t');
      }
    });

    test('false for non-IDR slice (type 1)', () {
      final pkt =
          _rtpWithH264(seq: 1, ts: 0, h264Bytes: [_nalHdr(1), 0xaa, 0xbb]);
      expect(isH264Keyframe(pkt), isFalse);
    });

    test('false for slice data partition A/B/C (types 2..4)', () {
      for (final t in [2, 3, 4]) {
        final pkt = _rtpWithH264(seq: 1, ts: 0, h264Bytes: [_nalHdr(t), 0x00]);
        expect(isH264Keyframe(pkt), isFalse, reason: 'type=$t');
      }
    });
  });

  group('isH264Keyframe — FU-A fragmentation', () {
    test('true on START fragment of an IDR', () {
      // FU indicator: NRI=3, type=28 → 0x7c
      // FU header   : S=1, type=5 → 0x85
      final pkt = _rtpWithH264(
          seq: 1, ts: 0, h264Bytes: [0x7c, 0x85, 0x01, 0x02, 0x03]);
      expect(isH264Keyframe(pkt), isTrue);
    });

    test('false on MIDDLE fragment of an IDR (S=0, E=0)', () {
      final pkt =
          _rtpWithH264(seq: 2, ts: 0, h264Bytes: [0x7c, 0x05, 0xaa, 0xbb]);
      expect(isH264Keyframe(pkt), isFalse);
    });

    test('false on END fragment of an IDR (E=1)', () {
      final pkt = _rtpWithH264(seq: 3, ts: 0, h264Bytes: [0x7c, 0x45, 0xaa]);
      expect(isH264Keyframe(pkt), isFalse);
    });

    test('false on START fragment of a non-IDR slice', () {
      // FU header: S=1, type=1 → 0x81
      final pkt =
          _rtpWithH264(seq: 1, ts: 0, h264Bytes: [0x7c, 0x81, 0xaa, 0xbb]);
      expect(isH264Keyframe(pkt), isFalse);
    });
  });

  group('isH264Keyframe — STAP-A aggregation', () {
    test('true when an aggregated NALU is SPS/PPS/IDR', () {
      // STAP-A NAL header (type 24, NRI=3) = 0x78
      // Aggregated #1: size=2, NALU = SPS (type 7), 1 byte body
      // Aggregated #2: size=2, NALU = IDR (type 5), 1 byte body
      final pkt = _rtpWithH264(seq: 1, ts: 0, h264Bytes: [
        0x78,
        0x00,
        0x02,
        _nalHdr(7),
        0x11,
        0x00,
        0x02,
        _nalHdr(5),
        0x22,
      ]);
      expect(isH264Keyframe(pkt), isTrue);
    });

    test('false when all aggregated NALUs are non-keyframe slices', () {
      final pkt = _rtpWithH264(seq: 1, ts: 0, h264Bytes: [
        0x78,
        0x00,
        0x02,
        _nalHdr(1),
        0x11,
        0x00,
        0x02,
        _nalHdr(1),
        0x22,
      ]);
      expect(isH264Keyframe(pkt), isFalse);
    });
  });

  group('isH264Keyframe — robustness', () {
    test('false on empty payload', () {
      final pkt = _rtpWithH264(seq: 1, ts: 0, h264Bytes: const []);
      expect(isH264Keyframe(pkt), isFalse);
    });

    test('false on truncated FU-A (no FU header)', () {
      final pkt = _rtpWithH264(seq: 1, ts: 0, h264Bytes: [0x7c]);
      expect(isH264Keyframe(pkt), isFalse);
    });

    test('false on truncated STAP-A (size points past end)', () {
      final pkt = _rtpWithH264(
          seq: 1, ts: 0, h264Bytes: [0x78, 0x00, 0x10, _nalHdr(5)]);
      expect(isH264Keyframe(pkt), isFalse);
    });
  });

  group('SimulcastRewriter reSync gate — H264', () {
    test('drops H264 delta frames after a layer switch until IDR arrives', () {
      final rw = SimulcastRewriter(
        rewrittenPrimarySsrc: 0xAAAA,
        rewrittenRtxSsrc: null,
        currentLayer: 'h',
        pool: BytePool(),
        isKeyframe: isH264Keyframe,
      );

      // Initial IDR on 'h' establishes the baseline.
      final kf1 = _rtpWithH264(seq: 100, ts: 1000, h264Bytes: [_nalHdr(5)]);
      var r = rw.rewrite(rid: 'h', isRtx: false, rtp: kf1);
      expect(r.dropped, isFalse,
          reason: 'first keyframe must establish offset');

      // A delta frame (P-slice, type 1) passes through normally.
      final delta = _rtpWithH264(seq: 101, ts: 1100, h264Bytes: [_nalHdr(1)]);
      r = rw.rewrite(rid: 'h', isRtx: false, rtp: delta);
      expect(r.dropped, isFalse);

      // Switch to 'q'. Until an IDR (or SPS/PPS/SEI) arrives, every
      // delta on 'q' must be dropped by the gate.
      rw.setCurrentLayer('q');
      for (var i = 0; i < 3; i++) {
        final pkt = _rtpWithH264(
            seq: 200 + i, ts: 5000 + i * 100, h264Bytes: [_nalHdr(1)]);
        r = rw.rewrite(rid: 'q', isRtx: false, rtp: pkt);
        expect(r.dropped, isTrue,
            reason: 'delta frame #$i on new layer must be gated');
      }
      expect(rw.gateDropped, 3);
      expect(rw.switchInFlight, isTrue);

      // Now an IDR lands on 'q' — gate opens, packet forwarded.
      final kf2 = _rtpWithH264(seq: 210, ts: 6000, h264Bytes: [_nalHdr(5)]);
      r = rw.rewrite(rid: 'q', isRtx: false, rtp: kf2);
      expect(r.dropped, isFalse);
      expect(rw.switchInFlight, isFalse);
    });

    test('FU-A start of IDR opens the gate; non-start fragments do not', () {
      final rw = SimulcastRewriter(
        rewrittenPrimarySsrc: 0xAAAA,
        rewrittenRtxSsrc: null,
        currentLayer: 'h',
        pool: BytePool(),
        isKeyframe: isH264Keyframe,
      );

      // Establish baseline with an IDR on 'h'.
      rw.rewrite(
        rid: 'h',
        isRtx: false,
        rtp: _rtpWithH264(seq: 1, ts: 0, h264Bytes: [_nalHdr(5)]),
      );

      rw.setCurrentLayer('q');

      // Middle FU-A fragment of an IDR — gate stays closed.
      final mid =
          _rtpWithH264(seq: 10, ts: 1000, h264Bytes: [0x7c, 0x05, 0xaa]);
      var r = rw.rewrite(rid: 'q', isRtx: false, rtp: mid);
      expect(r.dropped, isTrue);

      // Start FU-A fragment of an IDR — gate opens.
      final start =
          _rtpWithH264(seq: 11, ts: 2000, h264Bytes: [0x7c, 0x85, 0xaa]);
      r = rw.rewrite(rid: 'q', isRtx: false, rtp: start);
      expect(r.dropped, isFalse);
      expect(rw.switchInFlight, isFalse);
    });
  });
}
