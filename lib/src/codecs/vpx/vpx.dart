// Public API of the VPX codec wrapper.
//
// Typical usage:
//
//   import 'package:pure_dart_webrtc/src/codecs/vpx/vpx.dart';
//
//   final encoder = VpxEncoder(
//     codec: VpxCodec.vp8,
//     width: 384, height: 216,
//     fps: 25, bitrateKbps: 800,
//   );
//   final ivf = IvfWriter.toFile(File('out.ivf'),
//       codec: VpxCodec.vp8, width: 384, height: 216, fps: 25);
//
//   for (var i = 0; i < frames.length; i++) {
//     for (final p in encoder.encode(frames[i], pts: i)) {
//       ivf.writeFrame(p.data, p.pts);
//     }
//   }
//   for (final p in encoder.flush()) {
//     ivf.writeFrame(p.data, p.pts);
//   }
//   await ivf.close();
//   encoder.dispose();

export 'i420_frame.dart';
export 'ivf.dart';
export 'vpx_codec_kind.dart';
export 'vpx_decoder.dart';
export 'vpx_encoder.dart' show VpxEncoder, VpxPacket, VpxException;
export 'vpx_loader.dart' show VpxLoaderException, loadVpx;
