// CLI: encode a raw RGB24 file to a VP8 IVF using libvpx (via FFI).
//
// Usage:
//   dart run bin/vpx_encode.dart <input.rgb24> <output.ivf> \
//       [--width=384] [--height=216] [--fps=25] [--bitrate=1000]
//
// libvpx is loaded via [loadVpx] (honours the VPX_LIB_PATH env var; falls
// back to common per-platform paths).

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:ffi/ffi.dart';

import 'package:pure_dart_webrtc/src/codecs/vpx2/vpx_bindings.dart';
import 'package:pure_dart_webrtc/src/codecs/vpx2/vpx_loader.dart';

Future<int> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('width', defaultsTo: '384')
    ..addOption('height', defaultsTo: '216')
    ..addOption('fps', defaultsTo: '25')
    ..addOption('bitrate', defaultsTo: '1000', help: 'kbps');
  final ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    return 64;
  }
  if (parsed.rest.length != 2) {
    stderr.writeln('Usage: vpx_encode <input.rgb24> <output.ivf> [options]\n'
        '${parser.usage}');
    return 64;
  }

  final width = int.parse(parsed['width'] as String);
  final height = int.parse(parsed['height'] as String);
  final fps = int.parse(parsed['fps'] as String);
  final bitrate = int.parse(parsed['bitrate'] as String);

  final inputFile = File(parsed.rest[0]);
  final outputFile = File(parsed.rest[1]);
  if (!inputFile.existsSync()) {
    stderr.writeln('Input not found: ${inputFile.path}');
    return 66;
  }

  final lib = loadVpx();

  final ctx = calloc<vpx_codec_ctx_t>();
  final cfg = calloc<vpx_codec_enc_cfg_t>();

  final iface = lib.vpx_codec_vp8_cx();
  if (iface == ffi.nullptr) {
    stderr.writeln('VP8 encoder interface not found');
    return 1;
  }
  lib.vpx_codec_enc_config_default(iface, cfg, 0);
  cfg.ref.g_w = width;
  cfg.ref.g_h = height;
  cfg.ref.g_timebase.num = 1;
  cfg.ref.g_timebase.den = fps;
  cfg.ref.rc_target_bitrate = bitrate;

  final initRes =
      lib.vpx_codec_enc_init_ver(ctx, iface, cfg, 0, VPX_ENCODER_ABI_VERSION);
  if (initRes != vpx_codec_err_t.VPX_CODEC_OK) {
    stderr.writeln('Encoder init failed: $initRes');
    return 1;
  }

  final img = lib.vpx_img_alloc(
      ffi.nullptr, vpx_img_fmt.VPX_IMG_FMT_I420, width, height, 1);
  if (img == ffi.nullptr) {
    stderr.writeln('vpx_img_alloc failed');
    return 1;
  }

  final out = outputFile.openWrite();
  _writeIvfFileHeader(out, width, height, fps);

  final frameSize = width * height * 3;
  final raw = await inputFile.readAsBytes();
  var frameCount = 0;

  for (var off = 0; off + frameSize <= raw.length; off += frameSize) {
    final frame = Uint8List.view(raw.buffer, off, frameSize);
    _rgb24ToI420(frame, img, width, height);
    final r = lib.vpx_codec_encode(ctx, img, frameCount, 1, 0, 1);
    if (r != vpx_codec_err_t.VPX_CODEC_OK) {
      stderr.writeln('encode error at frame $frameCount: $r');
      break;
    }
    _drainPackets(lib, ctx, out);
    frameCount++;
  }

  // Flush.
  lib.vpx_codec_encode(ctx, ffi.nullptr, -1, 1, 0, 1);
  _drainPackets(lib, ctx, out);

  await out.close();
  lib.vpx_img_free(img);
  lib.vpx_codec_destroy(ctx);
  calloc.free(ctx);
  calloc.free(cfg);

  stdout.writeln('Encoded $frameCount frames -> ${outputFile.path} '
      '(${outputFile.lengthSync()} bytes)');
  return 0;
}

void _writeIvfFileHeader(IOSink sink, int w, int h, int fps) {
  final h32 = ByteData(32);
  // Magic 'DKIF' as ASCII bytes 0x44 0x4B 0x49 0x46.
  h32.setUint32(0, 0x46494B44, Endian.little);
  h32.setUint16(4, 0, Endian.little); // version
  h32.setUint16(6, 32, Endian.little); // header length
  h32.setUint32(8, 0x30385056, Endian.little); // 'VP80'
  h32.setUint16(12, w, Endian.little);
  h32.setUint16(14, h, Endian.little);
  h32.setUint32(16, fps, Endian.little); // timebase denom
  h32.setUint32(20, 1, Endian.little); // timebase num
  h32.setUint32(24, 0, Endian.little); // frame count placeholder
  sink.add(h32.buffer.asUint8List());
}

void _drainPackets(
    NativeLibrary lib, ffi.Pointer<vpx_codec_ctx_t> ctx, IOSink sink) {
  final iter = calloc<vpx_codec_iter_t>();
  ffi.Pointer<vpx_codec_cx_pkt_t> pkt;
  while ((pkt = lib.vpx_codec_get_cx_data(ctx, iter)) != ffi.nullptr) {
    if (pkt.ref.kind == vpx_codec_cx_pkt_kind.VPX_CODEC_CX_FRAME_PKT) {
      final frame = pkt.ref.data.frame;
      final fh = ByteData(12);
      fh.setUint32(0, frame.sz, Endian.little);
      fh.setUint64(4, frame.pts, Endian.little);
      sink.add(fh.buffer.asUint8List());
      // Copy the native buffer immediately: the encoder reuses this
      // memory for subsequent frames, so handing the IOSink a view
      // would lead to garbled output once the next frame is encoded.
      sink.add(Uint8List.fromList(
          frame.buf.cast<ffi.Uint8>().asTypedList(frame.sz)));
    }
  }
  calloc.free(iter);
}

void _rgb24ToI420(
    Uint8List rgb, ffi.Pointer<vpx_image_t> imgPtr, int w, int h) {
  final img = imgPtr.ref;
  final yPlane = img.planes[0].cast<ffi.Uint8>();
  final uPlane = img.planes[1].cast<ffi.Uint8>();
  final vPlane = img.planes[2].cast<ffi.Uint8>();
  final yStr = img.stride[0];
  final uStr = img.stride[1];

  for (var y = 0; y < h; y += 2) {
    for (var x = 0; x < w; x += 2) {
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
