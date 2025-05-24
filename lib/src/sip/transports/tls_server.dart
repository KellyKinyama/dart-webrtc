import 'dart:io';

import '../globals.dart';
import '../sip_parser/sip.dart';
import '../transports/transport.dart';
import 'package:dotenv/dotenv.dart';

class SecureTcpSipServer {
  String tcpIp; // = env['WS_SERVER_ADDRESS']!;
  int tcpPort; // = int.parse(env['WS_SERVER_PORT']!);

  String udpServerIp;
  int udpServerPort;

  String path_to_certificate_file;
  String path_to_private_key_file;
  String rootCertificate;

  SecureTcpSipServer(
      this.tcpIp,
      this.tcpPort,
      this.udpServerIp,
      this.udpServerPort,
      this.path_to_certificate_file,
      this.path_to_private_key_file,
      this.rootCertificate) {
    connect();
  }
  void connect() async {
    // Security context to specify certificate and private key files
    SecurityContext serverContext = SecurityContext(withTrustedRoots: true);
    serverContext.setTrustedCertificates(rootCertificate);
    serverContext.useCertificateChain(path_to_certificate_file);
    serverContext.usePrivateKey(path_to_private_key_file);

    // Create a server socket using the security context
    var server = await SecureServerSocket.bind(tcpIp, tcpPort, serverContext);

    print(
        'Server listening on port tls:${server.address.address}:${server.port}');

    // Listen for connections and handle them asynchronously
    // try {
    //   await for (var socket in server) {
    //     //handleConnection(socket);
    //     // Handle TLS connections
    //     //try {
    //     handleTLSSecureConnection(socket);
    //   }
    // } catch (exception) {
    //   print("Error: $exception");
    // }

    server.listen(
        (SecureSocket client) {
          handleTLSSecureConnection(client);
        },
        cancelOnError: false,
        onError: (error, stack) {
          print("{Error: $error, stacktrace: $stack}");
        });
  }

  void handleConnection(SecureSocket socket) {
    print(
        'Connection from ${socket.remoteAddress.address}:${socket.remotePort}');
    //SecureServerSocket.secureServer();
    msgToClient(String data) {
      print("Sending to client");
      socket.write(data);
    }

    msgFromClient(String data) {
      var tx = SipTransport(
          sockaddr_in(socket.remoteAddress.address, socket.remotePort, 'tls'),
          sockaddr_in(tcpIp, tcpPort, 'tls'),
          msgToClient);
      requestsHander.handle(data, tx);
    }

    socket.listen((List<int> data) {
      // Handle incoming data
      var dataFromSocket = String.fromCharCodes(data);
      print('Received: $dataFromSocket');
      //print(object)
      // Echo the received data back to the client
      //socket.write('Server echo: ${String.fromCharCodes(data)}');
      msgFromClient(dataFromSocket);
    }, onError: (error) {
      // Handle errors
      print('Error: $error');
    }, onDone: () {
      // Handle when the client disconnects
      print('Client disconnected');
    });
  }

  void handleTLSSecureConnection(SecureSocket socket) {
    print(
        'TLS connection from ${socket.remoteAddress.address}:${socket.remotePort}');

    socket.listen((List<int> data) {
      // Handle incoming data
      print('Received (TLS): ${String.fromCharCodes(data)}');
      // Echo the received data back to the client
      //socket.write('Server echo (TLS): ${String.fromCharCodes(data)}');
    }, onError: (error) {
      // Handle errors
      print('Error (TLS): $error');
    }, onDone: () {
      // Handle when the client disconnects
      print('Client disconnected (TLS)');
    });
  }

  void handleNonTLSSecureConnection(Socket socket) {
    print(
        'Non-TLS connection from ${socket.remoteAddress.address}:${socket.remotePort}');

    // Close the non-TLS connection immediately
    socket.close();
    print('Connection closed (Non-TLS)');
  }
}
