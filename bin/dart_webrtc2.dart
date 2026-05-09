// DTLS+SRTP server example (legacy entry point).
//
// Same as bin\dart_webrtc.dart but bound to localhost. Uses the new
// [RtcUdpTransport] which wires up SRTP key derivation automatically
// once DTLS completes.
//
// Run with: dart run bin\dart_webrtc2.dart

import 'dart:io';

import 'package:pure_dart_webrtc/src/dtls/tests/verify_ecdsa_256_cert1.dart'
    show generateSelfSignedCertificate;
import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

Future<void> main(List<String> arguments) async {
  const ip = '127.0.0.1';
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
