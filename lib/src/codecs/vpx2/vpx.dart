// lib/src/vpx_exception.dart
import 'package:ffi/ffi.dart';

/// Custom exception for VPX FFI operations.
class VpxException implements Exception {
  final String message;
  final int? errorCode;
  final String? errorDetail;

  VpxException(this.message, {this.errorCode, this.errorDetail});

  @override
  String toString() {
    String result = 'VpxException: $message';
    if (errorCode != null) {
      result += ' (Error Code: $errorCode)';
    }
    if (errorDetail != null && errorDetail!.isNotEmpty) {
      result += ' (Detail: $errorDetail)';
    }
    return result;
  }
}

// lib/src/vpx_enums.dart
// ignore_for_file: constant_identifier_names

/// Enum for VP8 encoder control IDs.
enum Vp8eEncControlId {
  VP8E_SET_CPUUSED(13),
  VP8E_SET_NOISE_SENSITIVITY(15),
  VP8E_SET_STATIC_THRESHOLD(17),
  VP8E_SET_TOKEN_PARTITIONS(18);

  final int value;
  const Vp8eEncControlId(this.value);
}

/// Enum for VPX codec error codes.
enum VpxCodecErrT {
  VPX_CODEC_OK(0),
  VPX_CODEC_ERROR(1),
  VPX_CODEC_MEM_ERROR(2),
  VPX_CODEC_ABI_MISMATCH(3),
  VPX_CODEC_INCAPABLE(4),
  VPX_CODEC_UNSUP_BITSTREAM(5),
  VPX_CODEC_UNSUP_FEATURE(6),
  VPX_CODEC_CORRUPT_FRAME(7),
  VPX_CODEC_INVALID_PARAM(8),
  VPX_CODEC_LIST_END(9);

  final int value;
  const VpxCodecErrT(this.value);
}

/// Enum for VPX bit depth.
enum VpxBitDepthT {
  VPX_BITS_8(8),
  VPX_BITS_10(10),
  VPX_BITS_12(12);

  final int value;
  const VpxBitDepthT(this.value);
}

/// Enum for VPX encoding pass.
enum VpxEncPass {
  VPX_RC_ONE_PASS(0),
  VPX_RC_FIRST_PASS(1),
  VPX_RC_LAST_PASS(2);

  final int value;
  const VpxEncPass(this.value);
}

/// Enum for VPX rate control mode.
enum VpxRcMode {
  VPX_VBR(0),
  VPX_CBR(1),
  VPX_CQ(2),
  VPX_Q(3);

  final int value;
  const VpxRcMode(this.value);
}

/// Enum for VPX keyframe mode.
enum VpxKfMode {
  VPX_KF_FIXED(0),
  VPX_KF_AUTO(1),
  VPX_KF_DISABLED(2);

  final int value;
  const VpxKfMode(this.value);
}

/// Enum for VPX image format.
enum VpxImgFmtT {
  VPX_IMG_FMT_NONE(0),
  VPX_IMG_FMT_I420(258); // Assuming this is the primary one from PHP code

  final int value;
  const VpxImgFmtT(this.value);
}

/// Enum for VPX color space.
enum VpxColorSpaceT {
  VPX_CS_UNKNOWN(0),
  VPX_CS_BT_601(1),
  VPX_CS_BT_709(2),
  VPX_CS_SMPTE_170(3),
  VPX_CS_SMPTE_240(4),
  VPX_CS_BT_2020(5),
  VPX_CS_RESERVED(6),
  VPX_CS_SRGB(7);

  final int value;
  const VpxColorSpaceT(this.value);
}

/// Enum for VPX color range.
enum VpxColorRangeT {
  VPX_CR_STUDIO_RANGE(0),
  VPX_CR_FULL_RANGE(1);

  final int value;
  const VpxColorRangeT(this.value);
}

/// Enum for VPX codec output packet kind.
enum VpxCodecCxPktKind {
  VPX_CODEC_CX_FRAME_PKT(0),
  VPX_CODEC_STATS_PKT(1),
  VPX_CODEC_FPMB_STATS_PKT(2),
  VPX_CODEC_PSNR_PKT(3),
  VPX_CODEC_CUSTOM_PKT(256);

  final int value;
  const VpxCodecCxPktKind(this.value);
}

