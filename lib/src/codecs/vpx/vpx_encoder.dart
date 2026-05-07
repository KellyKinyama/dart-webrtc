// High-level VP8/VP9 encoder. Wraps libvpx via FFI and hides all native
// pointer plumbing behind a tight Dart API.
//
// Lifecycle:
//   final enc = VpxEncoder(codec: VpxCodec.vp8, width: 384, height: 216);
//   for (var i = 0; i < frames.length; i++) {
//     for (final pkt in enc.encode(frames[i], pts: i)) {
//       sink.writeFrame(pkt.data, pkt.pts);
//     }
//   }
//   for (final pkt in enc.flush()) sink.writeFrame(pkt.data, pkt.pts);
//   enc.dispose();

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'i420_frame.dart';
import 'vpx_bindings.dart';
import 'vpx_codec_kind.dart';
import 'vpx_loader.dart';

/// One compressed bitstream packet emitted by [VpxEncoder].
class VpxPacket {
  /// Compressed bytes (always a fresh copy — safe to retain).
  final Uint8List data;

  /// Presentation timestamp in encoder time-base ticks (== the `pts`
  /// passed to [VpxEncoder.encode]).
  final int pts;

  /// True if this packet starts an independently decodable group.
  final bool isKeyframe;

  const VpxPacket({
    required this.data,
    required this.pts,
    required this.isKeyframe,
  });
}

class VpxEncoder {
  final VpxCodec codec;
  final int width;
  final int height;
  final int fps;

  final NativeLibrary _lib;
  final ffi.Pointer<vpx_codec_ctx_t> _ctx;
  final ffi.Pointer<vpx_image_t> _img;
  bool _disposed = false;

  VpxEncoder._(this.codec, this.width, this.height, this.fps, this._lib,
      this._ctx, this._img);

  /// Create and initialise a libvpx encoder.
  ///
  /// [bitrateKbps] sets the target bitrate. [keyframeInterval] is the maximum
  /// distance between keyframes (libvpx default if null).
  factory VpxEncoder({
    required VpxCodec codec,
    required int width,
    required int height,
    int fps = 30,
    int bitrateKbps = 1000,
    int? keyframeInterval,
    NativeLibrary? library,
  }) {
    final lib = library ?? loadVpx();
    final ctx = calloc<vpx_codec_ctx_t>();
    final cfg = calloc<vpx_codec_enc_cfg_t>();
    ffi.Pointer<vpx_image_t>? img;
    try {
      final iface = switch (codec) {
        VpxCodec.vp8 => lib.vpx_codec_vp8_cx(),
        VpxCodec.vp9 => lib.vpx_codec_vp9_cx(),
      };
      if (iface == ffi.nullptr) {
        throw VpxException('Encoder interface for ${codec.name} not available');
      }
      final defRes = lib.vpx_codec_enc_config_default(iface, cfg, 0);
      if (defRes != vpx_codec_err_t.VPX_CODEC_OK) {
        throw VpxException('vpx_codec_enc_config_default failed: $defRes');
      }
      cfg.ref.g_w = width;
      cfg.ref.g_h = height;
      cfg.ref.g_timebase.num = 1;
      cfg.ref.g_timebase.den = fps;
      cfg.ref.rc_target_bitrate = bitrateKbps;
      if (keyframeInterval != null) {
        cfg.ref.kf_max_dist = keyframeInterval;
      }

      final initRes = lib.vpx_codec_enc_init_ver(
          ctx, iface, cfg, 0, VPX_ENCODER_ABI_VERSION);
      if (initRes != vpx_codec_err_t.VPX_CODEC_OK) {
        throw VpxException('vpx_codec_enc_init_ver failed: $initRes');
      }

      img = lib.vpx_img_alloc(
          ffi.nullptr, vpx_img_fmt.VPX_IMG_FMT_I420, width, height, 1);
      if (img == ffi.nullptr) {
        throw VpxException('vpx_img_alloc failed');
      }

      return VpxEncoder._(codec, width, height, fps, lib, ctx, img);
    } catch (_) {
      if (img != null && img != ffi.nullptr) lib.vpx_img_free(img);
      lib.vpx_codec_destroy(ctx);
      calloc.free(ctx);
      calloc.free(cfg);
      rethrow;
    } finally {
      calloc.free(cfg);
    }
  }

