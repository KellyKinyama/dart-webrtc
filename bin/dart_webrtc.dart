import 'dart:io';

import 'package:dart_webrtc/src/dtls/dtls_message.dart' as dtls;
import 'package:dart_webrtc/src/dtls/examples/server/dtls_server.dart'
    as dtls_server;
import 'package:dart_webrtc/src/stun3/stun_server8.dart' as stun;

// import 'package:dart_webrtc/src/stun/src/stun_message.dart';
// import 'dart:typed_data';

// import 'package:dart_tls/ch09/handshake/handshake_context.dart';
// import 'package:dart_tls/ch09/handshaker/psk_aes_128_ccm.dart';
// import 'package:dart_tls/dart_tls.dart' as dart_tls;

void main(List<String> arguments) {
  String ip = "10.100.53.194";
  // String ip = "10.100.53.174";
  int port = 4444;

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
          dtls_server.handleDtls(d, socket);
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
