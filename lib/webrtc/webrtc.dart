// Public entry point for the browser-shaped WebRTC API.
//
// ```dart
// import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
//
// final pc = RTCPeerConnection(RTCConfiguration(
//   defaultVideoCodecs: [Vp8Codec()],
//   defaultAudioCodecs: [PcmuCodec()],
// ));
// pc.addTransceiver(trackOrKind: MediaKind.video);
// final offer = await pc.createOffer();
// await pc.setLocalDescription(offer);
// ```
library;

export 'peer_connection.dart';
export 'rtc_udp_transport.dart';

// Re-export codec constructors so callers don't need a second import.
export 'package:pure_dart_webrtc/signal/sdp_v2.dart'
    show
        SdpCodec,
        Vp8Codec,
        Vp9Codec,
        PcmaCodec,
        PcmuCodec,
        TelephoneEventCodec;
