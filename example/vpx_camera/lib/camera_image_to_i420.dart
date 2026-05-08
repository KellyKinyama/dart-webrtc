// Convert a Flutter `camera` plugin [CameraImage] into an [I420Frame] for the
// VP8/VP9 encoder. Two camera image formats are supported:
//
//   - YUV420 (Android default): 3 planes (Y, U, V) with optional row stride
//     and pixel-stride padding (e.g. interleaved NV21-like layout). We
//     repack into tight 4:2:0 planar.
//   - BGRA8888 (iOS, macOS, Windows DirectShow): one packed plane. We
//     convert to I420 with BT.601 limited-range coefficients.
//
// The output [I420Frame] always uses tight strides (no padding), which is
// what `VpxEncoder.encode` expects.

import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:pure_dart_webrtc/vpx.dart';

class CameraImageConverter {
  /// Convert any supported [CameraImage] to a tight I420 frame.
  static I420Frame convert(CameraImage image) {
    switch (image.format.group) {
      case ImageFormatGroup.yuv420:
        return _fromYuv420(image);
      case ImageFormatGroup.bgra8888:
        return _fromBgra8888(image);
      default:
        throw UnsupportedError(
            'Unsupported camera image format: ${image.format.group}');
    }
  }

  static I420Frame _fromYuv420(CameraImage img) {
    // Make dimensions even; libvpx 4:2:0 expects this for unambiguous
    // chroma sampling. We simply crop one row/column if needed.
    final w = img.width & ~1;
    final h = img.height & ~1;
    final cw = w >> 1;
    final ch = h >> 1;

    final out = I420Frame.allocate(w, h);

    // --- Y plane ---
    final yPlane = img.planes[0];
    final ySrc = yPlane.bytes;
    final yStride = yPlane.bytesPerRow;
    for (var row = 0; row < h; row++) {
      out.y.setRange(row * w, row * w + w, ySrc, row * yStride);
    }

    // --- U / V planes ---
    // On Android the chroma planes can be interleaved (NV21/NV12 style),
    // exposed by `bytesPerPixel == 2`. We handle both layouts.
    final uPlane = img.planes[1];
    final vPlane = img.planes[2];
    final uSrc = uPlane.bytes;
    final vSrc = vPlane.bytes;
    final uStride = uPlane.bytesPerRow;
    final vStride = vPlane.bytesPerRow;
    final uPx = uPlane.bytesPerPixel ?? 1;
    final vPx = vPlane.bytesPerPixel ?? 1;

    for (var row = 0; row < ch; row++) {
      final uRow = row * uStride;
      final vRow = row * vStride;
      final dstRow = row * cw;
      for (var col = 0; col < cw; col++) {
        out.u[dstRow + col] = uSrc[uRow + col * uPx];
        out.v[dstRow + col] = vSrc[vRow + col * vPx];
      }
    }
    return out;
  }

  static I420Frame _fromBgra8888(CameraImage img) {
    final w = img.width & ~1;
    final h = img.height & ~1;
    final cw = w >> 1;
    final stride = img.planes[0].bytesPerRow;
    final src = img.planes[0].bytes;

    final out = I420Frame.allocate(w, h);

    // BT.601 limited-range coefficients, matching `I420Frame.fromRgb24`.
    for (var y = 0; y < h; y += 2) {
      for (var x = 0; x < w; x += 2) {
        final i00 = y * stride + x * 4;
        final i01 = i00 + 4;
        final i10 = i00 + stride;
        final i11 = i10 + 4;

        final b0 = src[i00], g0 = src[i00 + 1], r0 = src[i00 + 2];
        final b1 = src[i01], g1 = src[i01 + 1], r1 = src[i01 + 2];
        final b2 = src[i10], g2 = src[i10 + 1], r2 = src[i10 + 2];
        final b3 = src[i11], g3 = src[i11 + 1], r3 = src[i11 + 2];

        out.y[y * w + x] = _y(r0, g0, b0);
        out.y[y * w + x + 1] = _y(r1, g1, b1);
        out.y[(y + 1) * w + x] = _y(r2, g2, b2);
        out.y[(y + 1) * w + x + 1] = _y(r3, g3, b3);

        final r = (r0 + r1 + r2 + r3) >> 2;
        final g = (g0 + g1 + g2 + g3) >> 2;
        final b = (b0 + b1 + b2 + b3) >> 2;
        final ci = (y >> 1) * cw + (x >> 1);
        out.u[ci] = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
        out.v[ci] = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
      }
    }
    return out;
  }

  static int _y(int r, int g, int b) =>
      ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
}

/// Convert an [I420Frame] to packed BGRA8888 for display via `dart:ui`'s
/// `ImmutableBuffer.fromUint8List` + `ImageDescriptor.raw` path.
Uint8List i420ToBgra8888(I420Frame f) {
  final w = f.width;
  final h = f.height;
  final cw = (w + 1) >> 1;
  final out = Uint8List(w * h * 4);

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final yV = f.y[y * w + x] - 16;
      final uV = f.u[(y >> 1) * cw + (x >> 1)] - 128;
      final vV = f.v[(y >> 1) * cw + (x >> 1)] - 128;

      final c = 298 * yV;
      final r = (c + 409 * vV + 128) >> 8;
      final g = (c - 100 * uV - 208 * vV + 128) >> 8;
      final b = (c + 516 * uV + 128) >> 8;

      final o = (y * w + x) * 4;
      out[o] = _clip(b);
      out[o + 1] = _clip(g);
      out[o + 2] = _clip(r);
      out[o + 3] = 255;
    }
  }
  return out;
}

int _clip(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);
