// https://stackoverflow.com/questions/68859120/how-to-convert-vp8-interframe-into-image-with-pion-webrtc
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'dart:ffi' as ffi;

import 'iface.dart';
import 'types.dart';
import 'vpx_bindings.dart';

typedef CodecFlags = int;

String libraryPath = 'C:/msys64/mingw64/bin/libvpx-1.dll';

ffi.DynamicLibrary vpxLib = vpxLib = ffi.DynamicLibrary.open(libraryPath);
final bindings = NativeLibrary(vpxLib);

class VP8Decoder {
  // src     <-chan *rtp.Packet
  Uint8List src;
  ffi.Pointer<CodecCtx> context;
  ffi.Pointer<vpx_codec_iface> iface;

  VP8Decoder({required this.src, required this.context, required this.iface});

  static VP8Decoder newVP8Decoder(Uint8List src) {
    final contextPtr = calloc<CodecCtx>(1);
    final result = VP8Decoder(
      src: src,
      context: contextPtr,
      iface: decoderIfaceVP8(),
    );
    // err := vpx.Error(vpx.CodecDecInitVer(result.context, result.iface, nil, 0, vpx.DecoderABIVersion))
    // if err != nil {
    // 	return nil, err
    // }
    return result;
  }
}

// CodecDecInitVer function as declared in vpx-1.6.0/vpx_decoder.h:136
ffi.Pointer<Utf8> codecDecInitVer(
    ffi.Pointer<CodecCtx> ctx,
    ffi.Pointer<CodecIface> iface,
    ffi.Pointer<vpx_codec_dec_cfg_t> cfg,
    CodecFlags flags,
    int ver) {
  // final cctx = ctx;
  // final ciface = iface;
  // ccfg, _ := cfg.PassRef()
  // cflags, _ := (C.vpx_codec_flags_t)(flags), cgoAllocsUnknown
  // cver, _ := (C.int)(ver), cgoAllocsUnknown
  // __ret := C.vpx_codec_dec_init_ver(cctx, ciface, ccfg, cflags, cver)
  bindings.vpx_codec_dec_init_ver(ctx, iface, cfg, flags, ver);
  final ffi.Pointer<Utf8> versionCharPtr =
      bindings.vpx_codec_version_str().cast<Utf8>();
  // __v := (CodecErr)(__ret)
  // return __v
  return versionCharPtr;
}
