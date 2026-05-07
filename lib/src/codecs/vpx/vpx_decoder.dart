// High-level VP8/VP9 decoder. Wraps libvpx via FFI; consumers see only Dart
// types ([Uint8List] in, [I420Frame] out).

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'i420_frame.dart';
import 'vpx_bindings.dart';
import 'vpx_codec_kind.dart';
import 'vpx_encoder.dart' show VpxException;
import 'vpx_loader.dart';

class VpxDecoder {
  final VpxCodec codec;

  final NativeLibrary _lib;
  final ffi.Pointer<vpx_codec_ctx_t> _ctx;
  bool _disposed = false;

  VpxDecoder._(this.codec, this._lib, this._ctx);

  /// Initialise a libvpx decoder.
  factory VpxDecoder({
    required VpxCodec codec,
    NativeLibrary? library,
  }) {
    final lib = library ?? loadVpx();
    final ctx = calloc<vpx_codec_ctx_t>();
    try {
      final iface = switch (codec) {
        VpxCodec.vp8 => lib.vpx_codec_vp8_dx(),
        VpxCodec.vp9 => lib.vpx_codec_vp9_dx(),
      };
      if (iface == ffi.nullptr) {
        throw VpxException('Decoder interface for ${codec.name} not available');
      }
      final r = lib.vpx_codec_dec_init_ver(
          ctx, iface, ffi.nullptr, 0, VPX_DECODER_ABI_VERSION);
      if (r != vpx_codec_err_t.VPX_CODEC_OK) {
        throw VpxException('vpx_codec_dec_init_ver failed: $r');
      }
      return VpxDecoder._(codec, lib, ctx);
    } catch (_) {
      lib.vpx_codec_destroy(ctx);
      calloc.free(ctx);
      rethrow;
    }
  }

  /// Decode a single compressed bitstream packet and return the I420 frames
  /// it produced (usually 0 or 1; codecs may emit 0 when buffering).
  List<I420Frame> decode(Uint8List payload) {
    _checkAlive();
    final buf = malloc.allocate<ffi.Uint8>(payload.length);
    try {
      buf.asTypedList(payload.length).setAll(0, payload);
      final r =
          _lib.vpx_codec_decode(_ctx, buf, payload.length, ffi.nullptr, 0);
      if (r != vpx_codec_err_t.VPX_CODEC_OK) {
        throw VpxException('vpx_codec_decode failed: $r');
      }
    } finally {
      malloc.free(buf);
    }

    final iter = calloc<vpx_codec_iter_t>();
    final frames = <I420Frame>[];
    try {
      ffi.Pointer<vpx_image_t> img;
      while ((img = _lib.vpx_codec_get_frame(_ctx, iter)) != ffi.nullptr) {
        frames.add(_imageToI420(img));
      }
    } finally {
      calloc.free(iter);
    }
    return frames;
  }

  /// Release native resources. Safe to call multiple times.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lib.vpx_codec_destroy(_ctx);
    calloc.free(_ctx);
  }

  void _checkAlive() {
    if (_disposed) throw StateError('VpxDecoder has been disposed');
  }

  static I420Frame _imageToI420(ffi.Pointer<vpx_image_t> imgPtr) {
    final img = imgPtr.ref;
    final w = img.d_w;
    final h = img.d_h;
    final cw = (w + 1) >> 1;
    final ch = (h + 1) >> 1;
    final yStr = img.stride[0];
    final uStr = img.stride[1];
    final vStr = img.stride[2];

    final y = Uint8List(w * h);
    final u = Uint8List(cw * ch);
    final v = Uint8List(cw * ch);

    final yBuf = img.planes[0].cast<ffi.Uint8>().asTypedList(yStr * h);
    for (var row = 0; row < h; row++) {
      y.setRange(row * w, row * w + w, yBuf, row * yStr);
    }
    final uBuf = img.planes[1].cast<ffi.Uint8>().asTypedList(uStr * ch);
    for (var row = 0; row < ch; row++) {
      u.setRange(row * cw, row * cw + cw, uBuf, row * uStr);
    }
    final vBuf = img.planes[2].cast<ffi.Uint8>().asTypedList(vStr * ch);
    for (var row = 0; row < ch; row++) {
      v.setRange(row * cw, row * cw + cw, vBuf, row * vStr);
    }

    return I420Frame(width: w, height: h, y: y, u: u, v: v);
  }
}
