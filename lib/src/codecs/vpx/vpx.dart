// vpx_ffi_bindings.dart
// This file contains Dart FFI bindings for the VP8/VP9 codec library (libvpx).
// It maps C types, structs, enums, and function signatures to their Dart equivalents.

import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'dart:ffi';

// --- Typedefs for common C integer types ---
typedef Uint8 = ffi.Uint8;
typedef Int8 = ffi.Int8;
typedef Uint16 = ffi.Uint16;
typedef Int16 = ffi.Int16;
typedef Uint32 = ffi.Uint32;
typedef Int32 = ffi.Int32;
typedef Uint64 = ffi.Uint64;
typedef Int64 = ffi.Int64;
typedef Size = ffi.Size; // Maps to size_t
typedef PtrDiff = ffi.IntPtr; // Maps to ptrdiff_t

// --- vpx_image.h bindings ---

/// List of supported image formats (vpx_img_fmt)
class VpxImgFmt {
  static const int VPX_IMG_FMT_NONE = 0;
  static const int VPX_IMG_FMT_RGB24 = 1;
  static const int VPX_IMG_FMT_RGB32 = 2;
  static const int VPX_IMG_FMT_RGB565 = 3;
  static const int VPX_IMG_FMT_RGB555 = 4;
  static const int VPX_IMG_FMT_UYVY = 5;
  static const int VPX_IMG_FMT_YUY2 = 6;
  static const int VPX_IMG_FMT_YVYU = 7;
  static const int VPX_IMG_FMT_BGR24 = 8;
  static const int VPX_IMG_FMT_RGB32_LE = 9;
  static const int VPX_IMG_FMT_ARGB = 10;
  static const int VPX_IMG_FMT_ARGB_LE = 11;
  static const int VPX_IMG_FMT_RGB565_LE = 12;
  static const int VPX_IMG_FMT_RGB555_LE = 13;

  // Planar formats with flags
  static const int VPX_IMG_FMT_PLANAR = 0x100;
  static const int VPX_IMG_FMT_UV_FLIP = 0x200;
  static const int VPX_IMG_FMT_HAS_ALPHA = 0x400;
  static const int VPX_IMG_FMT_HIGHBITDEPTH = 0x800;

  static const int VPX_IMG_FMT_YV12 =
      VPX_IMG_FMT_PLANAR | VPX_IMG_FMT_UV_FLIP | 1;
  static const int VPX_IMG_FMT_I420 = VPX_IMG_FMT_PLANAR | 2;
  static const int VPX_IMG_FMT_VPXYV12 =
      VPX_IMG_FMT_PLANAR | VPX_IMG_FMT_UV_FLIP | 3;
  static const int VPX_IMG_FMT_VPXI420 = VPX_IMG_FMT_PLANAR | 4;
  static const int VPX_IMG_FMT_I422 = VPX_IMG_FMT_PLANAR | 5;
  static const int VPX_IMG_FMT_I444 = VPX_IMG_FMT_PLANAR | 6;
  static const int VPX_IMG_FMT_I440 = VPX_IMG_FMT_PLANAR | 7;
  static const int VPX_IMG_FMT_444A =
      VPX_IMG_FMT_PLANAR | VPX_IMG_FMT_HAS_ALPHA | 6;
  static const int VPX_IMG_FMT_I42016 =
      VPX_IMG_FMT_I420 | VPX_IMG_FMT_HIGHBITDEPTH;
  static const int VPX_IMG_FMT_I42216 =
      VPX_IMG_FMT_I422 | VPX_IMG_FMT_HIGHBITDEPTH;
  static const int VPX_IMG_FMT_I44416 =
      VPX_IMG_FMT_I444 | VPX_IMG_FMT_HIGHBITDEPTH;
  static const int VPX_IMG_FMT_I44016 =
      VPX_IMG_FMT_I440 | VPX_IMG_FMT_HIGHBITDEPTH;
}

/// List of supported color spaces (vpx_color_space)
class VpxColorSpace {
  static const int VPX_CS_UNKNOWN = 0;
  static const int VPX_CS_BT_601 = 1;
  static const int VPX_CS_BT_709 = 2;
  static const int VPX_CS_SMPTE_170 = 3;
  static const int VPX_CS_SMPTE_240 = 4;
  static const int VPX_CS_BT_2020 = 5;
  static const int VPX_CS_RESERVED = 6;
  static const int VPX_CS_SRGB = 7;
}

/// List of supported color range (vpx_color_range)
class VpxColorRange {
  static const int VPX_CR_STUDIO_RANGE = 0;
  static const int VPX_CR_FULL_RANGE = 1;
}

/// Representation of a rectangle on a surface (vpx_image_rect_t)
final class VpxImageRect extends ffi.Struct {
  @Uint32()
  external int x;
  @Uint32()
  external int y;
  @Uint32()
  external int w;
  @Uint32()
  external int h;
}

/// Image Descriptor (vpx_image_t)
final class VpxImage extends ffi.Struct {
  @Int32()
  external int fmt; // VpxImgFmt enum
  @Int32()
  external int cs; // VpxColorSpace enum
  @Int32()
  external int range; // VpxColorRange enum

  // Image storage dimensions
  @Uint32()
  external int w;
  @Uint32()
  external int h;
  @Uint32()
  external int bit_depth;

  // Image display dimensions
  @Uint32()
  external int d_w;
  @Uint32()
  external int d_h;

  // Image intended rendering dimensions
  @Uint32()
  external int r_w;
  @Uint32()
  external int r_h;

  // Chroma subsampling info
  @Uint32()
  external int x_chroma_shift;
  @Uint32()
  external int y_chroma_shift;

  // Image data pointers. (planes)
  // Use Array<Pointer<Uint8>> or separate Pointers, for simplicity and
  // direct mapping, using separate Pointers.
  // C: unsigned char *planes[4];
  external Pointer<Uint8> planes0;
  external Pointer<Uint8> planes1;
  external Pointer<Uint8> planes2;
  external Pointer<Uint8> planes3;

  // Stride between rows for each plane
  // C: int stride[4];
  @Int32()
  external int stride0;
  @Int32()
  external int stride1;
  @Int32()
  external int stride2;
  @Int32()
  external int stride3;

  @Int32()
  external int bps; // bits per sample (for packed formats)

  // User private data
  external Pointer<Void> user_priv;

  // Private members (internal use)
  external Pointer<Uint8> img_data;
  @Int32()
  external int img_data_owner;
  @Int32()
  external int self_allocd;

  external Pointer<Void>
      fb_priv; // Frame buffer data associated with the image.
}

// vpx_image.h Functions
typedef vpx_img_alloc_native = Pointer<VpxImage> Function(
  Pointer<VpxImage> img,
  Int32 fmt,
  Uint32 d_w,
  Uint32 d_h,
  Uint32 align,
);
typedef vpx_img_alloc_dart = Pointer<VpxImage> Function(
  Pointer<VpxImage> img,
  int fmt,
  int d_w,
  int d_h,
  int align,
);

typedef vpx_img_wrap_native = Pointer<VpxImage> Function(
  Pointer<VpxImage> img,
  Int32 fmt,
  Uint32 d_w,
  Uint32 d_h,
  Uint32 align,
  Pointer<Uint8> img_data,
);
typedef vpx_img_wrap_dart = Pointer<VpxImage> Function(
  Pointer<VpxImage> img,
  int fmt,
  int d_w,
  int d_h,
  int align,
  Pointer<Uint8> img_data,
);

