import 'dart:ffi' as ffi;

import 'types.dart';
import 'vpx_bindings.dart';

const Vp8Fourcc = 808996950;
const Vp9Fourcc = 809062486;

String libraryPath = 'C:/msys64/mingw64/bin/libvpx-1.dll';

ffi.DynamicLibrary vpxLib = vpxLib = ffi.DynamicLibrary.open(libraryPath);
final bindings = NativeLibrary(vpxLib);

ffi.Pointer<CodecIface> decoderIfaceVP8() {
  return bindings.vpx_codec_vp8_dx();
}

ffi.Pointer<vpx_codec_iface> decoderIfaceVP9()
// *CodecIface
{
  return bindings.vpx_codec_vp9_dx();
}

// ffi.Pointer<vpx_codec_iface> decoderIfaceVP10() {
//   return bindings.vpx_codec_vp10_dx();
// }

ffi.Pointer<vpx_codec_iface> decoderFor(int fourcc) {
  switch (fourcc) {
    case Vp8Fourcc:
      return decoderIfaceVP8();
    case Vp9Fourcc:
      return decoderIfaceVP9();
  }
  throw ArgumentError(fourcc);
}

ffi.Pointer<vpx_codec_iface> encoderIfaceVP8() {
  return bindings.vpx_codec_vp8_cx();
}

ffi.Pointer<vpx_codec_iface> encoderIfaceVP9() {
  return bindings.vpx_codec_vp9_cx();
}

// func EncoderIfaceVP10() *CodecIface {
// 	return (*CodecIface)(C.vpx_codec_vp10_cx())
// }

ffi.Pointer<vpx_codec_iface> encoderFor(int fourcc) {
  switch (fourcc) {
    case Vp8Fourcc:
      return encoderIfaceVP8();
    case Vp9Fourcc:
      return encoderIfaceVP9();
  }
  throw ArgumentError(fourcc);
}
