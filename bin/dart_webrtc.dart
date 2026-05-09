// DTLS server example (legacy entry point).
//
// Listens on a UDP port and runs the STUN + DTLS server-side handshake
// via [RtcUdpTransport]. Once DTLS completes for a peer, SRTP keys are
// derived automatically; this example only logs the events.
//
// Run with: dart run bin\dart_webrtc.dart

import 'dart:io';

import 'package:pure_dart_webrtc/src/dtls/tests/verify_ecdsa_256_cert1.dart'
    show generateSelfSignedCertificate;
import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

Future<void> main(List<String> arguments) async {
  const ip = '192.168.160.1';
  const port = 4444;

  final transport = await RtcUdpTransport.bind(
    InternetAddress(ip),
    port,
    certificate: generateSelfSignedCertificate(),
    stunPassword: '05iMxO9GujD2fUWXSoi0ByNd',
  );

  print('listening on udp:${transport.address.address}:${transport.port}');

  transport
    ..onPeer = (peer) {
      print('[peer] new ${peer.remoteAddress.address}:${peer.remotePort}');
    }
    ..onSecure = (peer) {
      print('[peer] DTLS complete; SRTP keyed for '
          '${peer.remoteAddress.address}:${peer.remotePort}');
    }
    ..onUnknown = (peer, data) {
      print('[?] ${data.length} bytes from '
          '${peer?.remoteAddress.address}:${peer?.remotePort}');
    };

  await ProcessSignal.sigint.watch().first;
  await transport.close();
}