typedef vpx_img_set_rect_native = Int32 Function(
  Pointer<VpxImage> img,
  Uint32 x,
  Uint32 y,
  Uint32 w,
  Uint32 h,
);
typedef vpx_img_set_rect_dart = int Function(
  Pointer<VpxImage> img,
  int x,
  int y,
  int w,
  int h,
);

typedef vpx_img_flip_native = Void Function(
  Pointer<VpxImage> img,
);
typedef vpx_img_flip_dart = void Function(
  Pointer<VpxImage> img,
);

typedef vpx_img_free_native = Void Function(
  Pointer<VpxImage> img,
);
typedef vpx_img_free_dart = void Function(
  Pointer<VpxImage> img,
);

// --- vpx_frame_buffer.h bindings ---

// Max work buffers
const int VPX_MAXIMUM_WORK_BUFFERS = 8;
const int VP9_MAXIMUM_REF_BUFFERS = 8;

/// External frame buffer (vpx_codec_frame_buffer_t)
final class VpxCodecFrameBuffer extends ffi.Struct {
  external Pointer<Uint8> data;
  @Size()
  external int size;
  external Pointer<Void> priv;
}

/// get frame buffer callback prototype (vpx_get_frame_buffer_cb_fn_t)
typedef VpxGetFrameBufferCbFnNative = Int32 Function(
  Pointer<Void> priv,
  Size min_size,
  Pointer<VpxCodecFrameBuffer> fb,
);
typedef VpxGetFrameBufferCbFn = int Function(
  Pointer<Void> priv,
  int min_size,
  Pointer<VpxCodecFrameBuffer> fb,
);

/// release frame buffer callback prototype (vpx_release_frame_buffer_cb_fn_t)
typedef VpxReleaseFrameBufferCbFnNative = Int32 Function(
  Pointer<Void> priv,
  Pointer<VpxCodecFrameBuffer> fb,
);
typedef VpxReleaseFrameBufferCbFn = int Function(
  Pointer<Void> priv,
  Pointer<VpxCodecFrameBuffer> fb,
);

// --- vpx_codec.h bindings ---

/// Algorithm return codes (vpx_codec_err_t)
class VpxCodecErr {
  static const int VPX_CODEC_OK = 0;
  static const int VPX_CODEC_ERROR = 1;
  static const int VPX_CODEC_MEM_ERROR = 2;
  static const int VPX_CODEC_ABI_MISMATCH = 3;
  static const int VPX_CODEC_INCAPABLE = 4;
  static const int VPX_CODEC_UNSUP_BITSTREAM = 5;
  static const int VPX_CODEC_UNSUP_FEATURE = 6;
  static const int VPX_CODEC_CORRUPT_FRAME = 7;
  static const int VPX_CODEC_INVALID_PARAM = 8;
  static const int VPX_CODEC_LIST_END = 9;
}

/// Codec capabilities bitfield (vpx_codec_caps_t)
typedef VpxCodecCaps = ffi.Int64;
const int VPX_CODEC_CAP_DECODER = 0x1;
const int VPX_CODEC_CAP_ENCODER = 0x2;

/// Initialization-time Feature Enabling (vpx_codec_flags_t)
typedef VpxCodecFlags = ffi.Int64;
const int VPX_CODEC_USE_PSNR = 0x10000;
const int VPX_CODEC_USE_OUTPUT_PARTITION = 0x20000;
const int VPX_CODEC_USE_HIGHBITDEPTH = 0x40000;

/// Codec interface structure (vpx_codec_iface_t) - Opaque
final class VpxCodecIface extends ffi.Opaque {}

/// Codec private data structure (vpx_codec_priv_t) - Opaque
final class VpxCodecPriv extends ffi.Opaque {}

/// Iterator (vpx_codec_iter_t) - Opaque pointer
typedef VpxCodecIter = Pointer<Void>;

/// Bit depth for codec (vpx_bit_depth_t)
class VpxBitDepth {
  static const int VPX_BITS_8 = 8;
  static const int VPX_BITS_10 = 10;
  static const int VPX_BITS_12 = 12;
}

/// Rational Number (vpx_rational_t)
final class VpxRational extends ffi.Struct {
  @Int32()
  external int num;
  @Int32()
  external int den;
}

/// Generic fixed size buffer structure (vpx_fixed_buf_t)
final class VpxFixedBuf extends ffi.Struct {
  external Pointer<Void> buf;
  @Size()
  external int sz;
}

/// Time Stamp Type (vpx_codec_pts_t)
typedef VpxCodecPts = ffi.Int64;

/// Compressed Frame Flags (vpx_codec_frame_flags_t)
typedef VpxCodecFrameFlags = ffi.Uint32;
const int VPX_FRAME_IS_KEY = 0x1;
const int VPX_FRAME_IS_DROPPABLE = 0x2;
const int VPX_FRAME_IS_INVISIBLE = 0x4;
const int VPX_FRAME_IS_FRAGMENT = 0x8;

/// Error Resilient flags (vpx_codec_er_flags_t)
typedef VpxCodecErFlags = ffi.Uint32;
const int VPX_ERROR_RESILIENT_DEFAULT = 0x1;
const int VPX_ERROR_RESILIENT_PARTITIONS = 0x2;

/// Encoder output packet variants (vpx_codec_cx_pkt_kind)
class VpxCodecCxPktKind {
  static const int VPX_CODEC_CX_FRAME_PKT = 0;
  static const int VPX_CODEC_STATS_PKT = 1;
  static const int VPX_CODEC_FPMB_STATS_PKT = 2;
  static const int VPX_CODEC_PSNR_PKT = 3;
  static const int VPX_CODEC_CUSTOM_PKT = 256;
}

/// PSNR statistics for this frame (vpx_psnr_pkt)
final class VpxPsnrPkt extends ffi.Struct {
  @Array(4)
  external ffi.Array<Uint32> samples; // samples[4]
  @Array(4)
  external ffi.Array<Uint64> sse; // sse[4]
  @Array(4)
  external ffi.Array<ffi.Double> psnr; // psnr[4]
}

/// Data for compressed frame packet (anonymous struct within vpx_codec_cx_pkt)
final class VpxCodecCxFramePkt extends ffi.Struct {
  external Pointer<Void> buf;
  @Size()
  external int sz;
  @Int64()
  external int pts;
  @Uint32()
  external int duration; // unsigned long
  @Uint32()
  external int flags; // vpx_codec_frame_flags_t
  @Int32()
  external int partition_id;
}

/// Encoder output packet (vpx_codec_cx_pkt_t)
/// This is a union in C, so we'll use an array of bytes for the data field
/// and rely on `kind` to interpret it.
final class VpxCodecCxPkt extends ffi.Struct {
  @Int32()
  external int kind; // VpxCodecCxPktKind enum

  @Array(128 -
      4) // Total size of union is 128 bytes, subtract size of kind (4 bytes for int32)
  external ffi.Array<Uint8> data; // Represents the union content
}

/// Codec context structure (vpx_codec_ctx_t)
final class VpxCodecCtx extends ffi.Struct {
  external Pointer<Int8> name; // const char*
  external Pointer<VpxCodecIface> iface;
  @Int32()
  external int err; // vpx_codec_err_t
  external Pointer<Int8> err_detail; // const char*
  @Int64()
  external int init_flags; // vpx_codec_flags_t

  // Union config: We'll just use a generic pointer here as config structures vary.
  external Pointer<Void>
      config_ptr; // Points to either vpx_codec_dec_cfg_t or vpx_codec_enc_cfg_t

