
// lib/vpx_library.dart
import 'dart:ffi' as ffi;
import 'dart:io';
// import 'package:ffi/ffi.dart';
import 'vpx_bindings.dart';
import 'vpx_exception.dart';
import 'vpx_enums.dart';

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
        ffi.Pointer Function(ffi.Pointer, ffi.Pointer),
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