  /// Encode one I420 frame and return any packets the encoder produced.
  ///
  /// [pts] is the timestamp in time-base ticks (denominator = [fps]).
  /// Set [forceKeyframe] to mark the next packet as a keyframe.
  List<VpxPacket> encode(I420Frame frame,
      {required int pts, bool forceKeyframe = false}) {
    _checkAlive();
    if (frame.width != width || frame.height != height) {
      throw ArgumentError(
          'Frame ${frame.width}x${frame.height} does not match encoder '
          '${width}x$height');
    }
    _copyI420ToImage(frame);
    final flags = forceKeyframe ? VPX_EFLAG_FORCE_KF : 0;
    final r = _lib.vpx_codec_encode(_ctx, _img, pts, 1, flags, 1);
    if (r != vpx_codec_err_t.VPX_CODEC_OK) {
      throw VpxException('vpx_codec_encode failed: $r');
    }
    return _drain();
  }

  /// Signal end-of-stream and return any remaining buffered packets.
  /// After calling this, do not call [encode] again — call [dispose].
  List<VpxPacket> flush() {
    _checkAlive();
    _lib.vpx_codec_encode(_ctx, ffi.nullptr, -1, 1, 0, 1);
    return _drain();
  }

  /// Release native resources. Safe to call multiple times.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lib.vpx_img_free(_img);
    _lib.vpx_codec_destroy(_ctx);
    calloc.free(_ctx);
  }

  void _checkAlive() {
    if (_disposed) throw StateError('VpxEncoder has been disposed');
  }

  List<VpxPacket> _drain() {
    final iter = calloc<vpx_codec_iter_t>();
    final out = <VpxPacket>[];
    try {
      ffi.Pointer<vpx_codec_cx_pkt_t> pkt;
      while ((pkt = _lib.vpx_codec_get_cx_data(_ctx, iter)) != ffi.nullptr) {
        if (pkt.ref.kind == vpx_codec_cx_pkt_kind.VPX_CODEC_CX_FRAME_PKT) {
          final f = pkt.ref.data.frame;
          // libvpx reuses `f.buf` for the next frame, so we copy now.
          final bytes =
              Uint8List.fromList(f.buf.cast<ffi.Uint8>().asTypedList(f.sz));
          final isKey = (f.flags & 1) != 0; // VPX_FRAME_IS_KEY
          out.add(VpxPacket(data: bytes, pts: f.pts, isKeyframe: isKey));
        }
      }
    } finally {
      calloc.free(iter);
    }
    return out;
  }

  void _copyI420ToImage(I420Frame f) {
    final img = _img.ref;
    final yPlane = img.planes[0].cast<ffi.Uint8>();
    final uPlane = img.planes[1].cast<ffi.Uint8>();
    final vPlane = img.planes[2].cast<ffi.Uint8>();
    final yStr = img.stride[0];
    final uStr = img.stride[1];
    final vStr = img.stride[2];
    final cw = (width + 1) >> 1;
    final ch = (height + 1) >> 1;

    final yBuf = yPlane.asTypedList(yStr * height);
    for (var row = 0; row < height; row++) {
      yBuf.setRange(row * yStr, row * yStr + width, f.y, row * width);
    }
    final uBuf = uPlane.asTypedList(uStr * ch);
    for (var row = 0; row < ch; row++) {
      uBuf.setRange(row * uStr, row * uStr + cw, f.u, row * cw);
    }
    final vBuf = vPlane.asTypedList(vStr * ch);
    for (var row = 0; row < ch; row++) {
      vBuf.setRange(row * vStr, row * vStr + cw, f.v, row * cw);
    }
  }
}

class VpxException implements Exception {
  final String message;
  const VpxException(this.message);
  @override
  String toString() => 'VpxException: $message';
}