/// Enum for codec interfaces (used by Config and Encoder/Decoder).
enum BriefInterface {
  VP8_CX('vpx_codec_vp8_cx'),
  VP8_DX('vpx_codec_vp8_dx'),
  VP9_CX('vpx_codec_vp9_cx'), // Assuming VP9 exists based on PHP comments
  VP9_DX('vpx_codec_vp9_dx'); // Assuming VP9 exists based on PHP comments

  final String functionName;
  const BriefInterface(this.functionName);
}


// lib/src/vpx_bindings.dart
// ignore_for_file: camel_case_types, non_constant_identifier_names

import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:webrtc_vpx_ffi/src/vpx_enums.dart'; // Import the enums

// --- Typedefs ---
typedef vpx_codec_er_flags_t = ffi.Uint32;
typedef vpx_codec_pts_t = ffi.Int64;
typedef vpx_codec_frame_flags_t = ffi.Uint32;
typedef vpx_enc_frame_flags_t = ffi.Int64; // long in C is typically 64-bit on Windows/Linux x64
typedef vpx_enc_deadline_t = ffi.Uint64; // unsigned long in C is typically 64-bit on Windows/Linux x64
typedef vpx_codec_iter_t = ffi.Pointer<ffi.Void>;

// --- Opaque Structs/Pointers ---
class vpx_codec_iface_t extends ffi.Opaque {}
class vpx_codec_priv_t extends ffi.Opaque {}

// --- Structs ---
class vpx_rational extends ffi.Struct {
  @ffi.Int32()
  external int num;
  @ffi.Int32()
  external int den;
}

class vpx_fixed_buf extends ffi.Struct {
  external ffi.Pointer<ffi.Void> buf;
  @ffi.Size()
  external int sz;
}

// Union for vpx_codec_ctx config
class _VpxCodecCtxConfigUnion extends ffi.Union {
  external ffi.Pointer<vpx_codec_dec_cfg> dec;
  external ffi.Pointer<vpx_codec_enc_cfg> enc;
  external ffi.Pointer<ffi.Void> raw;
}

class vpx_codec_ctx extends ffi.Struct {
  external ffi.Pointer<ffi.Char> name;
  external ffi.Pointer<vpx_codec_iface_t> iface;
  @ffi.Int32() // vpx_codec_err_t is an enum, but maps to int
  external int err;
  external ffi.Pointer<ffi.Char> err_detail;
  @vpx_codec_flags_t()
  external int init_flags;
  external _VpxCodecCtxConfigUnion config;
  external ffi.Pointer<vpx_codec_priv_t> priv;
}

