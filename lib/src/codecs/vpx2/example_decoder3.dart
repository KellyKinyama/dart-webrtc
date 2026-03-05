import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

import 'vpx_bindings.dart';
import 'dart_ivf.dart'; // Using the library you built

const int VPX_CODEC_OK = 0;

void main() async {
  final inputFile = File('output3.ivf');
  final outputFile = File('decoded3.yuv');

  if (!inputFile.existsSync()) {
    print('Error: IVF file not found');
    return;
  }

  // ------------------------------------------------------------
  // 1. USE YOUR IVFReader LIBRARY
  // ------------------------------------------------------------
  final bytes = await inputFile.readAsBytes();
  final reader = IVFReader(bytes);

  print("Codec: ${reader.header.codec}");
  print("Resolution: ${reader.header.width}x${reader.header.height}");
  print("Timebase: ${reader.header.timebaseDen}/${reader.header.timebaseNum}");

  // ------------------------------------------------------------
  // 2. FFI INITIALIZATION
  // ------------------------------------------------------------
  final vpxLib = ffi.DynamicLibrary.open('C:/msys64/mingw64/bin/libvpx-1.dll');
  final lib = NativeLibrary(vpxLib);

  final ctx = calloc<vpx_codec_ctx_t>();
  ffi.Pointer<vpx_codec_iface_t> iface;

  // Handle codec selection based on IVF header
  if (reader.header.codec == "VP80") {
    iface = lib.vpx_codec_vp8_dx();
  } else if (reader.header.codec == "VP90") {
    iface = lib.vpx_codec_vp9_dx();
  } else {
    throw Exception("Unsupported codec: ${reader.header.codec}");
  }

  // ABI Version 9 for libvpx 1.14
  final res = lib.vpx_codec_dec_init_ver(ctx, iface, ffi.nullptr, 0, 12);

  if (res.value != VPX_CODEC_OK) {
    throw Exception("Decoder init failed: ${res.value}");
  }

  print("Decoder initialized.");

  final sink = outputFile.openWrite();
  final iter = calloc<vpx_codec_iter_t>();

  // ------------------------------------------------------------
  // 3. DECODE LOOP USING IVFReader.frames()
  // ------------------------------------------------------------
  int frameCount = 0;

  for (final ivfFrame in reader.frames()) {
    // Allocate native memory for the compressed frame
    final buf = malloc.allocate<ffi.Uint8>(ivfFrame.size);
    buf.asTypedList(ivfFrame.size).setAll(0, ivfFrame.data);

    final decodeRes = lib.vpx_codec_decode(
      ctx,
      buf,
      ivfFrame.size,
      ffi.nullptr,
      0,
    );

    malloc.free(buf);

    if (decodeRes.value != VPX_CODEC_OK) {
      print("Decode error on frame $frameCount: ${decodeRes.value}");
      continue;
    }

    // Pull decoded YUV frames from the decoder
    ffi.Pointer<vpx_image_t> img;
    iter.value = ffi.nullptr;

    while ((img = lib.vpx_codec_get_frame(ctx, iter)) != ffi.nullptr) {
      _writeI420Frame(img, reader.header.width, reader.header.height, sink);
      frameCount++;
      if (frameCount % 10 == 0) stdout.write("\rDecoded $frameCount frames");
    }
  }

  // ------------------------------------------------------------
  // 4. CLEANUP
  // ------------------------------------------------------------
  malloc.free(iter);
  lib.vpx_codec_destroy(ctx);
  malloc.free(ctx);

  await sink.close();

  print("\nDecoding finished. Total: $frameCount frames.");
  print("Output written to decoded.yuv");
}

/// Correctly writes YUV420 Planes to disk, handling striding
void _writeI420Frame(
  ffi.Pointer<vpx_image_t> imgPtr,
  int width,
  int height,
  IOSink sink,
) {
  final img = imgPtr.ref;

  // I420 format: Y plane followed by U then V
  for (int plane = 0; plane < 3; plane++) {
    final planePtr = img.planes[plane].cast<ffi.Uint8>();
    final stride = img.stride[plane];

    // U and V planes are half-width and half-height
    final planeWidth = (plane == 0) ? width : width ~/ 2;
    final planeHeight = (plane == 0) ? height : height ~/ 2;

    final planeData = planePtr.asTypedList(stride * planeHeight);

    for (int row = 0; row < planeHeight; row++) {
      // We only want the actual pixel data, not the stride padding
      final start = row * stride;
      final end = start + planeWidth;
      sink.add(planeData.sublist(start, end));
    }
  }
}
