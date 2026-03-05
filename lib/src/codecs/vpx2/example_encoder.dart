import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'vpx_bindings.dart';

const int VPX_CODEC_OK = 0;
const int VPX_CODEC_CX_FRAME_PKT = 0;

void main(List<String> args) async {
  const int width = 384;
  const int height = 216;
  const int fps = 25;
  const int bitrate = 1000;

  final inputFile = File('video.rgb24');
  final outputFile = File('output.ivf');

  if (!inputFile.existsSync()) {
    print("Error: video.rgb24 not found");
    return;
  }

  //------------------------------------------------------------
  // Load libvpx
  //------------------------------------------------------------

  final vpxLib = ffi.DynamicLibrary.open('C:/msys64/mingw64/bin/libvpx-1.dll');
  final lib = NativeLibrary(vpxLib);

  final ctx = calloc<vpx_codec_ctx_t>();
  final cfg = calloc<vpx_codec_enc_cfg_t>();

  final iface = lib.vpx_codec_vp8_cx();

  final cfgRes = lib.vpx_codec_enc_config_default(iface, cfg, 0);

  if (cfgRes.value != VPX_CODEC_OK) {
    throw Exception("Failed to get encoder config");
  }

  cfg.ref.g_w = width;
  cfg.ref.g_h = height;

  cfg.ref.g_timebase.num = 1;
  cfg.ref.g_timebase.den = fps;

  cfg.ref.rc_target_bitrate = bitrate;

  //------------------------------------------------------------
  // Initialize encoder
  //------------------------------------------------------------

  final initRes = lib.vpx_codec_enc_init_ver(
    ctx,
    iface,
    cfg,
    0,
    VPX_ENCODER_ABI_VERSION,
  );

  if (initRes.value != VPX_CODEC_OK) {
    throw Exception("Encoder init failed: ${initRes.value}");
  }

  print("Encoder initialized.");

  //------------------------------------------------------------
  // Allocate image
  //------------------------------------------------------------

  final img = lib.vpx_img_alloc(
    ffi.nullptr,
    vpx_img_fmt.VPX_IMG_FMT_I420,
    width,
    height,
    1,
  );

  if (img == ffi.nullptr) {
    throw Exception("Failed to allocate image");
  }

  //------------------------------------------------------------
  // Output
  //------------------------------------------------------------

  final sink = outputFile.openWrite();

  _writeIvfFileHeader(sink, width, height, fps);

  //------------------------------------------------------------
  // Encoding loop
  //------------------------------------------------------------

  final frameSize = width * height * 3;

  final raw = await inputFile.readAsBytes();

  int frameIndex = 0;

  for (int offset = 0; offset + frameSize <= raw.length; offset += frameSize) {
    final rgb = Uint8List.view(raw.buffer, offset, frameSize);

    _rgbToI420(rgb, img, width, height);

    final encRes = lib.vpx_codec_encode(
      ctx,
      img,
      frameIndex,
      1,
      0,
      0,
    );

    if (encRes.value != VPX_CODEC_OK) {
      print("Encode error: ${encRes.value}");
      continue;
    }

    _pullPackets(lib, ctx, sink);

    frameIndex++;

    if (frameIndex % 10 == 0) {
      stdout.write("\rEncoded $frameIndex frames");
    }
  }

  //------------------------------------------------------------
  // Flush encoder
  //------------------------------------------------------------

  lib.vpx_codec_encode(ctx, ffi.nullptr, -1, 1, 0, 0);
  _pullPackets(lib, ctx, sink);

  //------------------------------------------------------------
  // Cleanup
  //------------------------------------------------------------

  await sink.close();

  lib.vpx_img_free(img);

  lib.vpx_codec_destroy(ctx);

  malloc.free(ctx);
  malloc.free(cfg);

  print("\nFinished encoding → ${outputFile.path}");
}

//////////////////////////////////////////////////////////////
// RGB → I420
//////////////////////////////////////////////////////////////

