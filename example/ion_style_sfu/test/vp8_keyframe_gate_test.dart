// VP8 payload-descriptor parser, keyframe detection, and the
// reSync keyframe gate on SimulcastRewriter.

import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/src/byte_pool.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/src/simulcast_rewriter.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/src/vp8.dart';
import 'package:test/test.dart';

/// Build an RTP packet with a VP8 payload starting with [vp8Bytes].
Uint8List _rtpWithVp8({
  required int seq,
  required int ts,
  required List<int> vp8Bytes,
  int ssrc = 0xCAFE,
  int pt = 96,
}) {
  final out = Uint8List(12 + vp8Bytes.length);
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
  out.setRange(12, 12 + vp8Bytes.length, vp8Bytes);
  return out;
}

void main() {
  group('parseVp8Descriptor', () {
    test('decodes the minimal one-byte form (no extension)', () {
      // S=1, PID=0 → byte0 = 0x10
      final d = parseVp8Descriptor(Uint8List.fromList([0x10, 0xff, 0xff]), 0);
      expect(d, isNotNull);
      expect(d!.headerLength, 1);
      expect(d.startOfPartition, isTrue);
      expect(d.partitionIndex, 0);
      expect(d.hasExtension, isFalse);
      expect(d.pictureId, isNull);
      expect(d.tl0PicIdx, isNull);
    });

    test('decodes I=1 short PictureID (7-bit, M=0)', () {
      // X=1 (0x80) | S=1 (0x10) = 0x90; ext I=1 (0x80); pic = 0x42 (M=0).
      final d = parseVp8Descriptor(
          Uint8List.fromList([0x90, 0x80, 0x42, 0xee]), 0);
      expect(d, isNotNull);
      expect(d!.hasExtension, isTrue);
      expect(d.pictureId, 0x42);
      expect(d.pictureIdIsLong, isFalse);
      expect(d.headerLength, 3);
    });

    test('decodes I=1 long PictureID (15-bit, M=1)', () {
      // pic = 0x80 0x42 → M=1, val = 0x0042
      final d = parseVp8Descriptor(
          Uint8List.fromList([0x90, 0x80, 0x80, 0x42, 0xee]), 0);
      expect(d!.pictureId, 0x0042);
      expect(d.pictureIdIsLong, isTrue);
      expect(d.headerLength, 4);
    });

    test('decodes I=1 + L=1 (PictureID + TL0PICIDX)', () {
      // ext I|L = 0xc0; pic = 0x10 (short); tl0 = 0x55
      final d = parseVp8Descriptor(
          Uint8List.fromList([0x90, 0xc0, 0x10, 0x55, 0xee]), 0);
      expect(d!.pictureId, 0x10);
      expect(d.tl0PicIdx, 0x55);
      expect(d.headerLength, 4);
    });
  });

  group('isVp8Keyframe', () {
    test('true for S=1, PID=0, frame[0] P-bit=0', () {
      final pkt = _rtpWithVp8(seq: 1, ts: 0, vp8Bytes: [0x10, 0x00, 0x9d, 0x01]);
      expect(isVp8Keyframe(pkt), isTrue);
    });

    test('false for S=1, PID=0, frame[0] P-bit=1 (delta frame)', () {
      final pkt = _rtpWithVp8(seq: 1, ts: 0, vp8Bytes: [0x10, 0x01, 0x00]);
      expect(isVp8Keyframe(pkt), isFalse);
    });

    test('false when not start-of-partition', () {
      // S=0, PID=0 → byte0=0x00; even with frame[0]=0x00 it's not a keyframe.
      final pkt = _rtpWithVp8(seq: 1, ts: 0, vp8Bytes: [0x00, 0x00]);
      expect(isVp8Keyframe(pkt), isFalse);
    });

    test('false for partition index != 0', () {
      // S=1 PID=2 → byte0 = 0x12
      final pkt = _rtpWithVp8(seq: 1, ts: 0, vp8Bytes: [0x12, 0x00]);
      expect(isVp8Keyframe(pkt), isFalse);
    });
  });

  group('SimulcastRewriter reSync keyframe gate', () {
    test('drops delta frames after a layer switch until a keyframe arrives',
        () {
      final rw = SimulcastRewriter(
        rewrittenPrimarySsrc: 0xAAAA,
        rewrittenRtxSsrc: null,
        currentLayer: 'h',
        pool: BytePool(),
        isKeyframe: isVp8Keyframe,
      );

      // Initial keyframe on 'h' establishes the baseline.
      final kf1 = _rtpWithVp8(seq: 100, ts: 1000, vp8Bytes: [0x10, 0x00]);
      var r = rw.rewrite(rid: 'h', isRtx: false, rtp: kf1);
      expect(r.dropped, isFalse, reason: 'first keyframe must establish offset');

      // A few delta frames pass through normally.
      final delta = _rtpWithVp8(seq: 101, ts: 1100, vp8Bytes: [0x10, 0x01]);
      r = rw.rewrite(rid: 'h', isRtx: false, rtp: delta);
      expect(r.dropped, isFalse);

      // Switch to 'q'. Until a keyframe arrives, every delta on 'q'
      // must be dropped by the gate.
      rw.setCurrentLayer('q');
      for (var i = 0; i < 3; i++) {
        final pkt = _rtpWithVp8(
            seq: 200 + i, ts: 5000 + i * 100, vp8Bytes: [0x10, 0x01]);
        r = rw.rewrite(rid: 'q', isRtx: false, rtp: pkt);
        expect(r.dropped, isTrue,
            reason: 'delta frame #$i on new layer must be gated');
      }
      expect(rw.gateDropped, 3);
      expect(rw.switchInFlight, isTrue);

      // Now a keyframe lands on 'q' — offset is established and the
      // packet is forwarded.
      final kf2 = _rtpWithVp8(seq: 210, ts: 6000, vp8Bytes: [0x10, 0x00]);
      r = rw.rewrite(rid: 'q', isRtx: false, rtp: kf2);
      expect(r.dropped, isFalse);
      expect(rw.switchInFlight, isFalse);
    });

    test('without a detector, behavior is unchanged (offset on first primary)',
        () {
      final rw = SimulcastRewriter(
        rewrittenPrimarySsrc: 0xAAAA,
        rewrittenRtxSsrc: null,
        currentLayer: 'h',
        pool: BytePool(),
        // isKeyframe omitted intentionally.
      );
      final delta = _rtpWithVp8(seq: 1, ts: 0, vp8Bytes: [0x10, 0x01]);
      final r = rw.rewrite(rid: 'h', isRtx: false, rtp: delta);
      expect(r.dropped, isFalse);
      expect(rw.gateDropped, 0);
    });
  });

  group('Vp8PicIdRewriter', () {
    test('passes PictureID through unchanged on the first layer', () {
      final pr = Vp8PicIdRewriter();
      final pkt = Uint8List.fromList(<int>[
        // RTP header (12B), no CSRC/X.
        0x80, 96, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1,
        // VP8 desc: X=1 S=1 (0x90), ext I=1 L=1 (0xc0), pic=0x10, tl0=0x05
        0x90, 0xc0, 0x10, 0x05,
      ]);
      final ok = pr.rewrite(rid: 'h', rtp: pkt, isKeyframe: true);
      expect(ok, isTrue);
      expect(pkt[14], 0x10); // unchanged
      expect(pkt[15], 0x05);
      expect(pr.lastOutPicId, 0x10);
      expect(pr.lastOutTl0, 0x05);
    });

    test('after layer switch, new keyframe re-bases to lastOut+1', () {
      final pr = Vp8PicIdRewriter();
      final p1 = Uint8List.fromList(<int>[
        0x80, 96, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, //
        0x90, 0xc0, 0x10, 0x05,
      ]);
      pr.rewrite(rid: 'h', rtp: p1, isKeyframe: true);

      pr.onLayerSwitch('q');

      // Layer 'q' has a different PictureID space.
      final p2 = Uint8List.fromList(<int>[
        0x80, 96, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, //
        0x90, 0xc0, 0x70, 0x40,
      ]);
      final ok = pr.rewrite(rid: 'q', rtp: p2, isKeyframe: true);
      expect(ok, isTrue);
      // 0x10 + 1 = 0x11 → must rewrite outbound to 0x11 (short form).
      expect(p2[14], 0x11);
      // 0x05 + 1 = 0x06.
      expect(p2[15], 0x06);
    });

    test('drops delta frames on new layer until keyframe re-bases', () {
      final pr = Vp8PicIdRewriter();
      // Establish 'h' first.
      final kf = Uint8List.fromList(<int>[
        0x80, 96, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, //
        0x90, 0xc0, 0x10, 0x05,
      ]);
      pr.rewrite(rid: 'h', rtp: kf, isKeyframe: true);

      pr.onLayerSwitch('q');

      final delta = Uint8List.fromList(<int>[
        0x80, 96, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, //
        0x90, 0xc0, 0x77, 0x42,
      ]);
      final ok = pr.rewrite(rid: 'q', rtp: delta, isKeyframe: false);
      expect(ok, isFalse);
    });
  });
}