class vpx_codec_enc_cfg extends ffi.Struct {
  @ffi.Uint32()
  external int g_usage;
  @ffi.Uint32()
  external int g_threads;
  @ffi.Uint32()
  external int g_profile;
  @ffi.Uint32()
  external int g_w;
  @ffi.Uint32()
  external int g_h;
  @ffi.Int32() // vpx_bit_depth_t
  external int g_bit_depth;
  @ffi.Uint32()
  external int g_input_bit_depth;
  external vpx_rational g_timebase;
  @vpx_codec_er_flags_t()
  external int g_error_resilient;
  @ffi.Int32() // vpx_enc_pass
  external int g_pass;
  @ffi.Uint32()
  external int g_lag_in_frames;
  @ffi.Uint32()
  external int rc_dropframe_thresh;
  @ffi.Uint32()
  external int rc_resize_allowed;
  @ffi.Uint32()
  external int rc_scaled_width;
  @ffi.Uint32()
  external int rc_scaled_height;
  @ffi.Uint32()
  external int rc_resize_up_thresh;
  @ffi.Uint32()
  external int rc_resize_down_thresh;
  @ffi.Int32() // vpx_rc_mode
  external int rc_end_usage;
  external vpx_fixed_buf rc_twopass_stats_in;
  external vpx_fixed_buf rc_firstpass_mb_stats_in;
  @ffi.Uint32()
  external int rc_target_bitrate;
  @ffi.Uint32()
  external int rc_min_quantizer;
  @ffi.Uint32()
  external int rc_max_quantizer;
  @ffi.Uint32()
  external int rc_undershoot_pct;
  @ffi.Uint32()
  external int rc_overshoot_pct;
  @ffi.Uint32()
  external int rc_buf_sz;
  @ffi.Uint32()
  external int rc_buf_initial_sz;
  @ffi.Uint32()
  external int rc_buf_optimal_sz;
  @ffi.Uint32()
  external int rc_2pass_vbr_bias_pct;
  @ffi.Uint32()
  external int rc_2pass_vbr_minsection_pct;
  @ffi.Uint32()
  external int rc_2pass_vbr_maxsection_pct;
  @ffi.Uint32()
  external int rc_2pass_vbr_corpus_complexity;
  @ffi.Int32() // vpx_kf_mode
  external int kf_mode;
  @ffi.Uint32()
  external int kf_min_dist;
  @ffi.Uint32()
  external int kf_max_dist;
  @ffi.Uint32()
  external int ss_number_layers;
  @ffi.Array<ffi.Int32>(5)
  external ffi.Array<ffi.Int32> ss_enable_auto_alt_ref;
  @ffi.Array<ffi.Uint32>(5)
  external ffi.Array<ffi.Uint32> ss_target_bitrate;
  @ffi.Uint32()
  external int ts_number_layers;
  @ffi.Array<ffi.Uint32>(5)
  external ffi.Array<ffi.Uint32> ts_target_bitrate;
  @ffi.Array<ffi.Uint32>(5)
  external ffi.Array<ffi.Uint32> ts_rate_decimator;
  @ffi.Uint32()
  external int ts_periodicity;
  @ffi.Array<ffi.Uint32>(16)
  external ffi.Array<ffi.Uint32> ts_layer_id;
  @ffi.Array<ffi.Uint32>(12)
  external ffi.Array<ffi.Uint32> layer_target_bitrate;
  @ffi.Int32()
  external int temporal_layering_mode;
  @ffi.Int32()
  external int use_vizier_rc_params;
  external vpx_rational active_wq_factor;
  external vpx_rational err_per_mb_factor;
  external vpx_rational sr_default_decay_limit;
  external vpx_rational sr_diff_factor;
  external vpx_rational kf_err_per_mb_factor;
  external vpx_rational kf_frame_min_boost_factor;
  external vpx_rational kf_frame_max_boost_first_factor;
  external vpx_rational kf_frame_max_boost_subs_factor;
  external vpx_rational kf_max_total_boost_factor;
  external vpx_rational gf_max_total_boost_factor;
  external vpx_rational gf_frame_max_boost_factor;
  external vpx_rational zm_factor;
  external vpx_rational rd_mult_inter_qp_fac;
  external vpx_rational rd_mult_arf_qp_fac;
  external vpx_rational rd_mult_key_qp_fac;
}

class vpx_codec_dec_cfg extends ffi.Struct {
  @ffi.Uint32()
  external int threads;
  @ffi.Uint32()
  external int w;
  @ffi.Uint32()
  external int h;
}

class vpx_image extends ffi.Struct {
  @ffi.Int32() // vpx_img_fmt_t
  external int fmt;
  @ffi.Int32() // vpx_color_space_t
  external int cs;
  @ffi.Int32() // vpx_color_range_t
  external int range;

  @ffi.Uint32()
  external int w;
  @ffi.Uint32()
  external int h;
  @ffi.Uint32()
  external int bit_depth;

  @ffi.Uint32()
  external int d_w;
  @ffi.Uint32()
  external int d_h;

  @ffi.Uint32()
  external int r_w;
  @ffi.Uint32()
  external int r_h;

  @ffi.Uint32()
  external int x_chroma_shift;
  @ffi.Uint32()
  external int y_chroma_shift;

  @ffi.Array<ffi.Pointer<ffi.Uint8>>(4)
  external ffi.Array<ffi.Pointer<ffi.Uint8>> planes;
  @ffi.Array<ffi.Int32>(4)
  external ffi.Array<ffi.Int32> stride;

  @ffi.Int32()
  external int bps;
  external ffi.Pointer<ffi.Void> user_priv;

  external ffi.Pointer<ffi.Uint8> img_data;
  @ffi.Int32()
  external int img_data_owner;
  @ffi.Int32()
  external int self_allocd;

  external ffi.Pointer<ffi.Void> fb_priv;
}

class vpx_psnr_pkt extends ffi.Struct {
  @ffi.Array<ffi.Uint32>(4)
  external ffi.Array<ffi.Uint32> samples;
  @ffi.Array<ffi.Uint64>(4)
  external ffi.Array<ffi.Uint64> sse;
  @ffi.Array<ffi.Double>(4)
  external ffi.Array<ffi.Double> psnr;
}

