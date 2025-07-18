// vpx_codec.dart

import 'dart:ffi';
import 'package:ffi/ffi.dart';

// Assuming vpx_image.h provides VpxImage and VpxImageAbiVersion
// For demonstration, we'll use a placeholder for VpxImage
// You would typically generate this from vpx_image.h
import 'vpx_image.dart'; // This file would contain VpxImage bindings.

/// Current ABI version number
/// If this file is altered in any way that changes the ABI, this value
/// must be bumped. Examples include, but are not limited to, changing
/// types, removing or reassigning enums, adding/removing/rearranging
/// fields to structures
const int VPX_CODEC_ABI_VERSION = 4 + VPX_IMAGE_ABI_VERSION;

/// Algorithm return codes
enum VpxCodecErr {
  /// Operation completed without error
  ok,

  /// Unspecified error
  error,

  /// Memory operation failed
  memError,

  /// ABI version mismatch
  abiMismatch,

  /// Algorithm does not have required capability
  incapable,

  /// The given bitstream is not supported.
  ///
  /// The bitstream was unable to be parsed at the highest level. The decoder
  /// is unable to proceed. This error SHOULD be treated as fatal to the
  /// stream.
  unsupBitstream,

  /// Encoded bitstream uses an unsupported feature
  ///
  /// The decoder does not implement a feature required by the encoder. This
  /// return code should only be used for features that prevent future
  /// pictures from being properly decoded. This error MAY be treated as
  /// fatal to the stream or MAY be treated as fatal to the current GOP.
  unsupFeature,

  /// The coded data for this stream is corrupt or incomplete
  ///
  /// There was a problem decoding the current frame. This return code
  /// should only be used for failures that prevent future pictures from
  /// being properly decoded. This error MAY be treated as fatal to the
  /// stream or MAY be treated as fatal to the current GOP. If decoding
  /// is continued for the current GOP, artifacts may be present.
  corruptFrame,

  /// An application-supplied parameter is not valid.
  invalidParam,

  /// An iterator reached the end of list.
  listEnd,
}

/// Helper extension to convert int to VpxCodecErr
extension VpxCodecErrExtension on int {
  VpxCodecErr toVpxCodecErr() {
    switch (this) {
      case 0:
        return VpxCodecErr.ok;
      case 1:
        return VpxCodecErr.error;
      case 2:
        return VpxCodecErr.memError;
      case 3:
        return VpxCodecErr.abiMismatch;
      case 4:
        return VpxCodecErr.incapable;
      case 5:
        return VpxCodecErr.unsupBitstream;
      case 6:
        return VpxCodecErr.unsupFeature;
      case 7:
        return VpxCodecErr.corruptFrame;
      case 8:
        return VpxCodecErr.invalidParam;
      case 9:
        return VpxCodecErr.listEnd;
      default:
        throw ArgumentError('Invalid VpxCodecErr value: $this');
    }
  }
}

/// Codec capabilities bitfield
///
/// Each codec advertises the capabilities it supports as part of its
/// VpxCodecIface structure. Capabilities are extra interfaces
/// or functionality, and are not required to be supported.
///
/// The available flags are specified by VPX_CODEC_CAP_* defines.
typedef VpxCodecCaps = Int64; // C 'long' typically maps to Int64

const int VPX_CODEC_CAP_DECODER = 0x1; /// Is a decoder
const int VPX_CODEC_CAP_ENCODER = 0x2; /// Is an encoder
const int VPX_CODEC_CAP_HIGHBITDEPTH = 0x4; /// Can support images at greater than 8 bitdepth.

/// Initialization-time Feature Enabling
///
/// Certain codec features must be known at initialization time, to allow for
/// proper memory allocation.
///
/// The available flags are specified by VPX_CODEC_USE_* defines.
typedef VpxCodecFlags = Int64; // C 'long' typically maps to Int64

/// Codec interface structure.
///
/// Contains function pointers and other data private to the codec
/// implementation. This structure is opaque to the application.
class VpxCodecIface extends Opaque {}

/// Codec private data structure.
///
/// Contains data private to the codec implementation. This structure is opaque
/// to the application.
class VpxCodecPriv extends Opaque {}

/// Iterator
///
/// Opaque storage used for iterating over lists.
typedef VpxCodecIter = Pointer<Void>;

