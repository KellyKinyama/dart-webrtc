// I420 (YUV 4:2:0 planar) frame produced by [VpxDecoder] and consumed by
// [VpxEncoder]. The three planes are owned by the caller (plain [Uint8List]).
//
// Layout per plane (row-major, no row padding):
//   Y: [width    * height   ] bytes
//   U: [width/2  * height/2 ] bytes (chroma uses ceil-div for odd sizes)
//   V: [width/2  * height/2 ] bytes

import 'dart:typed_data';

class I420Frame {
  final int width;
  final int height;
  final Uint8List y;
  final Uint8List u;
  final Uint8List v;

  const I420Frame({
    required this.width,
    required this.height,
    required this.y,
    required this.u,
    required this.v,
  });

  /// Allocate a tightly-packed I420 frame with zeroed planes.
  factory I420Frame.allocate(int width, int height) {
    final cw = (width + 1) >> 1;
    final ch = (height + 1) >> 1;
    return I420Frame(
      width: width,
      height: height,
      y: Uint8List(width * height),
      u: Uint8List(cw * ch),
      v: Uint8List(cw * ch),
    );
  }

  /// Concatenated Y, U, V planes — the format used by raw `.yuv` files and
  /// `ffplay -pixel_format yuv420p`.
  Uint8List toBytes() {
    final out = Uint8List(y.length + u.length + v.length);
    out.setRange(0, y.length, y);
    out.setRange(y.length, y.length + u.length, u);
    out.setRange(y.length + u.length, out.length, v);
    return out;
  }

  /// Convert a packed RGB24 buffer (R,G,B,R,G,B,...) of size width*height*3
  /// into a freshly allocated [I420Frame] using BT.601 limited-range
  /// coefficients.
  static I420Frame fromRgb24(Uint8List rgb, int width, int height) {
    if (rgb.length < width * height * 3) {
      throw ArgumentError('RGB24 buffer too small for ${width}x$height');
    }
    final f = I420Frame.allocate(width, height);
    final cw = (width + 1) >> 1;
    for (var yy = 0; yy < height; yy += 2) {
      for (var xx = 0; xx < width; xx += 2) {
        final x1 = xx + 1 < width ? xx + 1 : xx;
        final y1 = yy + 1 < height ? yy + 1 : yy;
        final i00 = (yy * width + xx) * 3;
        final i01 = (yy * width + x1) * 3;
        final i10 = (y1 * width + xx) * 3;
        final i11 = (y1 * width + x1) * 3;

        f.y[yy * width + xx] = _rgbToY(rgb, i00);
        f.y[yy * width + x1] = _rgbToY(rgb, i01);
        f.y[y1 * width + xx] = _rgbToY(rgb, i10);
        f.y[y1 * width + x1] = _rgbToY(rgb, i11);

        final r = (rgb[i00] + rgb[i01] + rgb[i10] + rgb[i11]) >> 2;
        final g =
            (rgb[i00 + 1] + rgb[i01 + 1] + rgb[i10 + 1] + rgb[i11 + 1]) >> 2;
        final b =
            (rgb[i00 + 2] + rgb[i01 + 2] + rgb[i10 + 2] + rgb[i11 + 2]) >> 2;
        final ci = (yy >> 1) * cw + (xx >> 1);
        f.u[ci] = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
        f.v[ci] = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
      }
    }
    return f;
  }

  static int _rgbToY(Uint8List rgb, int i) =>
      ((66 * rgb[i] + 129 * rgb[i + 1] + 25 * rgb[i + 2] + 128) >> 8) + 16;
}