  external Pointer<VpxCodecPriv> priv;
}

/// Codec Versioning Functions
typedef vpx_codec_version_native = Int32 Function();
typedef vpx_codec_version_dart = int Function();

typedef vpx_codec_version_str_native = Pointer<Int8> Function();
typedef vpx_codec_version_str_dart = Pointer<Int8> Function();

typedef vpx_codec_version_extra_str_native = Pointer<Int8> Function();
typedef vpx_codec_version_extra_str_dart = Pointer<Int8> Function();

typedef vpx_codec_build_config_native = Pointer<Int8> Function();
typedef vpx_codec_build_config_dart = Pointer<Int8> Function();

typedef vpx_codec_iface_name_native = Pointer<Int8> Function(
  Pointer<VpxCodecIface> iface,
);
typedef vpx_codec_iface_name_dart = Pointer<Int8> Function(
  Pointer<VpxCodecIface> iface,
);

typedef vpx_codec_err_to_string_native = Pointer<Int8> Function(
  Int32 err,
);
typedef vpx_codec_err_to_string_dart = Pointer<Int8> Function(
  int err,
);

typedef vpx_codec_error_native = Pointer<Int8> Function(
  Pointer<VpxCodecCtx> ctx,
);
typedef vpx_codec_error_dart = Pointer<Int8> Function(
  Pointer<VpxCodecCtx> ctx,
);

typedef vpx_codec_error_detail_native = Pointer<Int8> Function(
  Pointer<VpxCodecCtx> ctx,
);
typedef vpx_codec_error_detail_dart = Pointer<Int8> Function(
  Pointer<VpxCodecCtx> ctx,
);

typedef vpx_codec_destroy_native = Int32 Function(
  Pointer<VpxCodecCtx> ctx,
);
typedef vpx_codec_destroy_dart = int Function(
  Pointer<VpxCodecCtx> ctx,
);

typedef vpx_codec_get_caps_native = Int64 Function(
  Pointer<VpxCodecIface> iface,
);
typedef vpx_codec_get_caps_dart = int Function(
  Pointer<VpxCodecIface> iface,
);

// vpx_codec_control_ is a variadic function. FFI typically handles this
// by defining specific types for each control ID or by using a generic
// Pointer<Void> for the variadic argument.
// For now, we'll define a generic control function. Specific control IDs
// with their argument types will need separate `lookupFunction` calls if
// stricter type checking is desired.
typedef vpx_codec_control_native = Int32 Function(
  Pointer<VpxCodecCtx> ctx,
  Int32 ctrl_id,
  Pointer<Void> data, // generic for variadic arg
);
typedef vpx_codec_control_dart = int Function(
  Pointer<VpxCodecCtx> ctx,
  int ctrl_id,
  Pointer<Void> data,
);

// --- vpx_decoder.h bindings ---

// Decoder Capabilities Flags
const int VPX_CODEC_CAP_PUT_SLICE = 0x10000;
const int VPX_CODEC_CAP_PUT_FRAME = 0x20000;
const int VPX_CODEC_CAP_POSTPROC = 0x40000;
const int VPX_CODEC_CAP_ERROR_CONCEALMENT = 0x80000;
const int VPX_CODEC_CAP_INPUT_FRAGMENTS = 0x100000;
const int VPX_CODEC_CAP_FRAME_THREADING = 0x200000;
const int VPX_CODEC_CAP_EXTERNAL_FRAME_BUFFER = 0x400000;

// Decoder Usage Flags
const int VPX_CODEC_USE_POSTPROC = 0x10000;
const int VPX_CODEC_USE_ERROR_CONCEALMENT = 0x20000;
const int VPX_CODEC_USE_INPUT_FRAGMENTS = 0x40000;
const int VPX_CODEC_USE_FRAME_THREADING = 0x80000;

/// Stream properties (vpx_codec_stream_info_t)
final class VpxCodecStreamInfo extends ffi.Struct {
  @Uint32()
  external int sz;
  @Uint32()
  external int w;
  @Uint32()
  external int h;
  @Uint32()
  external int is_kf;
}

/// Initialization Configurations (vpx_codec_dec_cfg_t)
final class VpxCodecDecCfg extends ffi.Struct {
  @Uint32()
  external int threads;
  @Uint32()
  external int w;
  @Uint32()
  external int h;
}

// vpx_decoder.h Functions
typedef vpx_codec_dec_init_ver_native = Int32 Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<VpxCodecIface> iface,
  Pointer<VpxCodecDecCfg> cfg,
  Int64 flags, // vpx_codec_flags_t
  Int32 ver,
);
typedef vpx_codec_dec_init_ver_dart = int Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<VpxCodecIface> iface,
  Pointer<VpxCodecDecCfg> cfg,
  int flags,
  int ver,
);

typedef vpx_codec_peek_stream_info_native = Int32 Function(
  Pointer<VpxCodecIface> iface,
  Pointer<Uint8> data,
  Uint32 data_sz,
  Pointer<VpxCodecStreamInfo> si,
);
typedef vpx_codec_peek_stream_info_dart = int Function(
  Pointer<VpxCodecIface> iface,
  Pointer<Uint8> data,
  int data_sz,
  Pointer<VpxCodecStreamInfo> si,
);

typedef vpx_codec_get_stream_info_native = Int32 Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<VpxCodecStreamInfo> si,
);
typedef vpx_codec_get_stream_info_dart = int Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<VpxCodecStreamInfo> si,
);

typedef vpx_codec_decode_native = Int32 Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<Uint8> data,
  Uint32 data_sz,
  Pointer<Void> user_priv,
  Int64 deadline, // long
);
typedef vpx_codec_decode_dart = int Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<Uint8> data,
  int data_sz,
  Pointer<Void> user_priv,
  int deadline,
);

typedef vpx_codec_get_frame_native = Pointer<VpxImage> Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<VpxCodecIter> iter,
);
typedef vpx_codec_get_frame_dart = Pointer<VpxImage> Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<VpxCodecIter> iter,
);

/// put frame callback prototype (vpx_codec_put_frame_cb_fn_t)
typedef VpxCodecPutFrameCbFnNative = Void Function(
  Pointer<Void> user_priv,
  Pointer<VpxImage> img,
);
typedef VpxCodecPutFrameCbFn = void Function(
  Pointer<Void> user_priv,
  Pointer<VpxImage> img,
);

typedef vpx_codec_register_put_frame_cb_native = Int32 Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<NativeFunction<VpxCodecPutFrameCbFnNative>> cb,
  Pointer<Void> user_priv,
);
typedef vpx_codec_register_put_frame_cb_dart = int Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<NativeFunction<VpxCodecPutFrameCbFnNative>> cb,
  Pointer<Void> user_priv,
);

/// put slice callback prototype (vpx_codec_put_slice_cb_fn_t)
typedef VpxCodecPutSliceCbFnNative = Void Function(
  Pointer<Void> user_priv,
  Pointer<VpxImage> img,
  Pointer<VpxImageRect> valid,
  Pointer<VpxImageRect> update,
);
typedef VpxCodecPutSliceCbFn = void Function(
  Pointer<Void> user_priv,
  Pointer<VpxImage> img,
  Pointer<VpxImageRect> valid,
  Pointer<VpxImageRect> update,
);

typedef vpx_codec_register_put_slice_cb_native = Int32 Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<NativeFunction<VpxCodecPutSliceCbFnNative>> cb,
  Pointer<Void> user_priv,
);
typedef vpx_codec_register_put_slice_cb_dart = int Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<NativeFunction<VpxCodecPutSliceCbFnNative>> cb,
  Pointer<Void> user_priv,
);

