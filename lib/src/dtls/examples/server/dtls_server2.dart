import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dtls2/dtls2.dart';

void main() async {
  final port = 8080;
  final address = InternetAddress.anyIPv4;

  // Paths to your ECDSA server certificate and private key
  final serverCertificatePath = 'server_ecdsa.crt';
  final serverPrivateKeyPath = 'server_ecdsa.key';

  // Load certificate and private key
  final certificateChain = File(serverCertificatePath).readAsBytesSync();
  final privateKey = File(serverPrivateKeyPath).readAsBytesSync();

  // The *exact* cipher suite string for OpenSSL
  final ciphers = //[
      'ECDHE-ECDSA-AES128-GCM-SHA256'
      //]
      ;
// openssl req -new -x509 -key server_ecdsa.key -out server_ecdsa.crt -days 365  -subj "/CN=localhost"
  // For robust security, generally use a higher security level (2 or 3).
  // Level 0 might be needed for very old clients or specific hardware/software
  // that doesn't support the stricter requirements of higher levels.
  // For most modern applications, try to use securityLevel: 2 or 3.
  const securityLevel = 2; // Recommended for modern ciphers

  print("Starting DTLS server on $address:$port");
  print("Attempting to use cipher: $ciphers");
  print("Using security level: $securityLevel");

  DtlsServer? dtlsServer;

  try {
    // Create a DTLS server context with the ECDSA certificate and private key
    final dtlsServerContext = DtlsServerContext(
      // certificateChainBytes: [Uint8List.fromList(certificateChain)],
      // privateKeyBytes: Uint8List.fromList(privateKey),
      ciphers: ciphers,
      securityLevel: securityLevel,
      // You can also specify the supported elliptic curves here if needed,
      // though OpenSSL usually handles this based on the cipher suite.
      // E.g., namedCurves: ['P-384', 'P-256']
    );

    // Bind the DTLS server to an address and port
    dtlsServer = await DtlsServer.bind(
      address,
      port,
      dtlsServerContext,
    );

    print("DTLS server listening...");

    dtlsServer.listen(
      (connection) {
        print("New DTLS connection from");
        // print(
        // "New DTLS connection from ${connection.}:${connection.peerPort}");
        print(
            "Negotiated cipher:"); // This should be ECDHE-ECDSA-AES128-GCM-SHA256
        print("Negotiated protocol:"); // Likely DTLSv1.2

        connection.listen(
          (event) async {
            print("Received data from client: ${utf8.decode(event.data)}");
            await connection.send(
                utf8.encode("Hello Client! Your ECDSA connection is secure."));
            // For a simple example, you might close after sending:
            // await connection.close();
          },
          onDone: () {
            print("Client connection closed:");
            // print(
            //     "Client connection closed: ${connection.peerAddress.address}:${connection.peerPort}");
          },
          onError: (e) {
            print("Error on client connection: $e");
          },
        );
      },
      onDone: () async {
        print("DTLS server stopped listening.");
        await dtlsServer?.close();
      },
      onError: (e) {
        print("Error on DTLS server: $e");
      },
    );
  } catch (e) {
    print("Failed to start DTLS server: $e");
    await dtlsServer?.close();
  }
}
