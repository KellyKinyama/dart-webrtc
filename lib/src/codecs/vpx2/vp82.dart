import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img_lib;

import 'vp8_packet.dart';
import 'vpx_bindings.dart'; // Use 'image' package for JPEG encoding

class VP8Decoder {
  final NativeLibrary lib;
  final ffi.Pointer<vpx_codec_ctx_t> _ctx;
  
  List<int> _currentFrameBuffer = [];
  bool _seenKeyFrame = false;
  int _fileCount = 0;

  VP8Decoder(this.lib) : _ctx = calloc<vpx_codec_ctx_t>() {
    // Note: You need a function/pointer for vpx_codec_vp8_dx_algo
    // Usually provided by the library as an external symbol
    final result = lib.vpx_codec_dec_init_ver(
      _ctx, 
      lib.vpx_codec_vp8_dx(), // This helper must return the VP8 decoder interface
      ffi.nullptr, 
      0, 
      1 // VPX_DECODER_ABI_VERSION
    );
    
    if (result != vpx_codec_err_t.VPX_CODEC_OK) {
      throw Exception("Codec Init Failed: $result");
    }
  }

  void processRtpPacket(Uint8List rtpPayload, bool marker) {
    final vp8 = VP8Packet();
    try {
      vp8.unmarshal(rtpPayload);
    } catch (e) {
      return;
    }

    // Logic: Wait for a keyframe to start decoding
    if (!_seenKeyFrame && !vp8.isKeyFrame) return;
    
    // Logic: If we are mid-frame but this isn't a "start" partition, skip
    if (_currentFrameBuffer.isEmpty && vp8.s != 1) return;

    _seenKeyFrame = true;
    _currentFrameBuffer.addAll(vp8.payload);

    // Marker bit signifies the end of a full VP8 frame
    if (marker && _currentFrameBuffer.isNotEmpty) {
      _decodeAndSave();
      _currentFrameBuffer.clear();
    }
  }

  void _decodeAndSave() {
    final frameData = Uint8List.fromList(_currentFrameBuffer);
    final ffi.Pointer<ffi.UnsignedChar> nativeBuffer = malloc.allocate(frameData.length);
    nativeBuffer.asTypedList(frameData.length).setAll(0, frameData);

    final res = lib.vpx_codec_decode(_ctx, nativeBuffer.cast(), frameData.length, ffi.nullptr, 0);
    
    if (res == vpx_codec_err_t.VPX_CODEC_OK) {
      final iter = calloc<vpx_codec_iter_t>();
      ffi.Pointer<vpx_image_t> img;
      
      while ((img = lib.vpx_codec_get_frame(_ctx, iter)) != ffi.nullptr) {
        _convertAndWriteToFile(img);
      }
      malloc.free(iter);
    }

    malloc.free(nativeBuffer);
  }

  void _convertAndWriteToFile(ffi.Pointer<vpx_image_t> vpxImg) {
    final image = vpxImg.ref;
    
    // IMPORTANT: Converting YUV420 to RGB for JPEG
    // In a real app, use a high-performance converter. 
    // Here is a simplified logic using the 'image' package:
    final dartImg = img_lib.Image(width: image.d_w, height: image.d_h);
    
    // TODO: Loop through image.planes and image.stride to map YUV to dartImg
    // This part is computationally expensive in pure Dart.
    
    final jpeg = img_lib.encodeJpg(dartImg);
    File('output/shoot${_fileCount++}.jpg').writeAsBytesSync(jpeg);
  }

  void dispose() {
    lib.vpx_codec_destroy(_ctx);
    malloc.free(_ctx);
  }
}