typedef vpx_codec_set_frame_buffer_functions_native = Int32 Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<NativeFunction<VpxGetFrameBufferCbFnNative>> cb_get,
  Pointer<NativeFunction<VpxReleaseFrameBufferCbFnNative>> cb_release,
  Pointer<Void> cb_priv,
);
typedef vpx_codec_set_frame_buffer_functions_dart = int Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<NativeFunction<VpxGetFrameBufferCbFnNative>> cb_get,
  Pointer<NativeFunction<VpxReleaseFrameBufferCbFnNative>> cb_release,
  Pointer<Void> cb_priv,
);

// --- vpx_encoder.h bindings ---

const int VPX_TS_MAX_PERIODICITY = 16;
const int VPX_TS_MAX_LAYERS = 5;
const int VPX_MAX_LAYERS = 12; // 3 temporal + 4 spatial layers
const int VPX_SS_MAX_LAYERS = 5;
const int VPX_SS_DEFAULT_LAYERS = 1;

/// Multi-pass Encoding Pass (vpx_enc_pass)
class VpxEncPass {
  static const int VPX_RC_ONE_PASS = 0;
  static const int VPX_RC_FIRST_PASS = 1;
  static const int VPX_RC_LAST_PASS = 2;
}

/// Rate control mode (vpx_rc_mode)
class VpxRcMode {
  static const int VPX_VBR = 0;
  static const int VPX_CBR = 1;
  static const int VPX_CQ = 2;
  static const int VPX_Q = 3;
}

/// Keyframe placement mode (vpx_kf_mode)
class VpxKfMode {
  static const int VPX_KF_FIXED = 0; // deprecated, implies VPX_KF_DISABLED
  static const int VPX_KF_AUTO = 1;
  static const int VPX_KF_DISABLED = 0; // alias for VPX_KF_FIXED
}

/// Encoded Frame Flags (vpx_enc_frame_flags_t)
typedef VpxEncFrameFlags = ffi.Int64; // long in C is Int64 in Dart FFI
const int VPX_EFLAG_FORCE_KF = 1 << 0;

/// Encoder configuration structure (vpx_codec_enc_cfg_t)
final class VpxCodecEncCfg extends ffi.Struct {
  @Uint32()
  external int g_usage;
  @Uint32()
  external int g_threads;
  @Uint32()
  external int g_profile;
  @Uint32()
  external int g_w;
  @Uint32()
  external int g_h;
  @Int32()
  external int g_bit_depth; // vpx_bit_depth_t enum
  @Uint32()
  external int g_input_bit_depth;
  external VpxRational g_timebase;
  @Uint32()
  external int g_error_resilient; // vpx_codec_er_flags_t
  @Int32()
  external int g_pass; // vpx_enc_pass enum
  @Uint32() // unsigned int
  external int g_lag_in_frames;

  // rate control settings (rc)
  @Uint32()
  external int rc_dropframe_thresh;
  @Uint32()
  external int rc_resize_allowed;
  @Uint32()
  external int rc_scaled_width;
  @Uint32()
  external int rc_scaled_height;
  @Uint32()
  external int rc_resize_up_thresh;
  @Uint32()
  external int rc_resize_down_thresh;
  @Int32()
  external int rc_end_usage; // vpx_rc_mode enum
  external VpxFixedBuf rc_twopass_stats_in;
  external VpxFixedBuf rc_firstpass_mb_stats_in;
  @Uint32()
  external int rc_target_bitrate;

  // quantizer settings
  @Uint32()
  external int rc_min_quantizer;
  @Uint32()
  external int rc_max_quantizer;

  // bitrate tolerance
  @Uint32()
  external int rc_undershoot_pct;
  @Uint32()
  external int rc_overshoot_pct;

  // decoder buffer model parameters
  @Uint32()
  external int rc_buf_sz;
  @Uint32()
  external int rc_buf_initial_sz;
  @Uint32()
  external int rc_buf_optimal_sz;

  // 2 pass rate control parameters
  @Uint32()
  external int rc_2pass_vbr_bias_pct;
  @Uint32()
  external int rc_2pass_vbr_minsection_pct;
  @Uint32()
  external int rc_2pass_vbr_maxsection_pct;

  // keyframing settings (kf)
  @Int32()
  external int kf_mode; // vpx_kf_mode enum
  @Uint32()
  external int kf_min_dist;
  @Uint32()
  external int kf_max_dist;

  // Spatial scalability settings (ss)
  @Uint32()
  external int ss_number_layers;
  @Array(VPX_SS_MAX_LAYERS)
  external ffi.Array<Int32>
      ss_enable_auto_alt_ref; // int ss_enable_auto_alt_ref[VPX_SS_MAX_LAYERS];
  @Array(VPX_SS_MAX_LAYERS)
  external ffi.Array<Uint32>
      ss_target_bitrate; // unsigned int ss_target_bitrate[VPX_SS_MAX_LAYERS];

  // Temporal scalability settings (ts)
  @Uint32()
  external int ts_number_layers;
  @Array(VPX_TS_MAX_LAYERS)
  external ffi.Array<Uint32>
      ts_target_bitrate; // unsigned int ts_target_bitrate[VPX_TS_MAX_LAYERS];
  @Array(VPX_TS_MAX_LAYERS)
  external ffi.Array<Uint32>
      ts_rate_decimator; // unsigned int ts_rate_decimator[VPX_TS_MAX_LAYERS];
  @Uint32()
  external int ts_periodicity;
  @Array(VPX_TS_MAX_PERIODICITY)
  external ffi.Array<Uint32>
      ts_layer_id; // unsigned int ts_layer_id[VPX_TS_MAX_PERIODICITY];

  @Array(VPX_MAX_LAYERS)
  external ffi.Array<Uint32>
      layer_target_bitrate; // unsigned int layer_target_bitrate[VPX_MAX_LAYERS];

  @Int32()
  external int temporal_layering_mode; // int
}

/// vp9 svc extra configure parameters (vpx_svc_extra_cfg_t)
final class VpxSvcExtraCfg extends ffi.Struct {
  @Array(VPX_MAX_LAYERS)
  external ffi.Array<Int32> max_quantizers;
  @Array(VPX_MAX_LAYERS)
  external ffi.Array<Int32> min_quantizers;
  @Array(VPX_MAX_LAYERS)
  external ffi.Array<Int32> scaling_factor_num;
  @Array(VPX_MAX_LAYERS)
  external ffi.Array<Int32> scaling_factor_den;
  @Int32()
  external int temporal_layering_mode;
}

// vpx_encoder.h Functions
typedef vpx_codec_enc_init_ver_native = Int32 Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<VpxCodecIface> iface,
  Pointer<VpxCodecEncCfg> cfg,
  Int64 flags, // vpx_codec_flags_t
  Int32 ver,
);
typedef vpx_codec_enc_init_ver_dart = int Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<VpxCodecIface> iface,
  Pointer<VpxCodecEncCfg> cfg,
  int flags,
  int ver,
);

typedef vpx_codec_enc_init_multi_ver_native = Int32 Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<VpxCodecIface> iface,
  Pointer<VpxCodecEncCfg> cfg,
  Int32 num_enc,
  Int64 flags,
  Pointer<VpxRational> dsf,
  Int32 ver,
);
typedef vpx_codec_enc_init_multi_ver_dart = int Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<VpxCodecIface> iface,
  Pointer<VpxCodecEncCfg> cfg,
  int num_enc,
  int flags,
  Pointer<VpxRational> dsf,
  int ver,
);

