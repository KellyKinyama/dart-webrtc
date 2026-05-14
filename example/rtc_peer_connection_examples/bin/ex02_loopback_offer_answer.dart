// 02_loopback_offer_answer.dart
//
// Two `RTCPeerConnection`s in the same Dart process complete the full
// SDP offer / answer exchange against each other. No browser, no
// signalling server.
//
// What you'll see in the output:
//   - signaling state transitions on both sides ending at `stable`
//   - one host ICE candidate per side (loopback)
//   - the negotiated codecs / m-line directions
//
// IMPORTANT — server <-> server media path is NOT yet wired up in
// pure_dart_webrtc. `RTCPeerConnection.bind()` listens for incoming
// STUN binding requests but does not actively send them, so two
// servers facing each other will reach `iceConnectionState=checking`
// and stop there. To complete DTLS you need a real ICE controller on
// at least one side (typically a browser). This example therefore
// stops after the SDP exchange and prints the negotiated state.
//
// Run:
//   dart run bin/ex02_loopback_offer_answer.dart

import 'dart:io';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

Future<void> main() async {
  final loopback = InternetAddress.loopbackIPv4;

  final offerer = RTCPeerConnection(RTCConfiguration(
    defaultVideoCodecs: [Vp8Codec()],
    defaultAudioCodecs: [PcmuCodec()],
  ));
  final answerer = RTCPeerConnection(RTCConfiguration(
    defaultVideoCodecs: [Vp8Codec()],
    defaultAudioCodecs: [PcmuCodec()],
  ));

  _wireLogging('offerer', offerer);
  _wireLogging('answerer', answerer);

  // Bind two UDP sockets on different ports so each side has a real
  // host candidate to advertise in its SDP.
  await offerer.bind(loopback, 51000);
  await answerer.bind(loopback, 51001);

  // Offerer wants to send + receive video and audio.
  offerer.addTransceiver(trackOrKind: MediaKind.video);
  offerer.addTransceiver(trackOrKind: MediaKind.audio);

  // The answerer doesn't need to pre-add transceivers; setRemoteDescription
  // mirrors them automatically. (You can still call addTransceiver if you
  // want non-default codec preferences.)

  // ---- Offer ----------------------------------------------------------
  final offer = await offerer.createOffer();
  await offerer.setLocalDescription(offer);
  await answerer.setRemoteDescription(offer);

  // ---- Answer ---------------------------------------------------------
  final answer = await answerer.createAnswer();
  await answerer.setLocalDescription(answer);
  await offerer.setRemoteDescription(answer);

  // Drain pending microtasks (state transitions, candidate emits).
  await Future<void>.delayed(const Duration(milliseconds: 50));

  print('\n[loopback] negotiation complete.');
  print('  offerer:  signaling=${offerer.signalingState.name} '
      'ice=${offerer.iceConnectionState.name} '
      'conn=${offerer.connectionState.name}');
  print('  answerer: signaling=${answerer.signalingState.name} '
      'ice=${answerer.iceConnectionState.name} '
      'conn=${answerer.connectionState.name}');
  print('  offerer transceivers: '
      '${offerer.getTransceivers().map((t) => '${t.kind.name}:${t.direction.name}').join(', ')}');

  offerer.close();
  answerer.close();
}

void _wireLogging(String tag, RTCPeerConnection pc) {
  pc.onSignalingStateChange = (s) => print('[$tag] signaling=${s.name}');
  pc.onIceConnectionStateChange = (s) => print('[$tag] ice=${s.name}');
  pc.onConnectionStateChange = (s) => print('[$tag] conn=${s.name}');
  pc.onIceCandidate = (c) {
    if (c == null) {
      print('[$tag] ice-end');
    } else {
      print('[$tag] candidate ${c.candidate}');
    }
  };
}
