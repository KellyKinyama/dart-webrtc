import 'dart:io';

import 'package:dart_webrtc/src/dtls/dtls_message.dart' as dtls;
import 'package:dart_webrtc/src/dtls/examples/server/dtls_server.dart'
    as dtls_server;
import 'package:dart_webrtc/src/dtls/tests/verify_ecdsa_256_cert1.dart';
import 'package:dart_webrtc/src/stun3/stun_server8.dart' as stun;

// import 'package:dart_webrtc/src/stun/src/stun_message.dart';
// import 'dart:typed_data';

// import 'package:dart_tls/ch09/handshake/handshake_context.dart';
// import 'package:dart_tls/ch09/handshaker/psk_aes_128_ccm.dart';
// import 'package:dart_tls/dart_tls.dart' as dart_tls;

void main(List<String> arguments) {
  String ip = "192.168.160.1";
  // String ip = "127.0.0.1";
  int port = 4444;

  EcdsaCert serverEcCertificate = generateSelfSignedCertificate();

  RawDatagramSocket.bind(InternetAddress(ip), port)
      .then((RawDatagramSocket socket) {
    //print('UDP Echo ready to receive');
    print('listening on udp:${socket.address.address}:${socket.port}');

    socket.listen((RawSocketEvent e) {
      Datagram? d = socket.receive();

      if (d != null) {
        // print("recieved data ${d.data}");

        if (stun.StunMessage.isStunMessage(d.data)) {
          stun.StunServer.handleDatagram(d,
              socket: socket, serverPassword: "05iMxO9GujD2fUWXSoi0ByNd");
        } else if (dtls.isDtlsPacket(d.data, 0, d.data.length)) {
          // Handle DTLS packet
          print("DTLS packet received");
          // You can decode the DTLS message here
          dtls_server.handleDtls(d, socket, serverEcCertificate);
          // print("DTLS msg: $dtlsMsg");
        } else {
          throw Exception("Unknown packet type received: ");
        }

        // HandshakeContext context = HandshakeContext();
        // final dtlsMsg =
        //     DecodeDtlsMessageResult.decode(context, d.data, 0, d.data.length);

        // print("DTLS msg: $stunMessage");
      }
    });
  });
}
