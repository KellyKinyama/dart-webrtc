import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// Ensure this matches your ffigen output file name
import 'vpx_bindings.dart';
import 'dart_ivf.dart';

// NOTE: Ensure your IVFHeader, IVFFrame, IVFReader, and IVFWriter
// classes are either in this file or imported.

void main(List<String> args) async {
  // --- 1. SETTINGS ---
  const int width = 384;
  const int height = 216;
  const int fps = 25;
  const int bitrate = 1000;

  final inputFile = File('video.rgb24');
  final outputFile = File('output3.ivf');

  if (!inputFile.existsSync()) {
    print('Error: video.rgb24 not found.');
    return;
  }

  // --- 2. FFI INITIALIZATION ---
  final vpxLib = ffi.DynamicLibrary.open('C:/msys64/mingw64/bin/libvpx-1.dll');
  final bindings = NativeLibrary(vpxLib);

  final ctx = calloc<vpx_codec_ctx_t>();
  final cfg = calloc<vpx_codec_enc_cfg_t>();

  final iface = bindings.vpx_codec_vp8_cx();
  if (iface == ffi.nullptr) {
    print('Error: VP8 Encoder interface not found.');
    return;
  }

  bindings.vpx_codec_enc_config_default(iface, cfg, 0);

  cfg.ref.g_w = width;
  cfg.ref.g_h = height;
  cfg.ref.g_timebase.num = 1;
  cfg.ref.g_timebase.den = fps;
  cfg.ref.rc_target_bitrate = bitrate;

  // ABI VERSION 9 for libvpx v1.14
  final initRes = bindings.vpx_codec_enc_init_ver(ctx, iface, cfg, 0, 34);
  if (initRes.value != 0) {
    print('Encoder init failed with error code: $initRes');
    return;
  }

  // --- 3. ALLOCATE NATIVE IMAGE ---
  final ffi.Pointer<vpx_image_t> vpxImg = bindings.vpx_img_alloc(
      ffi.nullptr, vpx_img_fmt.VPX_IMG_FMT_I420, width, height, 1);

  // --- 4. PREPARE STRUCTURED WRITER ---
  // Using your IVFWriter class instead of a raw IOSink
  // final ivfWriter = IVFWriter(width: width, height: height, codec: "VP80");
  final ivfWriter = IVFWriter(
      width: width,
      height: height,
      fps: fps, // Now output3.ivf will correctly show 25/1
      codec: "VP80");

  // --- 5. ENCODE LOOP ---
  final frameSize = width * height * 3;
  final rawData = await inputFile.readAsBytes();
  int frameCount = 0;

  print('Encoding with libvpx 1.14 and IVFWriter...');

  for (int offset = 0;
      offset + frameSize <= rawData.length;
      offset += frameSize) {
    final rgbFrame = Uint8List.view(rawData.buffer, offset, frameSize);

    // Using your specific conversion function
    _optimizedRgbToYuvNative(rgbFrame, vpxImg, width, height);

    final encRes = bindings.vpx_codec_encode(ctx, vpxImg, frameCount, 1, 0, 1);
    if (encRes.value != 0) {
      print('Encoding error: $encRes');
      break;
    }

    // Pull packets into the IVFWriter object
    _pullPacketsIntoWriter(bindings, ctx, ivfWriter);

    frameCount++;
    if (frameCount % 10 == 0) stdout.write("\rEncoded $frameCount frames");
  }

  // Flush remaining frames
  bindings.vpx_codec_encode(ctx, ffi.nullptr, -1, 1, 0, 1);
  _pullPacketsIntoWriter(bindings, ctx, ivfWriter);

  // --- 6. SAVE AND CLEANUP ---
  // build() generates the full IVF file including the correct header
  await outputFile.writeAsBytes(ivfWriter.build());

  bindings.vpx_img_free(vpxImg);
  bindings.vpx_codec_destroy(ctx);
  malloc.free(ctx);
  malloc.free(cfg);

  print('\nFinished! Total frames: $frameCount. Output: ${outputFile.path}');
}

/// Refactored to use IVFWriter instead of IOSink
// void _pullPacketsIntoWriter(
//     NativeLibrary lib, ffi.Pointer<vpx_codec_ctx_t> ctx, IVFWriter writer) {
//   final iter = calloc<vpx_codec_iter_t>();
//   iter.value = ffi.nullptr;
//   ffi.Pointer<vpx_codec_cx_pkt_t> pkt;