void _rgbToI420(
  Uint8List rgb,
  ffi.Pointer<vpx_image_t> imgPtr,
  int w,
  int h,
) {
  final img = imgPtr.ref;

  final yPlane = img.planes[0].cast<ffi.Uint8>();
  final uPlane = img.planes[1].cast<ffi.Uint8>();
  final vPlane = img.planes[2].cast<ffi.Uint8>();

  final yStride = img.stride[0];
  final uStride = img.stride[1];
  final vStride = img.stride[2];

  for (int y = 0; y < h; y += 2) {
    for (int x = 0; x < w; x += 2) {
      final i00 = (y * w + x) * 3;
      final i01 = (y * w + x + 1) * 3;
      final i10 = ((y + 1) * w + x) * 3;
      final i11 = ((y + 1) * w + x + 1) * 3;

      int r = rgb[i00];
      int g = rgb[i00 + 1];
      int b = rgb[i00 + 2];

      yPlane[y * yStride + x] = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;

      r = rgb[i01];
      g = rgb[i01 + 1];
      b = rgb[i01 + 2];

      yPlane[y * yStride + x + 1] =
          ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;

      r = rgb[i10];
      g = rgb[i10 + 1];
      b = rgb[i10 + 2];

      yPlane[(y + 1) * yStride + x] =
          ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;

      r = rgb[i11];
      g = rgb[i11 + 1];
      b = rgb[i11 + 2];

      yPlane[(y + 1) * yStride + x + 1] =
          ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;

      final rAvg = (rgb[i00] + rgb[i01] + rgb[i10] + rgb[i11]) >> 2;
      final gAvg =
          (rgb[i00 + 1] + rgb[i01 + 1] + rgb[i10 + 1] + rgb[i11 + 1]) >> 2;
      final bAvg =
          (rgb[i00 + 2] + rgb[i01 + 2] + rgb[i10 + 2] + rgb[i11 + 2]) >> 2;

      final uvIndex = (y ~/ 2) * uStride + (x ~/ 2);

      uPlane[uvIndex] =
          ((-38 * rAvg - 74 * gAvg + 112 * bAvg + 128) >> 8) + 128;

      vPlane[uvIndex] = ((112 * rAvg - 94 * gAvg - 18 * bAvg + 128) >> 8) + 128;
    }
  }
}

//////////////////////////////////////////////////////////////
// IVF FILE HEADER
//////////////////////////////////////////////////////////////

void _writeIvfFileHeader(IOSink sink, int w, int h, int fps) {
  final header = ByteData(32);

  header.setUint32(0, 0x46494B44, Endian.little); // DKIF
  header.setUint16(4, 0, Endian.little); // version
  header.setUint16(6, 32, Endian.little); // header size

  header.setUint32(8, 0x30385056, Endian.little); // VP80

  header.setUint16(12, w, Endian.little);
  header.setUint16(14, h, Endian.little);

  header.setUint32(16, fps, Endian.little);
  header.setUint32(20, 1, Endian.little);

  header.setUint32(24, 0, Endian.little);
  header.setUint32(28, 0, Endian.little);

  sink.add(header.buffer.asUint8List());
}

//////////////////////////////////////////////////////////////
// PACKET WRITER
//////////////////////////////////////////////////////////////

void _pullPackets(
  NativeLibrary lib,
  ffi.Pointer<vpx_codec_ctx_t> ctx,
  IOSink sink,
) {
  final iter = calloc<vpx_codec_iter_t>();

  iter.value = ffi.nullptr;

  ffi.Pointer<vpx_codec_cx_pkt_t> pkt;

  while ((pkt = lib.vpx_codec_get_cx_data(ctx, iter)) != ffi.nullptr) {
    if (pkt.ref.kind.value == VPX_CODEC_CX_FRAME_PKT) {
      final frame = pkt.ref.data.frame;

      final header = ByteData(12);

      header.setUint32(0, frame.sz, Endian.little);
      header.setUint64(4, frame.pts, Endian.little);

      sink.add(header.buffer.asUint8List());

      final bytes = frame.buf.cast<ffi.Uint8>().asTypedList(frame.sz);

      sink.add(bytes);
    }
  }

  malloc.free(iter);
}
