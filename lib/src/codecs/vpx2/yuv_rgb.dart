import 'dart:typed_data';

import 'package:image/image.dart' as img_pkg;

img_pkg.Image yuv420ToImage(
  Uint8List yPlane,
  Uint8List uPlane,
  Uint8List vPlane,
  int width,
  int height,
  int yStride,
  int uvStride,
) {
  final image = img_pkg.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      // Y plane is full resolution
      final int yIndex = y * yStride + x;
      final int yp = yPlane[yIndex];

      // U/V planes are half resolution (subsampled)
      final int uvIndex = (y ~/ 2) * uvStride + (x ~/ 2);
      final int up = uPlane[uvIndex] - 128;
      final int vp = vPlane[uvIndex] - 128;

      // YUV to RGB conversion formula
      int r = (yp + 1.370705 * vp).round().clamp(0, 255);
      int g = (yp - 0.337633 * up - 0.698001 * vp).round().clamp(0, 255);
      int b = (yp + 1.732446 * up).round().clamp(0, 255);

      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}