/// Codec context structure
///
/// All codecs MUST support this context structure fully. In general,
/// this data should be considered private to the codec algorithm, and
/// not be manipulated or examined by the calling application. Applications
/// may reference the 'name' member to get a printable description of the
/// algorithm.
class VpxCodecCtx extends Struct {
  external Pointer<Int8> name; // const char *
  external Pointer<VpxCodecIface> iface; // vpx_codec_iface_t *
  @Int32()
  external int err; // vpx_codec_err_t (enum mapped to int)
  external Pointer<Int8> err_detail; // const char *
  @Int64()
  external int init_flags; // vpx_codec_flags_t (long mapped to Int64)

  // Union for config. In Dart FFI, you'd typically define separate
  // structs for dec and enc configs and use a void pointer or separate
  // fields if you need to access both. For simplicity, we'll expose 'raw'.
  external Pointer<Void> config_raw; // const void *raw

  external Pointer<VpxCodecPriv> priv; // vpx_codec_priv_t *

  VpxCodecErr get error => err.toVpxCodecErr();
}

/// Bit depth for codec
///
/// This enumeration determines the bit depth of the codec.
enum VpxBitDepth {
  bits8, // = 8
  bits10, // = 10
  bits12, // = 12
}

/// Helper extension to convert int to VpxBitDepth
extension VpxBitDepthExtension on int {
  VpxBitDepth toVpxBitDepth() {
    switch (this) {
      case 8:
        return VpxBitDepth.bits8;
      case 10:
        return VpxBitDepth.bits10;
      case 12:
        return VpxBitDepth.bits12;
      default:
        throw ArgumentError('Invalid VpxBitDepth value: $this');
    }
  }
}

// Function prototypes
typedef _vpx_codec_version_C = Int32 Function();
typedef _vpx_codec_version_Dart = int Function();

typedef _vpx_codec_version_str_C = Pointer<Int8> Function();
typedef _vpx_codec_version_str_Dart = Pointer<Int8> Function();

typedef _vpx_codec_version_extra_str_C = Pointer<Int8> Function();
typedef _vpx_codec_version_extra_str_Dart = Pointer<Int8> Function();

typedef _vpx_codec_build_config_C = Pointer<Int8> Function();
typedef _vpx_codec_build_config_Dart = Pointer<Int8> Function();

typedef _vpx_codec_iface_name_C = Pointer<Int8> Function(Pointer<VpxCodecIface> iface);
typedef _vpx_codec_iface_name_Dart = Pointer<Int8> Function(Pointer<VpxCodecIface> iface);

typedef _vpx_codec_err_to_string_C = Pointer<Int8> Function(Int32 err);
typedef _vpx_codec_err_to_string_Dart = Pointer<Int8> Function(int err);

typedef _vpx_codec_error_C = Pointer<Int8> Function(Pointer<VpxCodecCtx> ctx);
typedef _vpx_codec_error_Dart = Pointer<Int8> Function(Pointer<VpxCodecCtx> ctx);

typedef _vpx_codec_error_detail_C = Pointer<Int8> Function(Pointer<VpxCodecCtx> ctx);
typedef _vpx_codec_error_detail_Dart = Pointer<Int8> Function(Pointer<VpxCodecCtx> ctx);

typedef _vpx_codec_destroy_C = Int32 Function(Pointer<VpxCodecCtx> ctx);
typedef _vpx_codec_destroy_Dart = int Function(Pointer<VpxCodecCtx> ctx);

typedef _vpx_codec_get_caps_C = Int64 Function(Pointer<VpxCodecIface> iface);
typedef _vpx_codec_get_caps_Dart = int Function(Pointer<VpxCodecIface> iface);

typedef _vpx_codec_control__C = Int32 Function(Pointer<VpxCodecCtx> ctx, Int32 ctrl_id, VarArgs<dynamic> args);
typedef _vpx_codec_control__Dart = int Function(Pointer<VpxCodecCtx> ctx, int ctrl_id, List<Object> args);

// Class to hold the loaded dynamic library and expose C functions
class VpxCodecBindings {
  final DynamicLibrary _lib;

  VpxCodecBindings(this._lib);

  /// Return the version information (as an integer)
  int vpx_codec_version() => _lib
      .lookup<NativeFunction<_vpx_codec_version_C>>('vpx_codec_version')
      .asFunction<_vpx_codec_version_Dart>();

  /// Return the version major number
  int vpx_codec_version_major() => (vpx_codec_version() >> 16) & 0xff;

  /// Return the version minor number
  int vpx_codec_version_minor() => (vpx_codec_version() >> 8) & 0xff;

  /// Return the version patch number
  int vpx_codec_version_patch() => (vpx_codec_version() >> 0) & 0xff;

  /// Return the version information (as a string)
  String vpx_codec_version_str() => _lib
      .lookup<NativeFunction<_vpx_codec_version_str_C>>('vpx_codec_version_str')
      .asFunction<_vpx_codec_version_str_Dart>()
      .toDartString();

