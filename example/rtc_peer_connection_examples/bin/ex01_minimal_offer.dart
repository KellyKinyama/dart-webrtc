// 01_minimal_offer.dart
//
// Smallest possible server-side use of `RTCPeerConnection`:
//
//   1. Construct an `RTCPeerConnection` with default codecs.
//   2. Add one sendrecv video transceiver and one sendrecv audio
//      transceiver.
//   3. Generate a local offer SDP and print it.
//
// No socket is bound, no peer is contacted. This is the "hello world"
// of the API surface — useful for confirming that the package imports,
// builds, and produces a syntactically-valid offer.
//
// Run:
//   dart run bin/01_minimal_offer.dart

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

Future<void> main() async {
  final pc = RTCPeerConnection(RTCConfiguration(
    defaultVideoCodecs: [Vp8Codec()],
    defaultAudioCodecs: [PcmuCodec()],
  ));

  pc.addTransceiver(trackOrKind: MediaKind.video);
  pc.addTransceiver(trackOrKind: MediaKind.audio);

  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  print('--- local offer (${offer.type.name}) ---');
  print(offer.sdp);
  print('--- end ---');
  print('signalingState=${pc.signalingState.name}');

  pc.close();
}
