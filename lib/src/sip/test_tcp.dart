import 'dart:io';

import 'package:dotenv/dotenv.dart';

class SecureTcpSipServer {
  String tcpIp; // = env['WS_SERVER_ADDRESS']!;
  int tcpPort; // = int.parse(env['WS_SERVER_PORT']!);
  String path_to_certificate_file;
  String path_to_private_key_file;

  SecureTcpSipServer(this.tcpIp, this.tcpPort, this.path_to_certificate_file,
      this.path_to_private_key_file) {
    connect();
  }
  void connect() async {
    // Security context to specify certificate and private key files
    SecurityContext serverContext = SecurityContext();
    serverContext.useCertificateChain(path_to_certificate_file);
    serverContext.usePrivateKey(path_to_private_key_file);

    // Create a server socket using the security context
    var server = await SecureServerSocket.bind(tcpIp, tcpPort, serverContext);

    print('Server listening on port ${server.port}');

    // Listen for connections and handle them asynchronously
    await for (var socket in server) {
      handleConnection(socket);
    }
  }

  void handleConnection(SecureSocket socket) {
    print(
        'Connection from ${socket.remoteAddress.address}:${socket.remotePort}');

    socket.listen((List<int> data) {
      // Handle incoming data
      var dataFromSocket = String.fromCharCodes(data);
      print('Received: $dataFromSocket');
      //print(object)
      // Echo the received data back to the client
      //socket.write('Server echo: ${String.fromCharCodes(data)}');
    }, onError: (error) {
      // Handle errors
      print('Error: $error');
    }, onDone: () {
      // Handle when the client disconnects
      print('Client disconnected');
    });
  }
}