  /// Return the version information (as a string)
  String vpx_codec_version_extra_str() => _lib
      .lookup<NativeFunction<_vpx_codec_version_extra_str_C>>(
          'vpx_codec_version_extra_str')
      .asFunction<_vpx_codec_version_extra_str_Dart>()
      .toDartString();

  /// Return the build configuration
  String vpx_codec_build_config() => _lib
      .lookup<NativeFunction<_vpx_codec_build_config_C>>(
          'vpx_codec_build_config')
      .asFunction<_vpx_codec_build_config_Dart>()
      .toDartString();

  /// Return the name for a given interface
  String vpx_codec_iface_name(Pointer<VpxCodecIface> iface) => _lib
      .lookup<NativeFunction<_vpx_codec_iface_name_C>>(
          'vpx_codec_iface_name')
      .asFunction<_vpx_codec_iface_name_Dart>()(iface)
      .toDartString();

  /// Convert error number to printable string
  String vpx_codec_err_to_string(VpxCodecErr err) => _lib
      .lookup<NativeFunction<_vpx_codec_err_to_string_C>>(
          'vpx_codec_err_to_string')
      .asFunction<_vpx_codec_err_to_string_Dart>()(err.index)
      .toDartString();

  /// Retrieve error synopsis for codec context
  String vpx_codec_error(Pointer<VpxCodecCtx> ctx) => _lib
      .lookup<NativeFunction<_vpx_codec_error_C>>('vpx_codec_error')
      .asFunction<_vpx_codec_error_Dart>()(ctx)
      .toDartString();

  /// Retrieve detailed error information for codec context
  String? vpx_codec_error_detail(Pointer<VpxCodecCtx> ctx) {
    final ptr = _lib
        .lookup<NativeFunction<_vpx_codec_error_detail_C>>(
            'vpx_codec_error_detail')
        .asFunction<_vpx_codec_error_detail_Dart>()(ctx);
    return ptr.isNull ? null : ptr.toDartString();
  }

  /// Destroy a codec instance
  VpxCodecErr vpx_codec_destroy(Pointer<VpxCodecCtx> ctx) => _lib
      .lookup<NativeFunction<_vpx_codec_destroy_C>>('vpx_codec_destroy')
      .asFunction<_vpx_codec_destroy_Dart>()(ctx)
      .toVpxCodecErr();

  /// Get the capabilities of an algorithm.
  int vpx_codec_get_caps(Pointer<VpxCodecIface> iface) => _lib
      .lookup<NativeFunction<_vpx_codec_get_caps_C>>('vpx_codec_get_caps')
      .asFunction<_vpx_codec_get_caps_Dart>()(iface);

  /// Control algorithm
  /// This function uses VarArgs and is more complex to bind directly with
  /// strong typing in Dart. For specific control IDs, you would create
  /// dedicated Dart functions that wrap this, passing the correct type
  /// for the `data` parameter.
  ///
  /// Example:
  /// VpxCodecErr vpx_codec_control_set_cpu_used(Pointer<VpxCodecCtx> ctx, int cpuUsed) {
  ///   return _lib
  ///       .lookup<NativeFunction<Int32 Function(Pointer<VpxCodecCtx>, Int32, Int32)>>(
  ///           'vpx_codec_control_') // Direct call to vpx_codec_control_
  ///       .asFunction<int Function(Pointer<VpxCodecCtx>, int, int)>()(
  ///           ctx, VPX_CODEC_CTRL_SET_CPU_USED, cpuUsed) // Assuming a control ID constant
  ///       .toVpxCodecErr();
  /// }
  ///
  /// Due to the nature of `vpx_codec_control_` being a variadic function and
  /// typically used via macros in C (`vpx_codec_control`), a direct Dart FFI
  /// binding for the variadic part is problematic. The recommended approach
  /// is to create specific wrapper functions in Dart for each `ctrl_id` you
  /// intend to use, explicitly defining the argument types.
  int vpx_codec_control_(Pointer<VpxCodecCtx> ctx, int ctrl_id, List<Object> args) {
    // This is a placeholder. Real implementation would involve
    // calling different FFI functions based on ctrl_id and expected argument types.
    // As Dart's FFI does not directly support C-style varargs for arbitrary types,
    // you would typically bind specific control functions if VPX_DISABLE_CTRL_TYPECHECKS
    // is not defined, or call _control directly with known types.
    throw UnimplementedError(
        "vpx_codec_control_ with varargs is complex to bind directly. "
        "Define specific wrappers for each ctrl_id you need.");
  }
}