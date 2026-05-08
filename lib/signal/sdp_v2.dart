// Public surface of the new SDP module (typed model + offer/answer builder).
//
// The legacy `lib/signal/sdp.dart` (and `sdp2..sdp4.dart`) are kept in place
// for backward compatibility. New code should use this entry point.
//
// Typical usage:
//
//   import 'package:pure_dart_webrtc/signal/sdp_v2.dart';
//
//   final offer = SdpOfferBuilder(
//     identity: IceDtlsParams(
//       iceUfrag: 'abcd',
//       icePwd: '0123456789abcdef0123',
//       fingerprintHash: '12:34:...',
//     ),
//     candidates: [
//       IceCandidate(foundation: '1', address: '192.0.2.1', port: 7000),
//     ],
//   )
//     ..addVideo(mid: '0', codecs: [Vp8Codec(), Vp9Codec()])
//     ..addAudio(mid: '1', codecs: [PcmaCodec(), PcmuCodec()]);
//
//   final sdpText = offer.build().write();
library;

export 'sdp/sdp_codec.dart';
export 'sdp/sdp_offer_answer.dart';
export 'sdp/sdp_session.dart';
