// Snapshot recorder: keeps the latest decoded video frame for every
// producer, exposed as JPEG via `GET /snapshot/<participantId>.jpg` on
// the SFU's HTTP server.
//
// Subscribe with:
//
//   final snap = SnapshotRecorder();
//   sfu.onVideoRtp = (producerId, ssrc, rtp) =>
//       snap.acceptRtp(producerId, ssrc, rtp);
//
// The recorder reassembles RFC 7741 VP8 frames out of inbound RTP, only
// fully decodes keyframes (P-frames are dropped to keep the cost
// bounded), and lazily JPEG-encodes on demand. Per-producer state is
// reaped via [forget] when the participant leaves.

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pure_dart_webrtc/vpx.dart';

class SnapshotRecorder {
  /// One reassembly buffer per (producerId, ssrc).
  final Map<String, _Reassembler> _buffers = {};

  /// One VP8 decoder per producer (keeps reference frames hot).
  final Map<String, VpxDecoder> _decoders = {};

  /// Latest decoded I420 frame per producer.
  final Map<String, I420Frame> _latest = {};

  /// Cached JPEG bytes per producer; invalidated whenever a fresher
  /// I420 frame arrives.
  final Map<String, Uint8List> _jpegCache = {};

  /// Feed one inbound RTP packet (already-decrypted, header + payload).
  /// Safe to call from a hot path — assembly is O(n) over the payload
  /// only and decode is skipped for non-keyframes.
  void acceptRtp(String producerId, int primarySsrc, Uint8List rtp) {
    if (rtp.length < 12) return;
    final key = '$producerId#$primarySsrc';
    final asm = _buffers.putIfAbsent(key, () => _Reassembler());
    final completed = asm.feed(rtp);
    if (completed == null) return;

    // RFC 7741 §4.1: first byte of the VP8 *bitstream* (right after the
    // payload descriptor) has bit 0 == 0 for keyframes (inverse logic).
    final isKeyframe = completed.isNotEmpty && (completed[0] & 0x01) == 0;
    if (!isKeyframe) return;

    final dec = _decoders.putIfAbsent(
      producerId,
      () => VpxDecoder(codec: VpxCodec.vp8),
    );
    try {
      final frames = dec.decode(completed);
      for (final f in frames) {
        _latest[producerId] = f;
        _jpegCache.remove(producerId);
      }
    } catch (_) {
      // Corrupt frame — drop and wait for the next keyframe.
    }
  }

  /// JPEG-encode the most recent decoded frame for [producerId], or null
  /// if no keyframe has been received yet.
  Uint8List? snapshotJpeg(String producerId, {int quality = 80}) {
    final cached = _jpegCache[producerId];
    if (cached != null) return cached;
    final frame = _latest[producerId];
    if (frame == null) return null;

    final rgba = _i420ToRgba(frame);
    final image = img.Image.fromBytes(
      width: frame.width,
      height: frame.height,
      bytes: rgba.buffer,
      numChannels: 4,
    );
    final jpg = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    _jpegCache[producerId] = jpg;
    return jpg;
  }

  /// Forget all per-producer state. Call when a participant leaves so
  /// the decoder context and reassembly buffers are released.
  void forget(String producerId) {
    _buffers.removeWhere((k, _) => k.startsWith('$producerId#'));
    _decoders.remove(producerId)?.dispose();
    _latest.remove(producerId);
    _jpegCache.remove(producerId);
  }

  /// Release all decoders. Call before process exit.
  void dispose() {
    for (final d in _decoders.values) {
      d.dispose();
    }
    _decoders.clear();
    _buffers.clear();
    _latest.clear();
    _jpegCache.clear();
  }
}

// --- VP8 RTP reassembly ----------------------------------------------

/// Collects the VP8 payloads of one frame, keyed by RTP timestamp. Emits
/// the concatenated compressed bitstream when the marker bit is seen.
/// Out-of-order timestamps reset the buffer.
class _Reassembler {
  int? _ts;
  final BytesBuilder _buf = BytesBuilder(copy: false);

  Uint8List? feed(Uint8List rtp) {
    final bd = ByteData.sublistView(rtp);
    final marker = (rtp[1] & 0x80) != 0;
    final ts = bd.getUint32(4, Endian.big);
    final cc = rtp[0] & 0x0F;
    final hasExt = (rtp[0] & 0x10) != 0;

    var off = 12 + cc * 4;
    if (hasExt) {
      if (off + 4 > rtp.length) return null;
      final extLen = bd.getUint16(off + 2, Endian.big) * 4;
      off += 4 + extLen;
    }
    if (off >= rtp.length) return null;

    // VP8 payload descriptor (RFC 7741 §4.2). Always at least 1 byte.
    final desc = rtp[off++];
    final hasX = (desc & 0x80) != 0;
    if (hasX) {
      // Optional X byte signals which extra fields follow (I, L, T/K).
      if (off >= rtp.length) return null;
      final x = rtp[off++];
      // I = PictureID present (1 or 2 bytes).
      if ((x & 0x80) != 0) {
        if (off >= rtp.length) return null;
        if ((rtp[off] & 0x80) != 0) {
          off += 2;
        } else {
          off += 1;
        }
      }
      if ((x & 0x40) != 0) off += 1; // L: TL0PICIDX
      if ((x & 0x30) != 0) off += 1; // T or K: TID/KEYIDX
      if (off > rtp.length) return null;
    }

    if (_ts != null && _ts != ts) {
      _buf.clear();
    }
    _ts = ts;
    _buf.add(rtp.sublist(off));

    if (!marker) return null;
    final frame = _buf.toBytes();
    _buf.clear();
    _ts = null;
    return frame;
  }
}

/// Convert an [I420Frame] (BT.601 limited range) to a tightly packed
/// RGBA8 buffer. `image` only takes RGB / RGBA inputs.
Uint8List _i420ToRgba(I420Frame f) {
  final w = f.width;
  final h = f.height;
  final cw = (w + 1) >> 1;
  final out = Uint8List(w * h * 4);
  for (var yy = 0; yy < h; yy++) {
    for (var xx = 0; xx < w; xx++) {
      final yIdx = yy * w + xx;
      final cIdx = (yy >> 1) * cw + (xx >> 1);
      final yv = f.y[yIdx] - 16;
      final uv = f.u[cIdx] - 128;
      final vv = f.v[cIdx] - 128;
      // BT.601 inverse, fixed-point.
      var r = (298 * yv + 409 * vv + 128) >> 8;
      var g = (298 * yv - 100 * uv - 208 * vv + 128) >> 8;
      var b = (298 * yv + 516 * uv + 128) >> 8;
      if (r < 0) {
        r = 0;
      } else if (r > 255) {
        r = 255;
      }
      if (g < 0) {
        g = 0;
      } else if (g > 255) {
        g = 255;
      }
      if (b < 0) {
        b = 0;
      } else if (b > 255) {
        b = 255;
      }
      final o = yIdx * 4;
      out[o] = r;
      out[o + 1] = g;
      out[o + 2] = b;
      out[o + 3] = 255;
    }
  }
  return out;
}
