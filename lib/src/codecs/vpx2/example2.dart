import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// Ensure this matches your ffigen output file name
import 'vpx_bindings.dart';

void main(List<String> args) async {
  // --- 1. SETTINGS ---
  const int width = 384;
  const int height = 216;
  const int fps = 25;
  const int bitrateValue = 1000; // Renamed to avoid confusion

  final inputFile = File('video.rgb24');
  final outputFile = File('output.ivf');

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
  bindings.vpx_codec_enc_config_default(iface, cfg, 0);

  cfg.ref.g_w = width;
  cfg.ref.g_h = height;
  cfg.ref.g_timebase.num = 1;
  cfg.ref.g_timebase.den = fps;
  cfg.ref.rc_target_bitrate = bitrateValue;

  int? successfulAbi;
  print('Searching for compatible ABI version...');

  int abi = 34;
  // for (int abi = 0; abi <= 100; abi++) {
  final res = bindings.vpx_codec_enc_init_ver(ctx, iface, cfg, 0, abi);
  // final res = bindings.vpx_codec_enc_init_ver(ctx, iface, cfg, abi, abi);
  // print("Result: $res");

  // FIX: Accessing the underlying integer value of the error object
  // Depending on your ffigen settings, this is usually .value or .index
  // If neither works, use: res.toString().contains('VPX_CODEC_OK')
  if (res.value == 0 ||
      (res is! int && res.toString().contains('VPX_CODEC_OK'))) {
    successfulAbi = abi;
    // break;
  }
  // }

  if (successfulAbi == null) {
    print('Could not find matching ABI. This might be a config issue.');
    return;
  }

  print('SUCCESS: Encoder initialized with ABI Version: $successfulAbi');

  // --- 3. ALLOCATE NATIVE IMAGE ---
  // Using the signature: Pointer<vpx_image> vpx_img_alloc(img, fmt, d_w, d_h, align)
  final ffi.Pointer<vpx_image_t> vpxImg = bindings.vpx_img_alloc(
      ffi.nullptr, vpx_img_fmt.VPX_IMG_FMT_I420, width, height, 1);

  // --- 4. PREPARE OUTPUT ---
  final outSink = outputFile.openWrite();
  _writeIvfFileHeader(outSink, width, height, fps);

  // --- 5. ENCODE LOOP ---
  final frameSize = width * height * 3;
  final rawData = await inputFile.readAsBytes();
  int frameCount = 0;

  for (int offset = 0;
      offset + frameSize <= rawData.length;
      offset += frameSize) {
    final rgbFrame = Uint8List.view(rawData.buffer, offset, frameSize);
    _optimizedRgbToYuvNative(rgbFrame, vpxImg, width, height);

    // Perform the encode
    final encRes = bindings.vpx_codec_encode(ctx, vpxImg, frameCount, 1, 0, 1);

    // Check for success (similar to the init check)
    if (encRes.value == 0 || encRes.toString().contains('VPX_CODEC_OK')) {
      _pullAndWriteIvfPackets(bindings, ctx, outSink);
    }

    frameCount++;
    if (frameCount % 10 == 0) stdout.write('\rEncoded $frameCount frames...');
  }

  // Flush
  bindings.vpx_codec_encode(ctx, ffi.nullptr, -1, 1, 0, 1);
  _pullAndWriteIvfPackets(bindings, ctx, outSink);

  await outSink.close();
  bindings.vpx_img_free(vpxImg);
  bindings.vpx_codec_destroy(ctx);
  malloc.free(ctx);
  malloc.free(cfg);

  print('\nFinished! Saved to ${outputFile.path}');
}

// --- HELPERS ---

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

      // Y calculations for 4 pixels
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

      // Average RGB for U/V
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

void _writeIvfFileHeader(IOSink sink, int w, int h, int fps) {
  final header = ByteData(32);
  header.setUint32(0, 0x46564944, Endian.little); // 'DKIF'
  header.setUint32(8, 0x30385056, Endian.little); // 'VP80'
  header.setUint16(12, w, Endian.little);
  header.setUint16(14, h, Endian.little);
  header.setUint32(16, fps, Endian.little);
  header.setUint32(20, 1, Endian.little);
  sink.add(header.buffer.asUint8List());
}

void _pullAndWriteIvfPackets(
    NativeLibrary lib, ffi.Pointer<vpx_codec_ctx_t> ctx, IOSink sink) {
  final iter = calloc<vpx_codec_iter_t>();
  ffi.Pointer<vpx_codec_cx_pkt_t> pkt;
  while ((pkt = lib.vpx_codec_get_cx_data(ctx, iter)) != ffi.nullptr) {
    if (pkt.ref.kind.value == 0) {
      // VPX_CODEC_CX_FRAME_PKT
      final frame = pkt.ref.data.frame;
      final fHeader = ByteData(12);
      fHeader.setUint32(0, frame.sz, Endian.little);
      fHeader.setUint64(4, frame.pts, Endian.little);
      sink.add(fHeader.buffer.asUint8List());
      sink.add(frame.buf.cast<ffi.Uint8>().asTypedList(frame.sz));
    }
  }
  malloc.free(iter);
}