typedef vpx_codec_enc_config_default_native = Int32 Function(
  Pointer<VpxCodecIface> iface,
  Pointer<VpxCodecEncCfg> cfg,
  Uint32 reserved,
);
typedef vpx_codec_enc_config_default_dart = int Function(
  Pointer<VpxCodecIface> iface,
  Pointer<VpxCodecEncCfg> cfg,
  int reserved,
);

typedef vpx_codec_enc_config_set_native = Int32 Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<VpxCodecEncCfg> cfg,
);
typedef vpx_codec_enc_config_set_dart = int Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<VpxCodecEncCfg> cfg,
);

typedef vpx_codec_get_global_headers_native = Pointer<VpxFixedBuf> Function(
  Pointer<VpxCodecCtx> ctx,
);
typedef vpx_codec_get_global_headers_dart = Pointer<VpxFixedBuf> Function(
  Pointer<VpxCodecCtx> ctx,
);

const int VPX_DL_REALTIME = 1;
const int VPX_DL_GOOD_QUALITY = 1000000;
const int VPX_DL_BEST_QUALITY = 0;

typedef vpx_codec_encode_native = Int32 Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<VpxImage> img,
  Int64 pts, // vpx_codec_pts_t
  Uint32 duration, // unsigned long
  Int64 flags, // vpx_enc_frame_flags_t
  Uint32 deadline, // unsigned long
);
typedef vpx_codec_encode_dart = int Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<VpxImage> img,
  int pts,
  int duration,
  int flags,
  int deadline,
);

typedef vpx_codec_set_cx_data_buf_native = Int32 Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<VpxFixedBuf> buf,
  Uint32 pad_before,
  Uint32 pad_after,
);
typedef vpx_codec_set_cx_data_buf_dart = int Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<VpxFixedBuf> buf,
  int pad_before,
  int pad_after,
);

typedef vpx_codec_get_cx_data_native = Pointer<VpxCodecCxPkt> Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<VpxCodecIter> iter,
);
typedef vpx_codec_get_cx_data_dart = Pointer<VpxCodecCxPkt> Function(
  Pointer<VpxCodecCtx> ctx,
  Pointer<VpxCodecIter> iter,
);

typedef vpx_codec_get_preview_frame_native = Pointer<VpxImage> Function(
  Pointer<VpxCodecCtx> ctx,
);
typedef vpx_codec_get_preview_frame_dart = Pointer<VpxImage> Function(
  Pointer<VpxCodecCtx> ctx,
);

// --- vp8.h bindings (Common) ---

/// Control functions (vp8_com_control_id)
class Vp8ComControlId {
  static const int VP8_SET_REFERENCE = 1;
  static const int VP8_COPY_REFERENCE = 2;
  static const int VP8_SET_POSTPROC = 3;
  static const int VP8_SET_DBG_COLOR_REF_FRAME = 4;
  static const int VP8_SET_DBG_COLOR_MB_MODES = 5;
  static const int VP8_SET_DBG_COLOR_B_MODES = 6;
  static const int VP8_SET_DBG_DISPLAY_MV = 7;
  static const int VP9_GET_REFERENCE = 128;
  static const int VP8_COMMON_CTRL_ID_MAX = 129;
  static const int VP8_DECODER_CTRL_ID_START = 256;
}

/// Post process flags (vp8_postproc_level)
class Vp8PostProcLevel {
  static const int VP8_NOFILTERING = 0;
  static const int VP8_DEBLOCK = 1 << 0;
  static const int VP8_DEMACROBLOCK = 1 << 1;
  static const int VP8_ADDNOISE = 1 << 2;
  static const int VP8_DEBUG_TXT_FRAME_INFO = 1 << 3;
  static const int VP8_DEBUG_TXT_MBLK_MODES = 1 << 4;
  static const int VP8_DEBUG_TXT_DC_DIFF = 1 << 5;
  static const int VP8_DEBUG_TXT_RATE_INFO = 1 << 6;
  static const int VP8_MFQE = 1 << 10;
}

/// Post processing configuration (vp8_postproc_cfg_t)
final class Vp8PostprocCfg extends ffi.Struct {
  @Int32()
  external int post_proc_flag; // vp8_postproc_level combination
  @Int32()
  external int deblocking_level;
  @Int32()
  external int noise_level;
}

/// Reference frame type (vpx_ref_frame_type_t)
class VpxRefFrameType {
  static const int VP8_LAST_FRAME = 1;
  static const int VP8_GOLD_FRAME = 2;
  static const int VP8_ALTR_FRAME = 4;
}

/// Reference frame data struct (vpx_ref_frame_t)
final class VpxRefFrame extends ffi.Struct {
  @Int32()
  external int frame_type; // vpx_ref_frame_type_t
  external VpxImage img; // Nested struct, not pointer
}

/// VP9 specific reference frame data struct (vp9_ref_frame_t)
final class Vp9RefFrame extends ffi.Struct {
  @Int32()
  external int idx;
  external VpxImage img; // Nested struct, not pointer
}

// --- vp8cx.h bindings (Encoder Specific) ---

// VPx encoder control functions (vp8e_enc_control_id)
class Vp8eEncControlId {
  static const int VP8E_SET_ROI_MAP = 8;
  static const int VP8E_SET_ACTIVEMAP = 9; // Follows SET_ROI_MAP, so 9
  static const int VP8E_SET_SCALEMODE = 11;
  static const int VP8E_SET_CPUUSED = 13;
  static const int VP8E_SET_ENABLEAUTOALTREF = 14; // Follows SET_CPUUSED
  static const int VP8E_SET_NOISE_SENSITIVITY =
      15; // Follows SET_ENABLEAUTOALTREF
  static const int VP8E_SET_SHARPNESS = 16; // Follows SET_NOISE_SENSITIVITY
  static const int VP8E_SET_STATIC_THRESHOLD = 17; // Follows SET_SHARPNESS
  static const int VP8E_SET_TOKEN_PARTITIONS =
      18; // Follows SET_STATIC_THRESHOLD
  static const int VP8E_GET_LAST_QUANTIZER = 19; // Follows SET_TOKEN_PARTITIONS
  static const int VP8E_GET_LAST_QUANTIZER_64 =
      20; // Follows GET_LAST_QUANTIZER
  static const int VP8E_SET_ARNR_MAXFRAMES =
      21; // Follows GET_LAST_QUANTIZER_64
  static const int VP8E_SET_ARNR_STRENGTH = 22; // Follows SET_ARNR_MAXFRAMES
  static const int VP8E_SET_ARNR_TYPE = 23; // Deprecated, but still a value
  static const int VP8E_SET_TUNING = 24;
  static const int VP8E_SET_CQ_LEVEL = 25;
  static const int VP8E_SET_MAX_INTRA_BITRATE_PCT = 26;
  static const int VP8E_SET_FRAME_FLAGS = 27;