// Union for vpx_codec_cx_pkt data
class _VpxCodecCxPktDataUnion extends ffi.Union {
  external _VpxCodecCxPktDataFrame frame;
  external vpx_fixed_buf twopass_stats;
  external vpx_fixed_buf firstpass_mb_stats;
  external vpx_psnr_pkt psnr;
  external vpx_fixed_buf raw;

  @ffi.Array<ffi.Uint8>(128 - ffi.SizeOf<ffi.Int32>()) // pad to 128 bytes, accounting for kind
  external ffi.Array<ffi.Uint8> pad;
}

class _VpxCodecCxPktDataFrame extends ffi.Struct {
  external ffi.Pointer<ffi.Void> buf;
  @ffi.Size()
  external int sz;
  @vpx_codec_pts_t()
  external int pts;
  @ffi.Uint64() // unsigned long
  external int duration;
  @vpx_codec_frame_flags_t()
  external int flags;
  @ffi.Int32()
  external int partition_id;
  @ffi.Array<ffi.Uint32>(5)
  external ffi.Array<ffi.Uint32> width;
  @ffi.Array<ffi.Uint32>(5)
  external ffi.Array<ffi.Uint32> height;
  @ffi.Array<ffi.Uint8>(5)
  external ffi.Array<ffi.Uint8> spatial_layer_encoded;
}

class vpx_codec_cx_pkt extends ffi.Struct {
  @ffi.Int32() // vpx_codec_cx_pkt_kind
  external int kind;
  external _VpxCodecCxPktDataUnion data;
}


// --- Native Function Typedefs ---
typedef _vpx_codec_enc_config_default_native = ffi.Int32 Function(
  ffi.Pointer<vpx_codec_iface_t> iface,
  ffi.Pointer<vpx_codec_enc_cfg> cfg,
  ffi.Uint32 usage,
);
typedef VpxCodecEncConfigDefault = int Function(
  ffi.Pointer<vpx_codec_iface_t> iface,
  ffi.Pointer<vpx_codec_enc_cfg> cfg,
  int usage,
);

typedef _vpx_codec_enc_init_ver_native = ffi.Int32 Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
  ffi.Pointer<vpx_codec_iface_t> iface,
  ffi.Pointer<vpx_codec_enc_cfg> cfg,
  vpx_codec_flags_t flags,
  ffi.Int32 ver,
);
typedef VpxCodecEncInitVer = int Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
  ffi.Pointer<vpx_codec_iface_t> iface,
  ffi.Pointer<vpx_codec_enc_cfg> cfg,
  int flags,
  int ver,
);

typedef _vpx_codec_destroy_native = ffi.Int32 Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
);
typedef VpxCodecDestroy = int Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
);

typedef _vpx_codec_vp8_cx_native = ffi.Pointer<vpx_codec_iface_t> Function();
typedef VpxCodecVp8Cx = ffi.Pointer<vpx_codec_iface_t> Function();

typedef _vpx_codec_vp8_dx_native = ffi.Pointer<vpx_codec_iface_t> Function();
typedef VpxCodecVp8Dx = ffi.Pointer<vpx_codec_iface_t> Function();

typedef _vpx_codec_vp9_cx_native = ffi.Pointer<vpx_codec_iface_t> Function();
typedef VpxCodecVp9Cx = ffi.Pointer<vpx_codec_iface_t> Function();

typedef _vpx_codec_vp9_dx_native = ffi.Pointer<vpx_codec_iface_t> Function();
typedef VpxCodecVp9Dx = ffi.Pointer<vpx_codec_iface_t> Function();


typedef _vpx_img_alloc_native = ffi.Pointer<vpx_image> Function(
  ffi.Pointer<vpx_image> img,
  ffi.Int32 fmt, // vpx_img_fmt_t
  ffi.Uint32 d_w,
  ffi.Uint32 d_h,
  ffi.Uint32 align,
);
typedef VpxImgAlloc = ffi.Pointer<vpx_image> Function(
  ffi.Pointer<vpx_image> img,
  int fmt,
  int d_w,
  int d_h,
  int align,
);

typedef _vpx_codec_get_cx_data_native = ffi.Pointer<vpx_codec_cx_pkt> Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
  ffi.Pointer<vpx_codec_iter_t> iter,
);
typedef VpxCodecGetCxData = ffi.Pointer<vpx_codec_cx_pkt> Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
  ffi.Pointer<vpx_codec_iter_t> iter,
);

