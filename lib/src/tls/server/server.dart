import "dart:io";

import "package:dartls/src/tls/handshake_context.dart";

import "handshake_manager.dart";

class Server {
  String ip;
  int port;
  Server(this.ip, this.port);
  Future<void> listen() async {
    ServerSocket socket = await ServerSocket.bind(ip, port);
    socket.listen((onData) {
      // print("Received: $onData");
      handleSocket(onData);
    });

    print("listening on $ip:$port");
  }

  void handleSocket(Socket socket) {
    HandshakeContext context = HandshakeContext();
    HandshakeManager handshakeManager = HandshakeManager(context, socket);
    socket.listen((onData) {
      print("Received: $onData");
      handshakeManager.processTlsMessage(onData);
    });
  }
}

Future<void> main() async {
  final server = Server("127.0.0.1", 8500);
  await server.listen();
}
