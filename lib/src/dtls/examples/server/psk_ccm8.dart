import 'dart:io';
// import 'dart:typed_data';

// import 'package:dart_tls/ch09/handshake/handshake_context.dart';
// import 'package:dart_tls/ch09/handshaker/psk_aes_128_ccm.dart';
import '../../handshaker/psk_aes_ccm8.dart';
// import 'package:dart_tls/dart_tls.dart' as dart_tls;

void main(List<String> arguments) {
  String ip = "127.0.0.1";
  // String ip = "10.100.53.174";
  int port = 4444;
  RawDatagramSocket.bind(InternetAddress(ip), port)
      .then((RawDatagramSocket socket) {
    //print('UDP Echo ready to receive');
    print('listening on udp:${socket.address.address}:${socket.port}');

    HandshakeManager handshakeManager = HandshakeManager(socket);

    socket.listen((RawSocketEvent e) {
      Datagram? d = socket.receive();

      if (d != null) {
        handshakeManager.port = d.port;
        print("recieved data ...");
        // HandshakeContext context = HandshakeContext();
        // final dtlsMsg =
        //     DecodeDtlsMessageResult.decode(context, d.data, 0, d.data.length);

        handshakeManager.processDtlsMessage(d.data);
        //print("DTLS msg: $dtlsMsg");
      }
    });
  });
}
