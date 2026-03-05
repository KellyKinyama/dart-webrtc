import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img_pkg;

import 'vpx_bindings.dart';
import 'dart_ivf.dart';

const int VPX_CODEC_OK = 0;

void main() async {
  final inputFile = File('output3.ivf');
  final outputFile = File('decoded3.yuv');

  if (!inputFile.existsSync()) {
    print('Error: IVF file not found');
    return;
  }

  // 1. Load IVF via Reader
  final bytes = await inputFile.readAsBytes();
  final reader = IVFReader(bytes);

  print("Codec: ${reader.header.codec}");
  print("Resolution: ${reader.header.width}x${reader.header.height}");

  // 2. Load libvpx
  final vpxLib = ffi.DynamicLibrary.open('C:/msys64/mingw64/bin/libvpx-1.dll');
  final lib = NativeLibrary(vpxLib);

  final ctx = calloc<vpx_codec_ctx_t>();
  ffi.Pointer<vpx_codec_iface_t> iface = (reader.header.codec == "VP80")
      ? lib.vpx_codec_vp8_dx()
      : lib.vpx_codec_vp9_dx();

  // ABI 12 for Decoder
  final res = lib.vpx_codec_dec_init_ver(ctx, iface, ffi.nullptr, 0, 12);
  if (res.value != VPX_CODEC_OK) throw Exception("Decoder init failed");

  print("Decoder initialized.");

  final sink = outputFile.openWrite();
  final iter = calloc<vpx_codec_iter_t>();
  int frameCount = 0;

  // 3. Decode Loop
  for (final ivfFrame in reader.frames()) {
    final buf = malloc.allocate<ffi.Uint8>(ivfFrame.size);
    buf.asTypedList(ivfFrame.size).setAll(0, ivfFrame.data);

    final decodeRes =
        lib.vpx_codec_decode(ctx, buf, ivfFrame.size, ffi.nullptr, 0);
    malloc.free(buf);

    if (decodeRes.value != VPX_CODEC_OK) continue;

    ffi.Pointer<vpx_image_t> img;
    iter.value = ffi.nullptr;

    while ((img = lib.vpx_codec_get_frame(ctx, iter)) != ffi.nullptr) {
      final vpxImg = img.ref;

      // --- NEW: Convert to Image and save the first frame ---
      if (frameCount == 0) {
        print("\nConverting first frame to PNG...");
        final convertedImage = yuv420ToImage(
          vpxImg.planes[0]
              .cast<ffi.Uint8>()
              .asTypedList(vpxImg.stride[0] * reader.header.height),
          vpxImg.planes[1]
              .cast<ffi.Uint8>()
              .asTypedList(vpxImg.stride[1] * (reader.header.height ~/ 2)),
          vpxImg.planes[2]
              .cast<ffi.Uint8>()
              .asTypedList(vpxImg.stride[2] * (reader.header.height ~/ 2)),
          reader.header.width,
          reader.header.height,
          vpxImg.stride[0],
          vpxImg.stride[1],
        );

        File('first_frame_decoded.png')
            .writeAsBytesSync(img_pkg.encodePng(convertedImage));
        print("First frame saved to first_frame_decoded.png");
      }

      _writeI420Frame(img, reader.header.width, reader.header.height, sink);
      frameCount++;
      if (frameCount % 10 == 0) stdout.write("\rDecoded $frameCount frames");
    }
  }

  // Cleanup
  malloc.free(iter);
  lib.vpx_codec_destroy(ctx);
  malloc.free(ctx);
  await sink.close();

  print("\nFinished! Decoded $frameCount frames.");
}

/// Helper: YUV420 to RGB using ITU-R BT.601
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
      final int yp = yPlane[y * yStride + x];
      final int uvIndex = (y ~/ 2) * uvStride + (x ~/ 2);
      final int up = uPlane[uvIndex] - 128;
      final int vp = vPlane[uvIndex] - 128;

      // Conversion
      int r = (yp + 1.370705 * vp).round().clamp(0, 255);
      int g = (yp - 0.337633 * up - 0.698001 * vp).round().clamp(0, 255);
      int b = (yp + 1.732446 * up).round().clamp(0, 255);

      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}

void _writeI420Frame(
    ffi.Pointer<vpx_image_t> imgPtr, int width, int height, IOSink sink) {
  final img = imgPtr.ref;
  for (int plane = 0; plane < 3; plane++) {
    final planePtr = img.planes[plane].cast<ffi.Uint8>();
    final stride = img.stride[plane];
    final pW = (plane == 0) ? width : width ~/ 2;
    final pH = (plane == 0) ? height : height ~/ 2;
    final data = planePtr.asTypedList(stride * pH);

    for (int row = 0; row < pH; row++) {
      sink.add(data.sublist(row * stride, row * stride + pW));
    }
  }
}
