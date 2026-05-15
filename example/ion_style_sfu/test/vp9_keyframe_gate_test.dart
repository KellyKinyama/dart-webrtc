// VP9 keyframe detection + reSync gate on SimulcastRewriter.

import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/src/byte_pool.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/src/simulcast_rewriter.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/src/vp9.dart';
import 'package:test/test.dart';

/// Build an RTP packet with a VP9 payload starting with [vp9Bytes].
Uint8List _rtpWithVp9({
  required int seq,
  required int ts,
  required List<int> vp9Bytes,
  int ssrc = 0xCAFE,
  int pt = 98,
}) {
  final out = Uint8List(12 + vp9Bytes.length);
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
  out.setRange(12, 12 + vp9Bytes.length, vp9Bytes);
  return out;
}

void main() {
  group('isVp9Keyframe', () {
    test('true for B=1, P=0, no I, no L (minimal keyframe descriptor)', () {
      // descriptor byte0: B=1 (0x08) → 0x08
      final pkt = _rtpWithVp9(seq: 1, ts: 0, vp9Bytes: [0x08, 0xaa]);
      expect(isVp9Keyframe(pkt), isTrue);
    });

    test('false when P=1 (inter-predicted)', () {
      // B=1 | P=1 → 0x48
      final pkt = _rtpWithVp9(seq: 1, ts: 0, vp9Bytes: [0x48, 0xaa]);
      expect(isVp9Keyframe(pkt), isFalse);
    });

    test('false when B=0 (not start-of-frame)', () {
      // P=0, B=0 → 0x00
      final pkt = _rtpWithVp9(seq: 1, ts: 0, vp9Bytes: [0x00, 0xaa]);
      expect(isVp9Keyframe(pkt), isFalse);
    });

    test('true with I=1 short PictureID and L=1, base spatial layer (SID=0)',
        () {
      // byte0: I|L|B → 0x80|0x20|0x08 = 0xa8
      // PictureID short (M=0): 0x42
      // L byte: TID=0,U=0,SID=0,D=0 → 0x00
      final pkt =
          _rtpWithVp9(seq: 1, ts: 0, vp9Bytes: [0xa8, 0x42, 0x00, 0xaa]);
      expect(isVp9Keyframe(pkt), isTrue);
    });

    test('false with L=1 enhancement spatial layer (SID=1)', () {
      // L byte: SID=1 → 0x02
      final pkt =
          _rtpWithVp9(seq: 1, ts: 0, vp9Bytes: [0xa8, 0x42, 0x02, 0xaa]);
      expect(isVp9Keyframe(pkt), isFalse);
    });

    test('true with I=1 long PictureID (M=1) and base SID', () {
      // byte0: I|L|B → 0xa8
      // PictureID long: M=1,val=0x0042 → bytes 0x80, 0x42
      // L byte: SID=0 → 0x00
      final pkt =
          _rtpWithVp9(seq: 1, ts: 0, vp9Bytes: [0xa8, 0x80, 0x42, 0x00, 0xaa]);
      expect(isVp9Keyframe(pkt), isTrue);
    });

    test('false on empty payload', () {
      final pkt = _rtpWithVp9(seq: 1, ts: 0, vp9Bytes: const []);
      expect(isVp9Keyframe(pkt), isFalse);
    });

    test('false on truncated L extension', () {
      // I|L|B set but no following bytes for PictureID/L.
      final pkt = _rtpWithVp9(seq: 1, ts: 0, vp9Bytes: [0xa8]);
      expect(isVp9Keyframe(pkt), isFalse);
    });
  });

  group('SimulcastRewriter reSync gate — VP9', () {
    test('drops VP9 delta frames after a layer switch until a keyframe arrives',
        () {
      final rw = SimulcastRewriter(
        rewrittenPrimarySsrc: 0xAAAA,
        rewrittenRtxSsrc: null,
        currentLayer: 'h',
        pool: BytePool(),
        isKeyframe: isVp9Keyframe,
      );

      // Initial keyframe on 'h' establishes the baseline.
      final kf1 = _rtpWithVp9(seq: 100, ts: 1000, vp9Bytes: [0x08, 0xaa]);
      var r = rw.rewrite(rid: 'h', isRtx: false, rtp: kf1);
      expect(r.dropped, isFalse,
          reason: 'first keyframe must establish offset');

      // Delta frame (P=1) passes through normally.
      final delta = _rtpWithVp9(seq: 101, ts: 1100, vp9Bytes: [0x48, 0xaa]);
      r = rw.rewrite(rid: 'h', isRtx: false, rtp: delta);
      expect(r.dropped, isFalse);

      // Switch to 'q' — every delta on 'q' must be dropped until a
      // keyframe arrives.
      rw.setCurrentLayer('q');
      for (var i = 0; i < 3; i++) {
        final pkt = _rtpWithVp9(
            seq: 200 + i, ts: 5000 + i * 100, vp9Bytes: [0x48, 0xaa]);
        r = rw.rewrite(rid: 'q', isRtx: false, rtp: pkt);
        expect(r.dropped, isTrue,
            reason: 'delta frame #$i on new layer must be gated');
      }
      expect(rw.gateDropped, 3);
      expect(rw.switchInFlight, isTrue);

      // Now a keyframe lands on 'q' — gate opens.
      final kf2 = _rtpWithVp9(seq: 210, ts: 6000, vp9Bytes: [0x08, 0xaa]);
      r = rw.rewrite(rid: 'q', isRtx: false, rtp: kf2);
      expect(r.dropped, isFalse);
      expect(rw.switchInFlight, isFalse);
    });
  });
}
