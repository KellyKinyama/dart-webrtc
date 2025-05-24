import 'dart:io';

import '../globals.dart';
import '../sip_parser/sip.dart';
import '../transports/transport.dart';

class WsSipServer {
  WsSipServer(this.ip, this.port) {
    HttpServer.bind(ip, port).then((server) async {
      print('Listening on ws://${server.address.address}:${server.port}');

      await for (HttpRequest request in server) {
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
    onNewMessageFromSipServer(String data) {
      print(data);
      socket.add(data);
    }

    //SecureServerSocket.secureServer();
    msgToClient(String data) {
      //print("Sending to client $data");
      socket.add(data);
    }

    msgFromClient(String data) {
      var tx = SipTransport(sockaddr_in(ip, port, 'ws'),
          sockaddr_in(ip, port, 'ws'), msgToClient);
      requestsHander.handle(data, tx);
    }

    socket.listen(
      (data) {
        //print('Received: $data');
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
}