//   while ((pkt = lib.vpx_codec_get_cx_data(ctx, iter)) != ffi.nullptr) {
//     // kind == 0 is VPX_CODEC_CX_FRAME_PKT
//     if (pkt.ref.kind == 0) {
//       final frame = pkt.ref.data.frame;

//       // We MUST copy the data because the pointer is temporary
//       final frameData =
//           Uint8List.fromList(frame.buf.cast<ffi.Uint8>().asTypedList(frame.sz));

//       writer.addFrame(frameData, frame.pts);
//     }
//   }
//   malloc.free(iter);
// }

void _pullPacketsIntoWriter(
    NativeLibrary lib, ffi.Pointer<vpx_codec_ctx_t> ctx, IVFWriter writer) {
  final iter = calloc<vpx_codec_iter_t>();
  iter.value = ffi.nullptr;
  ffi.Pointer<vpx_codec_cx_pkt_t> pkt;

  while ((pkt = lib.vpx_codec_get_cx_data(ctx, iter)) != ffi.nullptr) {
    // Some bindings use pkt.ref.kind.value, others use pkt.ref.kind
    // We check for 0 (VPX_CODEC_CX_FRAME_PKT)
    final kind = pkt.ref.kind;

    // Use .value if kind is an FFI enum/struct, otherwise use it directly
    if (kind.value == 0) {
      final frame = pkt.ref.data.frame;
      final frameData =
          Uint8List.fromList(frame.buf.cast<ffi.Uint8>().asTypedList(frame.sz));

      writer.addFrame(frameData, frame.pts);
      // DEBUG: print('Added frame of size ${frameData.length}');
    }
  }
  malloc.free(iter);
}

void _optimizedRgbToYuvNative(
    Uint8List rgb, ffi.Pointer<vpx_image_t> imgPtr, int w, int h) {
  final img = imgPtr.ref;
  final yPlane = img.planes[0].cast<ffi.Uint8>();
  final uPlane = img.planes[1].cast<ffi.Uint8>();
  final vPlane = img.planes[2].cast<ffi.Uint8>();

  final yStr = img.stride[0];
  final uStr = img.stride[1];
  final vStr = img.stride[2];

  for (int y = 0; y < h; y += 2) {
    for (int x = 0; x < w; x += 2) {
      final i00 = (y * w + x) * 3;
      final i01 = (y * w + (x + 1)) * 3;
      final i10 = ((y + 1) * w + x) * 3;
      final i11 = ((y + 1) * w + (x + 1)) * 3;

      yPlane[y * yStr + x] =
          ((66 * rgb[i00] + 129 * rgb[i00 + 1] + 25 * rgb[i00 + 2] + 128) >>
                  8) +
              16;
      yPlane[y * yStr + (x + 1)] =
          ((66 * rgb[i01] + 129 * rgb[i01 + 1] + 25 * rgb[i01 + 2] + 128) >>
                  8) +
              16;
      yPlane[(y + 1) * yStr + x] =
          ((66 * rgb[i10] + 129 * rgb[i10 + 1] + 25 * rgb[i10 + 2] + 128) >>
                  8) +
              16;
      yPlane[(y + 1) * yStr + (x + 1)] =
          ((66 * rgb[i11] + 129 * rgb[i11 + 1] + 25 * rgb[i11 + 2] + 128) >>
                  8) +
              16;

      final rA = (rgb[i00] + rgb[i01] + rgb[i10] + rgb[i11]) >> 2;
      final gA =
          (rgb[i00 + 1] + rgb[i01 + 1] + rgb[i10 + 1] + rgb[i11 + 1]) >> 2;
      final bA =
          (rgb[i00 + 2] + rgb[i01 + 2] + rgb[i10 + 2] + rgb[i11 + 2]) >> 2;

      final uvIdx = (y ~/ 2) * uStr + (x ~/ 2);
      uPlane[uvIdx] = ((-38 * rA - 74 * gA + 112 * bA + 128) >> 8) + 128;
      vPlane[uvIdx] = ((112 * rA - 94 * gA - 18 * bA + 128) >> 8) + 128;
    }
  }
}