typedef _vpx_codec_encode_native = ffi.Int32 Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
  ffi.Pointer<vpx_image> img,
  vpx_codec_pts_t pts,
  ffi.Uint64 duration, // unsigned long
  vpx_enc_frame_flags_t flags,
  vpx_enc_deadline_t deadline,
);
typedef VpxCodecEncode = int Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
  ffi.Pointer<vpx_image> img,
  int pts,
  int duration,
  int flags,
  int deadline,
);

typedef _vpx_codec_dec_init_ver_native = ffi.Int32 Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
  ffi.Pointer<vpx_codec_iface_t> iface,
  ffi.Pointer<vpx_codec_dec_cfg> cfg,
  vpx_codec_flags_t flags,
  ffi.Int32 ver,
);
typedef VpxCodecDecInitVer = int Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
  ffi.Pointer<vpx_codec_iface_t> iface,
  ffi.Pointer<vpx_codec_dec_cfg> cfg,
  int flags,
  int ver,
);

typedef _vpx_codec_decode_native = ffi.Int32 Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
  ffi.Pointer<ffi.Uint8> data,
  ffi.Uint32 data_sz,
  ffi.Pointer<ffi.Void> user_priv,
  ffi.Int64 deadline, // long
);
typedef VpxCodecDecode = int Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
  ffi.Pointer<ffi.Uint8> data,
  int data_sz,
  ffi.Pointer<ffi.Void> user_priv,
  int deadline,
);

typedef _vpx_codec_get_frame_native = ffi.Pointer<vpx_image> Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
  ffi.Pointer<vpx_codec_iter_t> iter,
);
typedef VpxCodecGetFrame = ffi.Pointer<vpx_image> Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
  ffi.Pointer<vpx_codec_iter_t> iter,
);

typedef _vpx_img_free_native = ffi.Void Function(
  ffi.Pointer<vpx_image> img,
);
typedef VpxImgFree = void Function(
  ffi.Pointer<vpx_image> img,
);

typedef _vpx_codec_version_native = ffi.Int32 Function();
typedef VpxCodecVersion = int Function();

typedef _vpx_codec_control_native = ffi.Int32 Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
  ffi.Int32 ctrl_id,
  ffi.Int32 value, // Variable argument for int, adjust for others
);
typedef VpxCodecControl = int Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
  int ctrl_id,
  int value,
);

typedef _vpx_codec_enc_config_set_native = ffi.Int32 Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
  ffi.Pointer<vpx_codec_enc_cfg> cfg,
);
typedef VpxCodecEncConfigSet = int Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
  ffi.Pointer<vpx_codec_enc_cfg> cfg,
);

typedef _vpx_codec_error_native = ffi.Pointer<ffi.Char> Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
);
typedef VpxCodecError = ffi.Pointer<ffi.Char> Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
);

typedef _vpx_codec_err_to_string_native = ffi.Pointer<ffi.Char> Function(
  ffi.Int32 err, // vpx_codec_err_t
);
typedef VpxCodecErrToString = ffi.Pointer<ffi.Char> Function(
  int err,
);

typedef _vpx_codec_error_detail_native = ffi.Pointer<ffi.Char> Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
);
typedef VpxCodecErrorDetail = ffi.Pointer<ffi.Char> Function(
  ffi.Pointer<vpx_codec_ctx> ctx,
);


// lib/vpx_library.dart
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:webrtc_vpx_ffi/src/vpx_bindings.dart';
import 'package:webrtc_vpx_ffi/src/vpx_exception.dart';
import 'package:webrtc_vpx_ffi/src/vpx_enums.dart';

/// A class to manage the libvpx dynamic library and its FFI bindings.
class VpxLibrary {
  static const int SUPPORTED_VERSION = 69375; // Corresponds to VPX_ENCODER_ABI_VERSION 36 and VPX_DECODER_ABI_VERSION 12
                                             // This value is `VPX_ENCODER_ABI_VERSION << 16 | VPX_DECODER_ABI_VERSION`
                                             // from vpx_codec_version()
  static const int VPX_ENCODER_ABI_VERSION = 36;
  static const int VPX_DECODER_ABI_VERSION = 12;
  static const int VPX_DL_REALTIME = 1;
  static const int PACKET_MAX = 1300; // From PHP's Vpx.php

  late final ffi.DynamicLibrary _libvpx;

