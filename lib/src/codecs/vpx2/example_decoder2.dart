import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'vpx_bindings.dart';

const int VPX_CODEC_OK = 0;

void main() async {
  final inputFile = File('output.ivf');
  final outputFile = File('decoded2.yuv');

  if (!inputFile.existsSync()) {
    print('Error: IVF file not found');
    return;
  }

  // ------------------------------------------------------------
  // Open IVF
  // ------------------------------------------------------------
  final raf = await inputFile.open();
  final header = _readIvfHeader(raf);

  print("Codec: ${header.codec}");
  print("Resolution: ${header.width}x${header.height}");
  print("FPS: ${header.fps}");

  // ------------------------------------------------------------
  // Load libvpx
  // ------------------------------------------------------------
  final vpxLib = ffi.DynamicLibrary.open('C:/msys64/mingw64/bin/libvpx-1.dll');
  final lib = NativeLibrary(vpxLib);

  final ctx = calloc<vpx_codec_ctx_t>();

  // Select decoder automatically
  ffi.Pointer<vpx_codec_iface_t> iface;

  if (header.codec == "VP80") {
    iface = lib.vpx_codec_vp8_dx();
  } else if (header.codec == "VP90") {
    iface = lib.vpx_codec_vp9_dx();
  } else {
    throw Exception("Unsupported codec: ${header.codec}");
  }

  final res = lib.vpx_codec_dec_init_ver(
    ctx,
    iface,
    ffi.nullptr,
    0,
    VPX_DECODER_ABI_VERSION,
  );

  if (res.value != VPX_CODEC_OK) {
    throw Exception("Decoder init failed: ${res.value}");
  }

  print("Decoder initialized.");

  final sink = outputFile.openWrite();

  final iter = calloc<vpx_codec_iter_t>();
  iter.value = ffi.nullptr;

  // ------------------------------------------------------------
  // Decode loop
  // ------------------------------------------------------------
  while (true) {
    final frame = _readIvfFrame(raf);
    if (frame == null) break;

    final buf = malloc.allocate<ffi.Uint8>(frame.size);
    buf.asTypedList(frame.size).setAll(0, frame.data);

    final decodeRes = lib.vpx_codec_decode(
      ctx,
      buf,
      frame.size,
      ffi.nullptr,
      0,
    );

    malloc.free(buf);

    if (decodeRes.value != VPX_CODEC_OK) {
      print("Decode error: ${decodeRes.value}");
      continue;
    }

    ffi.Pointer<vpx_image_t> img;

    iter.value = ffi.nullptr;

    while ((img = lib.vpx_codec_get_frame(ctx, iter)) != ffi.nullptr) {
      _writeI420Frame(img, header.width, header.height, sink);
    }
  }

  // ------------------------------------------------------------
  // Cleanup
  // ------------------------------------------------------------
  malloc.free(iter);
  lib.vpx_codec_destroy(ctx);
  malloc.free(ctx);

  await raf.close();
  await sink.close();

  print("Decoding finished.");
  print("Output written to decoded.yuv");
}

//////////////////////////////////////////////////////////////
// IVF HEADER
//////////////////////////////////////////////////////////////

class IvfHeader {
  final int width;
  final int height;
  final int fps;
  final String codec;

  IvfHeader(this.width, this.height, this.fps, this.codec);
}

IvfHeader _readIvfHeader(RandomAccessFile f) {
  final data = f.readSync(32);

  final signature = String.fromCharCodes(data.sublist(0, 4));

  if (signature != "DKIF") {
    throw Exception("Invalid IVF file (missing DKIF)");
  }

  final hdr = ByteData.sublistView(data);

  final codec = String.fromCharCodes(data.sublist(8, 12));
  final width = hdr.getUint16(12, Endian.little);
  final height = hdr.getUint16(14, Endian.little);
  final fps = hdr.getUint32(16, Endian.little);

  return IvfHeader(width, height, fps, codec);
}

//////////////////////////////////////////////////////////////
// IVF FRAME
//////////////////////////////////////////////////////////////

class IvfFrame {
  final int size;
  final int pts;
  final Uint8List data;

  IvfFrame(this.size, this.pts, this.data);
}

IvfFrame? _readIvfFrame(RandomAccessFile f) {
  final hdrBytes = f.readSync(12);
  if (hdrBytes.length < 12) return null;

  final hdr = ByteData.sublistView(hdrBytes);

  final size = hdr.getUint32(0, Endian.little);
  final pts = hdr.getUint64(4, Endian.little);

  final data = f.readSync(size);

  if (data.length < size) return null;

  return IvfFrame(size, pts, data);
}

//////////////////////////////////////////////////////////////
// I420 WRITER
//////////////////////////////////////////////////////////////

void _writeI420Frame(
  ffi.Pointer<vpx_image_t> imgPtr,
  int width,
  int height,
  IOSink sink,
) {
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

  for (int row = 0; row < height; row++) {
    sink.add(yBuf.sublist(row * yStride, row * yStride + width));
  }

  for (int row = 0; row < height ~/ 2; row++) {
    sink.add(uBuf.sublist(row * uStride, row * uStride + width ~/ 2));
  }

  for (int row = 0; row < height ~/ 2; row++) {
    sink.add(vBuf.sublist(row * vStride, row * vStride + width ~/ 2));
  }
}