  // VP9 specific
  static const int VP9E_SET_MAX_INTER_BITRATE_PCT = 28;
  static const int VP9E_SET_GF_CBR_BOOST_PCT = 29;
  static const int VP8E_SET_TEMPORAL_LAYER_ID =
      30; // VP8 specific, but value is after VP9 ones in vp8cx.h enum
  static const int VP8E_SET_SCREEN_CONTENT_MODE = 31;
  static const int VP9E_SET_LOSSLESS = 32;
  static const int VP9E_SET_TILE_COLUMNS = 33;
  static const int VP9E_SET_TILE_ROWS = 34;
  static const int VP9E_SET_FRAME_PARALLEL_DECODING = 35;
  static const int VP9E_SET_AQ_MODE = 36;
  static const int VP9E_SET_FRAME_PERIODIC_BOOST = 37;
  static const int VP9E_SET_NOISE_SENSITIVITY = 38;
  static const int VP9E_SET_SVC = 39;
  static const int VP9E_SET_SVC_PARAMETERS = 40;
  static const int VP9E_SET_SVC_LAYER_ID = 41;
  static const int VP9E_SET_TUNE_CONTENT = 42;
  static const int VP9E_GET_SVC_LAYER_ID = 43;
  static const int VP9E_REGISTER_CX_CALLBACK = 44;
  static const int VP9E_SET_COLOR_SPACE = 45;
  static const int VP9E_SET_TEMPORAL_LAYERING_MODE = 46;
  static const int VP9E_SET_MIN_GF_INTERVAL = 47;
  static const int VP9E_SET_MAX_GF_INTERVAL = 48;
  static const int VP9E_GET_ACTIVEMAP = 49;
  static const int VP9E_SET_COLOR_RANGE = 50;
  static const int VP9E_SET_SVC_REF_FRAME_CONFIG = 51;
  static const int VP9E_SET_RENDER_SIZE = 52;
  static const int VP9E_SET_TARGET_LEVEL = 53;
  static const int VP9E_GET_LEVEL = 54;
}

/// vpx 1-D scaling mode (vpx_scaling_mode_1d / VPX_SCALING_MODE)
class VpxScalingMode {
  static const int VP8E_NORMAL = 0;
  static const int VP8E_FOURFIVE = 1;
  static const int VP8E_THREEFIVE = 2;
  static const int VP8E_ONETWO = 3;
}

/// Temporal layering mode enum for VP9 SVC (vp9e_temporal_layering_mode)
class Vp9eTemporalLayeringMode {
  static const int VP9E_TEMPORAL_LAYERING_MODE_NOLAYERING = 0;
  static const int VP9E_TEMPORAL_LAYERING_MODE_BYPASS = 1;
  static const int VP9E_TEMPORAL_LAYERING_MODE_0101 = 2;
  static const int VP9E_TEMPORAL_LAYERING_MODE_0212 = 3;
}

/// vpx region of interest map (vpx_roi_map_t)
final class VpxRoiMap extends ffi.Struct {
  external Pointer<Uint8> roi_map;
  @Uint32()
  external int rows;
  @Uint32()
  external int cols;
  @Array(4)
  external ffi.Array<Int32> delta_q; // int delta_q[4];
  @Array(4)
  external ffi.Array<Int32> delta_lf; // int delta_lf[4];
  @Array(4)
  external ffi.Array<Uint32>
      static_threshold; // unsigned int static_threshold[4];
}

/// vpx active region map (vpx_active_map_t)
final class VpxActiveMap extends ffi.Struct {
  external Pointer<Uint8> active_map;
  @Uint32()
  external int rows;
  @Uint32()
  external int cols;
}

/// vpx image scaling mode (vpx_scaling_mode_t)
final class VpxScalingModeStruct extends ffi.Struct {
  @Int32()
  external int h_scaling_mode; // VPX_SCALING_MODE enum
  @Int32()
  external int v_scaling_mode; // VPX_SCALING_MODE enum
}

/// VP8 token partition mode (vp8e_token_partitions)
class Vp8eTokenPartitions {
  static const int VP8_ONE_TOKENPARTITION = 0;
  static const int VP8_TWO_TOKENPARTITION = 1;
  static const int VP8_FOUR_TOKENPARTITION = 2;
  static const int VP8_EIGHT_TOKENPARTITION = 3;
}

/// VP9 encoder content type (vp9e_tune_content)
class Vp9eTuneContent {
  static const int VP9E_CONTENT_DEFAULT = 0;
  static const int VP9E_CONTENT_SCREEN = 1;
  static const int VP9E_CONTENT_INVALID = 2;
}

/// VP8 model tuning parameters (vp8e_tuning)
class Vp8eTuning {
  static const int VP8_TUNE_PSNR = 0;
  static const int VP8_TUNE_SSIM = 1;
}

/// vp9 svc layer parameters (vpx_svc_layer_id_t)
final class VpxSvcLayerId extends ffi.Struct {
  @Int32()
  external int spatial_layer_id;
  @Int32()
  external int temporal_layer_id;
}

/// vp9 svc frame flag parameters (vpx_svc_ref_frame_config_t)
final class VpxSvcRefFrameConfig extends ffi.Struct {
  @Array(VPX_TS_MAX_LAYERS)
  external ffi.Array<Int32> frame_flags;
  @Array(VPX_TS_MAX_LAYERS)
  external ffi.Array<Int32> lst_fb_idx;
  @Array(VPX_TS_MAX_LAYERS)
  external ffi.Array<Int32> gld_fb_idx;
  @Array(VPX_TS_MAX_LAYERS)
  external ffi.Array<Int32> alt_fb_idx;
}

// --- vp8dx.h bindings (Decoder Specific) ---

/// VP8 decoder control functions (vp8_dec_control_id)
class Vp8DecControlId {
  static const int VP8D_GET_LAST_REF_UPDATES =
      Vp8ComControlId.VP8_DECODER_CTRL_ID_START;
  static const int VP8D_GET_FRAME_CORRUPTED =
      Vp8ComControlId.VP8_DECODER_CTRL_ID_START + 1; // Increment from previous
  static const int VP8D_GET_LAST_REF_USED =
      Vp8ComControlId.VP8_DECODER_CTRL_ID_START + 2;
  static const int VPXD_SET_DECRYPTOR =
      Vp8ComControlId.VP8_DECODER_CTRL_ID_START + 3;
  static const int VP8D_SET_DECRYPTOR = VPXD_SET_DECRYPTOR; // Alias

  // VP9 specific
  static const int VP9D_GET_FRAME_SIZE =
      Vp8ComControlId.VP8_DECODER_CTRL_ID_START + 4;
  static const int VP9D_GET_DISPLAY_SIZE =
      Vp8ComControlId.VP8_DECODER_CTRL_ID_START + 5;
  static const int VP9D_GET_BIT_DEPTH =
      Vp8ComControlId.VP8_DECODER_CTRL_ID_START + 6;
  static const int VP9_SET_BYTE_ALIGNMENT =
      Vp8ComControlId.VP8_DECODER_CTRL_ID_START + 7;
  static const int VP9_INVERT_TILE_DECODE_ORDER =
      Vp8ComControlId.VP8_DECODER_CTRL_ID_START + 8;
  static const int VP9_SET_SKIP_LOOP_FILTER =
      Vp8ComControlId.VP8_DECODER_CTRL_ID_START + 9;

  static const int VP8_DECODER_CTRL_ID_MAX =
      Vp8ComControlId.VP8_DECODER_CTRL_ID_START + 10;
}

/// Decrypt callback (vpx_decrypt_cb)
typedef VpxDecryptCbNative = Void Function(
  Pointer<Void> decrypt_state,
  Pointer<Uint8> input,
  Pointer<Uint8> output,
  Int32 count,
);
typedef VpxDecryptCb = void Function(
  Pointer<Void> decrypt_state,
  Pointer<Uint8> input,
  Pointer<Uint8> output,
  int count,
);

/// Structure to hold decryption state (vpx_decrypt_init)
final class VpxDecryptInit extends ffi.Struct {
  external Pointer<NativeFunction<VpxDecryptCbNative>> decrypt_cb;
  external Pointer<Void> decrypt_state;
}