  // --- FFI Function Pointers ---
  late final VpxCodecEncConfigDefault vpx_codec_enc_config_default;
  late final VpxCodecEncInitVer vpx_codec_enc_init_ver;
  late final VpxCodecDestroy vpx_codec_destroy;
  late final VpxCodecVp8Cx vpx_codec_vp8_cx;
  late final VpxCodecVp8Dx vpx_codec_vp8_dx;
  late final VpxCodecVp9Cx vpx_codec_vp9_cx;
  late final VpxCodecVp9Dx vpx_codec_vp9_dx;
  late final VpxImgAlloc vpx_img_alloc;
  late final VpxCodecGetCxData vpx_codec_get_cx_data;
  late final VpxCodecEncode vpx_codec_encode;
  late final VpxCodecDecInitVer vpx_codec_dec_init_ver;
  late final VpxCodecDecode vpx_codec_decode;
  late final VpxCodecGetFrame vpx_codec_get_frame;
  late final VpxImgFree vpx_img_free;
  late final VpxCodecVersion vpx_codec_version;
  late final VpxCodecControl vpx_codec_control_;
  late final VpxCodecEncConfigSet vpx_codec_enc_config_set;
  late final VpxCodecError vpx_codec_error;
  late final VpxCodecErrToString vpx_codec_err_to_string;
  late final VpxCodecErrorDetail vpx_codec_error_detail;


  /// Private constructor for singleton pattern.
  VpxLibrary._internal() {
    _libvpx = _openLibvpx();
    _resolveFunctions();
  }

  /// The single instance of [VpxLibrary].
  static final VpxLibrary instance = VpxLibrary._internal();

  /// Opens the libvpx dynamic library based on the current platform.
  ffi.DynamicLibrary _openLibvpx() {
    String libPath;
    if (Platform.isWindows) {
      // Common names for libvpx DLL on Windows
      final candidates = [
        'libvpx.dll',
        'libvpx-1.dll', // Often the actual file name from MinGW/MSYS2
        'vpx.dll',
      ];
      libPath = candidates.firstWhere(
        (name) => File(name).existsSync() || File('mingw64/bin/$name').existsSync(), // Check current dir and common MSYS2 path
        orElse: () => candidates.first, // Fallback to first name, hoping it's in PATH
      );
    } else if (Platform.isMacOS) {
      libPath = 'libvpx.dylib';
    } else if (Platform.isLinux) {
      libPath = 'libvpx.so';
    } else {
      throw VpxException('Unsupported platform: ${Platform.operatingSystem}');
    }

    try {
      return ffi.DynamicLibrary.open(libPath);
    } on ArgumentError catch (e) {
      final String installHint;
      if (Platform.isWindows) {
        installHint = '''
Download and install libvpx for Windows manually or using MSYS2:
  pacman -S mingw-w64-x86_64-libvpx
Or download prebuilt binaries from trusted sources.
Make sure vpx-*.dll is available in your PATH or specify the full path.
''';
      } else if (Platform.isMacOS) {
        installHint = '''
Install libvpx on macOS using Homebrew:
  brew install libvpx
If you already have it installed but not linked:
  brew link libvpx --force
''';
      } else if (Platform.isLinux) {
        installHint = '''
Install libvpx development packages on Linux.
For Debian/Ubuntu:
  sudo apt update
  sudo apt install libvpx-dev
For Fedora/RHEL:
  sudo dnf install libvpx-devel
If your distribution provides an outdated version, consider building libvpx manually from:
  https://chromium.googlesource.com/webm/libvpx
''';
      } else {
        installHint = "Please install libvpx (VP8/VP9 codec library) with development headers and shared libraries available. See https://chromium.googlesource.com/webm/libvpx/ for source instructions.";
      }

      throw VpxException(
        'Failed to load VPX shared library "$libPath": ${e.message}\n\nInstallation instructions:\n$installHint',
        errorCode: VpxCodecErrT.VPX_CODEC_ERROR.value,
      );
    }
  }

