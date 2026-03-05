import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// Assuming your generated bindings are in these files
import 'vpx_bindings.dart';

void main() async {
  // --- 1. CONFIGURATION ---
  const width = 1920;
  const height = 1080;
  const fps = 30;
  const bitRate = 2000; // 2 Mbps
  final inputFile = File('input_1920x1080.yuv');
  final outputFile = File('output.vp8');

  // Frame size for YUV420P: Y (w*h) + U (w/2 * h/2) + V (w/2 * h/2)
  final frameSize = (width * height * 1.5).toInt();

  // --- 2. INITIALIZE NATIVE LIBRARY ---
  final vpxLib = ffi.DynamicLibrary.open('libvpx-1.dll');
  final bindings = NativeLibrary(vpxLib);

  // Allocate Contexts
  final ctx = calloc<vpx_codec_ctx_t>();
  final cfg = calloc<vpx_codec_enc_cfg_t>();

  try {
    // Setup Configuration
    bindings.vpx_codec_enc_config_default(bindings.vpx_codec_vp8_cx(), cfg, 0);
    cfg.ref.g_w = width;
    cfg.ref.g_h = height;
    cfg.ref.g_timebase.num = 1;
    cfg.ref.g_timebase.den = fps;
    cfg.ref.rc_target_bitrate = bitRate;

    // Initialize Encoder
    final initRes = bindings.vpx_codec_enc_init_ver(
        ctx, bindings.vpx_codec_vp8_cx(), cfg, 0, 1);
    if (initRes != 0) throw Exception("Encoder init failed: $initRes");

    // Allocate the VPX Image container (I420 format)
    final rawImg = bindings.vpx_img_alloc(
        ffi.nullptr,
        vpx_img_fmt.VPX_IMG_FMT_I420, // This is the 'fmt' integer constant
        width,
        height,
        1 // This is the 'align' integer
        );
    final outSink = outputFile.openWrite();
    final bytes = await inputFile.readAsBytes();
    int frameCount = 0;

    // --- 3. PROCESSING LOOP ---
    for (int offset = 0;
        offset + frameSize <= bytes.length;
        offset += frameSize) {
      final frameData = bytes.sublist(offset, offset + frameSize);

      // Load raw YUV into the native image planes
      _loadYuvToNative(rawImg, frameData, width, height);

      // Encode the frame
      final encRes = bindings.vpx_codec_encode(
          ctx, rawImg, frameCount, 1, 0, 0x1 /* VPX_DL_REALTIME */);

      if (encRes != 0) break;

      // Pull compressed packets
      _retrieveAndWrite(bindings, ctx, outSink);

      frameCount++;
      print("Processed frame $frameCount");
    }

    // --- 4. FLUSH ---
    bindings.vpx_codec_encode(ctx, ffi.nullptr, -1, 1, 0, 0x1);
    _retrieveAndWrite(bindings, ctx, outSink);

    await outSink.close();
    bindings.vpx_img_free(rawImg);
  } finally {
    bindings.vpx_codec_destroy(ctx);
    malloc.free(ctx);
    malloc.free(cfg);
  }
}

// --- HELPER: COPY YUV BYTES TO NATIVE PLANES ---
void _loadYuvToNative(
    ffi.Pointer<vpx_image_t> imgPtr, Uint8List data, int w, int h) {
  final img = imgPtr.ref;
  final ySize = w * h;
  final uvSize = (w ~/ 2) * (h ~/ 2);

  // Copy Y
  _copyPlane(img.planes[0], img.stride[0], data, 0, w, h);
  // Copy U
  _copyPlane(img.planes[1], img.stride[1], data, ySize, w ~/ 2, h ~/ 2);
  // Copy V
  _copyPlane(
      img.planes[2], img.stride[2], data, ySize + uvSize, w ~/ 2, h ~/ 2);
}

void _copyPlane(ffi.Pointer<ffi.UnsignedChar> ptr, int stride, Uint8List data,
    int offset, int w, int h) {
  for (int y = 0; y < h; y++) {
    final dest = ptr.cast<ffi.Uint8>().elementAt(y * stride).asTypedList(w);
    final srcStart = offset + (y * w);
    dest.setAll(0, data.sublist(srcStart, srcStart + w));
  }
}

// --- HELPER: RETRIEVE PACKETS FROM CODEC ---
void _retrieveAndWrite(
    NativeLibrary lib, ffi.Pointer<vpx_codec_ctx_t> ctx, IOSink sink) {
  final iter = calloc<vpx_codec_iter_t>();
  ffi.Pointer<vpx_codec_cx_pkt_t> pkt;

  while ((pkt = lib.vpx_codec_get_cx_data(ctx, iter)) != ffi.nullptr) {
    if (pkt.ref.kind == 0 /* VPX_CODEC_CX_FRAME_PKT */) {
      final size = pkt.ref.data.frame.sz;
      final buffer = pkt.ref.data.frame.buf.cast<ffi.Uint8>().asTypedList(size);
      sink.add(buffer); // Write compressed VP8 frame to file
    }
  }
  malloc.free(iter);
}