/// A deprecated alias for vpx_decrypt_init (vp8_decrypt_init)
// typedef VpxDecryptInit Vp8DecryptInit; // Not needed, just use VpxDecryptInit

// --- VPx Codec Interface Class ---

/// A class to encapsulate the native library and provide high-level access
/// to VPx codec functions.
class VpxCodec {
  late final DynamicLibrary _lib;

  // Image functions
  late final vpx_img_alloc_dart imgAlloc;
  late final vpx_img_wrap_dart imgWrap;
  late final vpx_img_set_rect_dart imgSetRect;
  late final vpx_img_flip_dart imgFlip;
  late final vpx_img_free_dart imgFree;

  // Common Codec functions
  late final vpx_codec_version_dart codecVersion;
  late final vpx_codec_version_str_dart codecVersionStr;
  late final vpx_codec_version_extra_str_dart codecVersionExtraStr;
  late final vpx_codec_build_config_dart codecBuildConfig;
  late final vpx_codec_iface_name_dart codecIfaceName;
  late final vpx_codec_err_to_string_dart codecErrToString;
  late final vpx_codec_error_dart codecError;
  late final vpx_codec_error_detail_dart codecErrorDetail;
  late final vpx_codec_destroy_dart codecDestroy;
  late final vpx_codec_get_caps_dart codecGetCaps;
  late final vpx_codec_control_dart codecControl;

  // Decoder functions
  late final vpx_codec_dec_init_ver_dart codecDecInitVer;
  late final vpx_codec_peek_stream_info_dart codecPeekStreamInfo;
  late final vpx_codec_get_stream_info_dart codecGetStreamInfo;
  late final vpx_codec_decode_dart codecDecode;
  late final vpx_codec_get_frame_dart codecGetFrame;
  late final vpx_codec_register_put_frame_cb_dart codecRegisterPutFrameCb;
  late final vpx_codec_register_put_slice_cb_dart codecRegisterPutSliceCb;
  late final vpx_codec_set_frame_buffer_functions_dart
      codecSetFrameBufferFunctions;

  // Encoder functions
  late final vpx_codec_enc_init_ver_dart codecEncInitVer;
  late final vpx_codec_enc_init_multi_ver_dart codecEncInitMultiVer;
  late final vpx_codec_enc_config_default_dart codecEncConfigDefault;
  late final vpx_codec_enc_config_set_dart codecEncConfigSet;
  late final vpx_codec_get_global_headers_dart codecGetGlobalHeaders;
  late final vpx_codec_encode_dart codecEncode;
  late final vpx_codec_set_cx_data_buf_dart codecSetCxDataBuf;
  late final vpx_codec_get_cx_data_dart codecGetCxData;
  late final vpx_codec_get_preview_frame_dart codecGetPreviewFrame;

  /// Initializes the VPx codec bindings by loading the native library.
  /// Provide the path to the native library (e.g., 'libvpx.so', 'libvpx.dylib', 'vpx.dll').
  VpxCodec(String libraryPath) {
    _lib = DynamicLibrary.open(libraryPath);
    _bindFunctions();
  }

  void _bindFunctions() {
    // Image functions
    imgAlloc = _lib.lookupFunction<vpx_img_alloc_native, vpx_img_alloc_dart>(
      'vpx_img_alloc',
    );
    imgWrap = _lib.lookupFunction<vpx_img_wrap_native, vpx_img_wrap_dart>(
      'vpx_img_wrap',
    );
    imgSetRect =
        _lib.lookupFunction<vpx_img_set_rect_native, vpx_img_set_rect_dart>(
      'vpx_img_set_rect',
    );
    imgFlip = _lib.lookupFunction<vpx_img_flip_native, vpx_img_flip_dart>(
      'vpx_img_flip',
    );
    imgFree = _lib.lookupFunction<vpx_img_free_native, vpx_img_free_dart>(
      'vpx_img_free',
    );

    // Common Codec functions
    codecVersion =
        _lib.lookupFunction<vpx_codec_version_native, vpx_codec_version_dart>(
      'vpx_codec_version',
    );
    codecVersionStr = _lib.lookupFunction<vpx_codec_version_str_native,
        vpx_codec_version_str_dart>(
      'vpx_codec_version_str',
    );
    codecVersionExtraStr = _lib.lookupFunction<
        vpx_codec_version_extra_str_native, vpx_codec_version_extra_str_dart>(
      'vpx_codec_version_extra_str',
    );
    codecBuildConfig = _lib.lookupFunction<vpx_codec_build_config_native,
        vpx_codec_build_config_dart>(
      'vpx_codec_build_config',
    );
    codecIfaceName = _lib
        .lookupFunction<vpx_codec_iface_name_native, vpx_codec_iface_name_dart>(
      'vpx_codec_iface_name',
    );
    codecErrToString = _lib.lookupFunction<vpx_codec_err_to_string_native,
        vpx_codec_err_to_string_dart>(
      'vpx_codec_err_to_string',
    );
    codecError =
        _lib.lookupFunction<vpx_codec_error_native, vpx_codec_error_dart>(
      'vpx_codec_error',
    );
    codecErrorDetail = _lib.lookupFunction<vpx_codec_error_detail_native,
        vpx_codec_error_detail_dart>(
      'vpx_codec_error_detail',
    );
    codecDestroy =
        _lib.lookupFunction<vpx_codec_destroy_native, vpx_codec_destroy_dart>(
      'vpx_codec_destroy',
    );
    codecGetCaps =
        _lib.lookupFunction<vpx_codec_get_caps_native, vpx_codec_get_caps_dart>(
      'vpx_codec_get_caps',
    );
    codecControl =
        _lib.lookupFunction<vpx_codec_control_native, vpx_codec_control_dart>(
      'vpx_codec_control_', // Note: the actual C function is vpx_codec_control_
    );

    // Decoder functions
    codecDecInitVer = _lib.lookupFunction<vpx_codec_dec_init_ver_native,
        vpx_codec_dec_init_ver_dart>(
      'vpx_codec_dec_init_ver',
    );
    codecPeekStreamInfo = _lib.lookupFunction<vpx_codec_peek_stream_info_native,
        vpx_codec_peek_stream_info_dart>(
      'vpx_codec_peek_stream_info',
    );
    codecGetStreamInfo = _lib.lookupFunction<vpx_codec_get_stream_info_native,
        vpx_codec_get_stream_info_dart>(
      'vpx_codec_get_stream_info',
    );
    codecDecode =
        _lib.lookupFunction<vpx_codec_decode_native, vpx_codec_decode_dart>(
      'vpx_codec_decode',
    );
    codecGetFrame = _lib
        .lookupFunction<vpx_codec_get_frame_native, vpx_codec_get_frame_dart>(
      'vpx_codec_get_frame',
    );
    codecRegisterPutFrameCb = _lib.lookupFunction<
        vpx_codec_register_put_frame_cb_native,
        vpx_codec_register_put_frame_cb_dart>(
      'vpx_codec_register_put_frame_cb',
    );
    codecRegisterPutSliceCb = _lib.lookupFunction<
        vpx_codec_register_put_slice_cb_native,
        vpx_codec_register_put_slice_cb_dart>(
      'vpx_codec_register_put_slice_cb',
    );
    codecSetFrameBufferFunctions = _lib.lookupFunction<
        vpx_codec_set_frame_buffer_functions_native,
        vpx_codec_set_frame_buffer_functions_dart>(
      'vpx_codec_set_frame_buffer_functions',
    );

    // Encoder functions
    codecEncInitVer = _lib.lookupFunction<vpx_codec_enc_init_ver_native,
        vpx_codec_enc_init_ver_dart>(
      'vpx_codec_enc_init_ver',
    );
    codecEncInitMultiVer = _lib.lookupFunction<
        vpx_codec_enc_init_multi_ver_native, vpx_codec_enc_init_multi_ver_dart>(
      'vpx_codec_enc_init_multi_ver',
    );
    codecEncConfigDefault = _lib.lookupFunction<
        vpx_codec_enc_config_default_native, vpx_codec_enc_config_default_dart>(
      'vpx_codec_enc_config_default',
    );
    codecEncConfigSet = _lib.lookupFunction<vpx_codec_enc_config_set_native,
        vpx_codec_enc_config_set_dart>(
      'vpx_codec_enc_config_set',
    );
    codecGetGlobalHeaders = _lib.lookupFunction<
        vpx_codec_get_global_headers_native, vpx_codec_get_global_headers_dart>(
      'vpx_codec_get_global_headers',
    );
    codecEncode =
        _lib.lookupFunction<vpx_codec_encode_native, vpx_codec_encode_dart>(
      'vpx_codec_encode',
    );
    codecSetCxDataBuf = _lib.lookupFunction<vpx_codec_set_cx_data_buf_native,
        vpx_codec_set_cx_data_buf_dart>(
      'vpx_codec_set_cx_data_buf',
    );
    codecGetCxData = _lib.lookupFunction<vpx_codec_get_cx_data_native,
        vpx_codec_get_cx_data_dart>(
      'vpx_codec_get_cx_data',
    );
    codecGetPreviewFrame = _lib.lookupFunction<
        vpx_codec_get_preview_frame_native, vpx_codec_get_preview_frame_dart>(
      'vpx_codec_get_preview_frame',
    );
  }

