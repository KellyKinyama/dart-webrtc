// Example 5 — ICE server-reflexive (srflx) candidate gathering.
//
// Demonstrates how to configure an `RTCPeerConnection` with one or more
// STUN servers and observe the candidates emitted by `onIceCandidate`.
//
// Pipeline:
//   1. Build an RTCPeerConnection with a `stun:` URL in `iceServers`.
//   2. Add a transceiver (gathering needs at least one m-section).
//   3. `bind()` the local UDP socket. The peer connection will:
//        - emit one `host` candidate for the bound socket,
//        - send a STUN Binding Request to each configured STUN server
//          from that *same* socket, and
//        - emit one `srflx` candidate per successful response,
//        - finally emit `null` to mark end-of-candidates.
//
// Run with the project's STUN URL of choice, e.g. Google's public server:
//
//   dart run example/rtc_peer_connection_examples/bin/ex05_ice_srflx_gathering.dart
//
// You should see output similar to:
//
//   host : candidate:1 1 udp 2113937151 192.168.1.42 54321 typ host
//   srflx: candidate:2 1 udp 1694498815 203.0.113.7 54321 typ srflx ...
//   <end-of-candidates>
//
// If you are behind a symmetric NAT or have no internet access the srflx
// line will simply not appear; the host candidate and end-of-candidates
// sentinel are always emitted.

import 'dart:async';
import 'dart:io';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

Future<void> main() async {
  final pc = RTCPeerConnection(RTCConfiguration(
    iceServers: const [
      RTCIceServer(urls: ['stun:stun.l.google.com:19302']),
      RTCIceServer(urls: ['stun:stun1.l.google.com:19302']),
    ],
    defaultVideoCodecs: [Vp8Codec()],
  ));

  pc.addTransceiver(trackOrKind: MediaKind.video);

  final done = Completer<void>();
  pc.onIceCandidate = (cand) {
    if (cand == null) {
      print('<end-of-candidates>');
      if (!done.isCompleted) done.complete();
      return;
    }
    final kind = cand.candidate.contains('typ host') ? 'host ' : 'srflx';
    print('$kind: ${cand.candidate}');
  };

  pc.onIceGatheringStateChange = (s) {
    print('iceGatheringState -> ${s.name}');
  };

  final transport = await pc.bind(InternetAddress.anyIPv4, 0);
  print('Bound on ${transport.address.address}:${transport.port}');

  // Wait for gathering to finish (or 5 s, whichever comes first).
  await done.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () => print('Timed out waiting for end-of-candidates.'),
  );

  pc.close();
}
