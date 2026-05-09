// SRTP server example (legacy entry point).
//
// Same shape as bin\srtp_webrtc2.dart but bound to a fixed IP/port and
// only logs (no echo). Uses [RtcUdpTransport] which handles STUN, DTLS
// and SRTP key derivation automatically.
//
// Run with: dart run bin\srtp_webrtc.dart

import 'dart:io';

import 'package:pure_dart_webrtc/src/dtls/tests/verify_ecdsa_256_cert1.dart'
    show generateSelfSignedCertificate;
import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

Future<void> main(List<String> arguments) async {
  const ip = '192.168.56.1';
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
    ..onRtp = (peer, decrypted) {
      print('[rtp] ${decrypted.length} bytes from '
          '${peer.remoteAddress.address}:${peer.remotePort}');
    }
    ..onRtcp = (peer, decrypted) {
      print('[rtcp] ${decrypted.length} bytes pt=${decrypted[1] & 0x7f} '
          'from ${peer.remoteAddress.address}:${peer.remotePort}');
    };

  await ProcessSignal.sigint.watch().first;
  await transport.close();
}