  /// Resolves all native functions from the loaded dynamic library.
  void _resolveFunctions() {
    vpx_codec_enc_config_default = _libvpx.lookupFunction<
        _vpx_codec_enc_config_default_native,
        VpxCodecEncConfigDefault>('vpx_codec_enc_config_default');
    vpx_codec_enc_init_ver = _libvpx.lookupFunction<
        _vpx_codec_enc_init_ver_native,
        VpxCodecEncInitVer>('vpx_codec_enc_init_ver');
    vpx_codec_destroy = _libvpx.lookupFunction<
        _vpx_codec_destroy_native,
        VpxCodecDestroy>('vpx_codec_destroy');
    vpx_codec_vp8_cx = _libvpx.lookupFunction<
        _vpx_codec_vp8_cx_native,
        VpxCodecVp8Cx>('vpx_codec_vp8_cx');
    vpx_codec_vp8_dx = _libvpx.lookupFunction<
        _vpx_codec_vp8_dx_native,
        VpxCodecVp8Dx>('vpx_codec_vp8_dx');
    vpx_codec_vp9_cx = _libvpx.lookupFunction<
        _vpx_codec_vp9_cx_native,
        VpxCodecVp9Cx>('vpx_codec_vp9_cx');
    vpx_codec_vp9_dx = _libvpx.lookupFunction<
        _vpx_codec_vp9_dx_native,
        VpxCodecVp9Dx>('vpx_codec_vp9_dx');
    vpx_img_alloc = _libvpx.lookupFunction<
        _vpx_img_alloc_native,
        VpxImgAlloc>('vpx_img_alloc');
    vpx_codec_get_cx_data = _libvpx.lookupFunction<
        _vpx_codec_get_cx_data_native,
        VpxCodecGetCxData>('vpx_codec_get_cx_data');
    vpx_codec_encode = _libvpx.lookupFunction<
        _vpx_codec_encode_native,
        VpxCodecEncode>('vpx_codec_encode');
    vpx_codec_dec_init_ver = _libvpx.lookupFunction<
        _vpx_codec_dec_init_ver_native,
        VpxCodecDecInitVer>('vpx_codec_dec_init_ver');
    vpx_codec_decode = _libvpx.lookupFunction<
        _vpx_codec_decode_native,
        VpxCodecDecode>('vpx_codec_decode');
    vpx_codec_get_frame = _libvpx.lookupFunction<
        _vpx_codec_get_frame_native,
        VpxCodecGetFrame>('vpx_codec_get_frame');
    vpx_img_free = _libvpx.lookupFunction<
        _vpx_img_free_native,
        VpxImgFree>('vpx_img_free');
    vpx_codec_version = _libvpx.lookupFunction<
        _vpx_codec_version_native,
        VpxCodecVersion>('vpx_codec_version');
    vpx_codec_control_ = _libvpx.lookupFunction<
        _vpx_codec_control_native,
        VpxCodecControl>('vpx_codec_control_');
    vpx_codec_enc_config_set = _libvpx.lookupFunction<
        _vpx_codec_enc_config_set_native,
        VpxCodecEncConfigSet>('vpx_codec_enc_config_set');
    vpx_codec_error = _libvpx.lookupFunction<
        _vpx_codec_error_native,
        VpxCodecError>('vpx_codec_error');
    vpx_codec_err_to_string = _libvpx.lookupFunction<
        _vpx_codec_err_to_string_native,
        VpxCodecErrToString>('vpx_codec_err_to_string');
    vpx_codec_error_detail = _libvpx.lookupFunction<
        _vpx_codec_error_detail_native,
        VpxCodecErrorDetail>('vpx_codec_error_detail');

    _checkVersion();
  }

  /// Checks if the loaded libvpx version is supported.
  void _checkVersion() {
    final version = vpx_codec_version();
    // The PHP code checks for exact match, which is unusual for ABI versions.
    // A more robust check might be `version >= SUPPORTED_VERSION`.
    // Sticking to PHP logic for now.
    if (version != SUPPORTED_VERSION) {
      throw VpxException(
        'The loaded libvpx library version is not supported. '
        'Required version is $SUPPORTED_VERSION, detected version is $version.',
        errorCode: VpxCodecErrT.VPX_CODEC_ABI_MISMATCH.value,
      );
    }
  }

  /// Returns the pointer to the codec interface function (e.g., vpx_codec_vp8_cx).
  ffi.Pointer<vpx_codec_iface_t> getCodecInterface(BriefInterface interface) {
    switch (interface) {
      case BriefInterface.VP8_CX:
        return vpx_codec_vp8_cx();
      case BriefInterface.VP8_DX:
        return vpx_codec_vp8_dx();
      case BriefInterface.VP9_CX:
        return vpx_codec_vp9_cx();
      case BriefInterface.VP9_DX:
        return vpx_codec_vp9_dx();
    }
  }
}
