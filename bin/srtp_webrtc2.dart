// SRTP/DTLS server example using the new browser-shaped WebRTC API.
//
// Listens on a UDP port and demultiplexes incoming packets into STUN, DTLS,
// SRTP and SRTCP via [RtcUdpTransport]. Once DTLS completes for a peer,
// SRTP keys are derived automatically and decrypted RTP/RTCP is echoed
// back encrypted.
//
// Run with:
//   dart run bin\srtp_webrtc2.dart [--ip 192.168.56.1] [--port 4444]

import 'dart:io';

import 'package:pure_dart_webrtc/src/dtls/tests/verify_ecdsa_256_cert1.dart'
    show generateSelfSignedCertificate;
import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

Future<void> main(List<String> arguments) async {
  String ip = '192.168.56.1';
  int port = 4444;
  String stunPassword = '05iMxO9GujD2fUWXSoi0ByNd';

  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--ip':
        ip = arguments[++i];
        break;
      case '--port':
        port = int.parse(arguments[++i]);
        break;
      case '--stun-password':
        stunPassword = arguments[++i];
        break;
    }
  }

  final transport = await RtcUdpTransport.bind(
    InternetAddress(ip),
    port,
    certificate: generateSelfSignedCertificate(),
    stunPassword: stunPassword,
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
    ..onRtp = (peer, decrypted) async {
      print('[rtp] ${decrypted.length} bytes from '
          '${peer.remoteAddress.address}:${peer.remotePort}');
      // Echo back, re-encrypted.
      await transport.sendRtp(peer, decrypted);
    }
    ..onRtcp = (peer, decrypted) async {
      print('[rtcp] ${decrypted.length} bytes pt=${decrypted[1] & 0x7f} '
          'from ${peer.remoteAddress.address}:${peer.remotePort}');
      await transport.sendRtcp(peer, decrypted);
    }
    ..onUnknown = (peer, data) {
      print('[?] ${data.length} bytes from '
          '${peer?.remoteAddress.address}:${peer?.remotePort}');
    };

  // Run until Ctrl+C.
  await ProcessSignal.sigint.watch().first;
  await transport.close();
}
