// CLI: decode a VP8/VP9 IVF file to a raw I420 YUV file using libvpx.
//
// Usage:
//   dart run bin/vpx_decode.dart <input.ivf> <output.yuv>
//
// The output is concatenated I420 planes per frame (Y, then U, then V),
// at the resolution declared in the IVF file header.

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:pure_dart_webrtc/src/codecs/vpx2/vpx_bindings.dart';
import 'package:pure_dart_webrtc/src/codecs/vpx2/vpx_loader.dart';

Future<int> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('Usage: vpx_decode <input.ivf> <output.yuv>');
    return 64;
  }
  final inputFile = File(args[0]);
  final outputFile = File(args[1]);
  if (!inputFile.existsSync()) {
    stderr.writeln('Input not found: ${inputFile.path}');
    return 66;
  }

  final raf = await inputFile.open();
  final header = _readIvfHeader(raf);
  stdout.writeln('Codec: ${header.codec}  '
      'Resolution: ${header.width}x${header.height}  FPS: ${header.fps}');

  final lib = loadVpx();
  final ctx = calloc<vpx_codec_ctx_t>();

  ffi.Pointer<vpx_codec_iface_t> iface;
  switch (header.codec) {
    case 'VP80':
      iface = lib.vpx_codec_vp8_dx();
      break;
    case 'VP90':
      iface = lib.vpx_codec_vp9_dx();
      break;
    default:
      stderr.writeln('Unsupported codec: ${header.codec}');
      return 1;
  }

  final r = lib.vpx_codec_dec_init_ver(
      ctx, iface, ffi.nullptr, 0, VPX_DECODER_ABI_VERSION);
  if (r != vpx_codec_err_t.VPX_CODEC_OK) {
    stderr.writeln('Decoder init failed: $r');
    return 1;
  }

  final sink = outputFile.openWrite();
  final iter = calloc<vpx_codec_iter_t>();
  var frameCount = 0;

  while (true) {
    final frame = _readIvfFrame(raf);
    if (frame == null) break;

    final buf = malloc.allocate<ffi.Uint8>(frame.size);
    buf.asTypedList(frame.size).setAll(0, frame.data);
    final dr = lib.vpx_codec_decode(ctx, buf, frame.size, ffi.nullptr, 0);
    malloc.free(buf);
    if (dr != vpx_codec_err_t.VPX_CODEC_OK) {
      stderr.writeln('Decode error on frame $frameCount: $dr');
      continue;
    }

    iter.value = ffi.nullptr;
    ffi.Pointer<vpx_image_t> img;
    while ((img = lib.vpx_codec_get_frame(ctx, iter)) != ffi.nullptr) {
      _writeI420Frame(img, header.width, header.height, sink);
      frameCount++;
    }
  }

  calloc.free(iter);
  lib.vpx_codec_destroy(ctx);
  calloc.free(ctx);
  await raf.close();
  await sink.close();

  stdout.writeln('Decoded $frameCount frames -> ${outputFile.path} '
      '(${outputFile.lengthSync()} bytes)');
  return 0;
}

class _IvfHeader {
  final int width;
  final int height;
  final int fps;
  final String codec;
  _IvfHeader(this.width, this.height, this.fps, this.codec);
}

_IvfHeader _readIvfHeader(RandomAccessFile f) {
  final data = f.readSync(32);
  if (String.fromCharCodes(data.sublist(0, 4)) != 'DKIF') {
    throw const FormatException('Invalid IVF file (missing DKIF signature)');
  }
  final hdr = ByteData.sublistView(data);
  final codec = String.fromCharCodes(data.sublist(8, 12));
  return _IvfHeader(
    hdr.getUint16(12, Endian.little),
    hdr.getUint16(14, Endian.little),
    hdr.getUint32(16, Endian.little),
    codec,
  );
}

class _IvfFrame {
  final int size;
  final int pts;
  final Uint8List data;
  _IvfFrame(this.size, this.pts, this.data);
}

_IvfFrame? _readIvfFrame(RandomAccessFile f) {
  final hdrBytes = f.readSync(12);
  if (hdrBytes.length < 12) return null;
  final hdr = ByteData.sublistView(hdrBytes);
  final size = hdr.getUint32(0, Endian.little);
  final pts = hdr.getUint64(4, Endian.little);
  final data = f.readSync(size);
  if (data.length < size) return null;
  return _IvfFrame(size, pts, data);
}

void _writeI420Frame(
    ffi.Pointer<vpx_image_t> imgPtr, int width, int height, IOSink sink) {
  final img = imgPtr.ref;
  final y = img.planes[0].cast<ffi.Uint8>();
  final u = img.planes[1].cast<ffi.Uint8>();
  final v = img.planes[2].cast<ffi.Uint8>();
  final yStride = img.stride[0];
  final uStride = img.stride[1];
  final vStride = img.stride[2];

  final yBuf = y.asTypedList(yStride * height);
  final uBuf = u.asTypedList(uStride * (height ~/ 2));
  final vBuf = v.asTypedList(vStride * (height ~/ 2));

  for (var row = 0; row < height; row++) {
    sink.add(yBuf.sublist(row * yStride, row * yStride + width));
  }
  for (var row = 0; row < height ~/ 2; row++) {
    sink.add(uBuf.sublist(row * uStride, row * uStride + width ~/ 2));
  }
  for (var row = 0; row < height ~/ 2; row++) {
    sink.add(vBuf.sublist(row * vStride, row * vStride + width ~/ 2));
  }
}
