import 'dart:io';

import '../globals.dart';
import '../sip_parser/sip.dart';
import '../transports/transport.dart';

class WssSipServer {
  WssSipServer(this.ip, this.port, this.path_to_certificate_file,
      this.path_to_private_key_file, this.rootCertificate) {
    SecurityContext serverContext = SecurityContext(withTrustedRoots: true);
    serverContext.setTrustedCertificates(rootCertificate);
    serverContext.useCertificateChain(path_to_certificate_file);
    serverContext.usePrivateKey(path_to_private_key_file);

    HttpServer.bindSecure(ip, port, serverContext).then((server) async {
      print('Listening on wss://${server.address.address}:${server.port}');

      await for (HttpRequest request in server) {
        print("Client connected...");
        request.response.headers.set("Sec-WebSocket-Protocol", "sip");
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          WebSocketTransformer.upgrade(request).then(handleWebSocket);
        } else {
          request.response
            ..statusCode = HttpStatus.forbidden
            ..close();
        }
      }
    });
  }

  void handleWebSocket(WebSocket socket) async {
    //   .then((RawDatagramSocket socket) {
    //print('UDP client ready to receive');
    //print('${udpClient.address.address}:${udpClient.port}');

    //handler = ReqHandler(socket.address.address, socket.port, socket);

    //SecureServerSocket.secureServer();
    msgToClient(String data) {
      print("Sending to client");
      socket.add(data);
    }

    msgFromClient(String data) {
      var tx = SipTransport(sockaddr_in(ip, port, 'wss'),
          sockaddr_in(ip, port, 'wss'), msgToClient);
      requestsHander.handle(data, tx);
    }

    socket.listen(
      (data) {
        //print('Received: $data');
        //onNewMessageFromWS(data);
        msgFromClient(data);
        //socket.add('Echo: ${json.encode(resp)}');
      },
      onDone: () {
        //print('Connection closed');
      },
      onError: (error) {
        //print('Error: $error');
      },
    );
  }

  String ip;
  int port;
  String path_to_certificate_file;
  String path_to_private_key_file;

  String rootCertificate;
}