  // --- VP8/VP9 Codec Interfaces (from vp8cx.h, vp8dx.h) ---

  // These are extern global variables in C. You need to get their pointers.
  // Example:
  // extern vpx_codec_iface_t  vpx_codec_vp8_cx_algo;
  // extern vpx_codec_iface_t *vpx_codec_vp8_cx(void);
  // In Dart, you would typically look up the function that returns the interface.

  // Example for getting VP8 encoder interface
  Pointer<VpxCodecIface> vpxCodecVp8Cx() {
    final vpx_codec_vp8_cx_native = _lib.lookupFunction<
        Pointer<VpxCodecIface> Function(), Pointer<VpxCodecIface> Function()>(
      'vpx_codec_vp8_cx',
    );
    return vpx_codec_vp8_cx_native();
  }

  // Example for getting VP9 encoder interface
  Pointer<VpxCodecIface> vpxCodecVp9Cx() {
    final vpx_codec_vp9_cx_native = _lib.lookupFunction<
        Pointer<VpxCodecIface> Function(), Pointer<VpxCodecIface> Function()>(
      'vpx_codec_vp9_cx',
    );
    return vpx_codec_vp9_cx_native();
  }

  // Example for getting VP8 decoder interface
  Pointer<VpxCodecIface> vpxCodecVp8Dx() {
    final vpx_codec_vp8_dx_native = _lib.lookupFunction<
        Pointer<VpxCodecIface> Function(), Pointer<VpxCodecIface> Function()>(
      'vpx_codec_vp8_dx',
    );
    return vpx_codec_vp8_dx_native();
  }

  // Example for getting VP9 decoder interface
  Pointer<VpxCodecIface> vpxCodecVp9Dx() {
    final vpx_codec_vp9_dx_native = _lib.lookupFunction<
        Pointer<VpxCodecIface> Function(), Pointer<VpxCodecIface> Function()>(
      'vpx_codec_vp9_dx',
    );
    return vpx_codec_vp9_dx_native();
  }
}

// Helper to determine the correct library path for different platforms
String getLibvpxPath() {
  if (Platform.isLinux || Platform.isAndroid) {
    return 'libvpx.so';
  } else if (Platform.isMacOS || Platform.isIOS) {
    return 'libvpx.dylib';
  } else if (Platform.isWindows) {
    return 'assets/codecs/libvpx.dll';
  } else {
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}

// Example Usage (conceptual, not part of the binding code itself)
void main() {
  // Assuming libvpx is available in a standard system path or specified here
  final vpx = VpxCodec(getLibvpxPath());

  print('VPX Version: ${vpx.codecVersion()}');
  print('VPX Version String: ${vpx.codecVersionStr()}');

  // Example: Initialize a VP8 encoder
  final encoderIface = vpx.vpxCodecVp8Cx();
  final encoderCtx = calloc<VpxCodecCtx>();
  final encCfg = calloc<VpxCodecEncCfg>();

  var result = vpx.codecEncConfigDefault(encoderIface, encCfg, 0);
  if (result == VpxCodecErr.VPX_CODEC_OK) {
    print('Default encoder config obtained.');
    encCfg.ref.g_w = 640;
    encCfg.ref.g_h = 480;
    encCfg.ref.rc_target_bitrate = 200; // 200 kbps

    result = vpx.codecEncInitVer(
        encoderCtx,
        encoderIface,
        encCfg,
        0,
        (3 +
            5)); // VPX_ENCODER_ABI_VERSION (from vpx_encoder.h, which is 5 + VPX_CODEC_ABI_VERSION)
    // Note: Actual ABI version should be dynamically retrieved or hardcoded from the exact C header.
    // For this example, 5 + VPX_CODEC_ABI_VERSION where VPX_CODEC_ABI_VERSION = 3 + VPX_IMAGE_ABI_VERSION(4) = 7
    // So, 5 + 7 = 12.

    if (result == VpxCodecErr.VPX_CODEC_OK) {
      print('VP8 Encoder initialized successfully.');
      // Proceed with encoding frames...
    } else {
      print('Failed to initialize VP8 Encoder: ${vpx.codecError(encoderCtx)}');
    }
  } else {
    // print(
    //     'Failed to get default encoder config: ${vpx.codecErrToString(result).toDartString()}');
    print(
        'Failed to get default encoder config: ${vpx.codecErrToString(result)}');
  }

  // Clean up
  vpx.codecDestroy(encoderCtx);
  calloc.free(encoderCtx);
  calloc.free(encCfg);

  // Example: Initialize a VP8 decoder
  final decoderIface = vpx.vpxCodecVp8Dx();
  final decoderCtx = calloc<VpxCodecCtx>();
  final decCfg = calloc<VpxCodecDecCfg>();

  result = vpx.codecDecInitVer(
      decoderCtx,
      decoderIface,
      decCfg,
      0,
      (3 +
          (3 +
              4))); // VPX_DECODER_ABI_VERSION (from vpx_decoder.h, which is 3 + VPX_CODEC_ABI_VERSION)
  // VPX_CODEC_ABI_VERSION = 3 + VPX_IMAGE_ABI_VERSION(4) = 7
  // So, 3 + 7 = 10.

  if (result == VpxCodecErr.VPX_CODEC_OK) {
    print('VP8 Decoder initialized successfully.');
    // Proceed with decoding frames...
  } else {
    print('Failed to initialize VP8 Decoder: ${vpx.codecError(decoderCtx)}');
  }

  // Clean up
  vpx.codecDestroy(decoderCtx);
  calloc.free(decoderCtx);
  calloc.free(decCfg);
}
