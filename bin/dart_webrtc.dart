import 'dart:io';

import 'package:dart_webrtc/src/stun/src/stun_message.dart';
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
        print("recieved data ${d.data}");

        StunMessage stunMessage =
            StunMessage.form(d.data, StunProtocol.RFC5780);

        // HandshakeContext context = HandshakeContext();
        // final dtlsMsg =
        //     DecodeDtlsMessageResult.decode(context, d.data, 0, d.data.length);

        print("DTLS msg: $stunMessage");
      }
    });
  });
}
