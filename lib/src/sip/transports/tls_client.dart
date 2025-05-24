import 'dart:convert';
import 'dart:io';

class TlsClient {
  int client_port;
  String server_address; // = "msteams.zesco.co.zm";

  String path_to_certificate_file;
  String path_to_private_key_file;
  String rootCertificate;

  // Security context to specify certificate and private key files
  TlsClient(this.path_to_certificate_file, this.path_to_private_key_file,
      this.rootCertificate, this.server_address, this.client_port);

  //try {
  Future<void> connect() async {
    // Security context to specify certificate and private key files
    SecurityContext serverContext = SecurityContext(withTrustedRoots: true);
    serverContext.setTrustedCertificates(rootCertificate);
    serverContext.useCertificateChain(path_to_certificate_file);
    serverContext.usePrivateKey(path_to_private_key_file);
    Socket socket = await SecureSocket.connect(server_address, client_port,
        context: serverContext, onBadCertificate: (certificate) {
      return true;
    });

    socket.listen((List<int> data) {
      // Handle incoming data from the server
      print(utf8.decode(data));
    }, onDone: () {
      // Handle when the connection is closed
      print('Connection closed');
    }, onError: (error) {
      // Handle connection errors
      print('Error: $error');
    });
  }
}
