import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Assuming dtls2 is imported from your pubspec.yaml
// The class definition provided implies these imports are available to dtls2
import 'package:dtls2/dtls2.dart';
import 'package:dtls2/src/dtls_client_context.dart'; // Just for completeness, not directly used here
import 'package:dtls2/src/generated/bindings.dart'; // For SSL_VERIFY_PEER, etc.
import 'package:dtls2/src/ssl.dart'; // For OpenSsl and SSL
import 'package:dtls2/src/context.dart'; // For DtlsServerContext
import 'package:dtls2/src/certificates.dart'; // For Certificate classes
import 'package:ffi/ffi.dart'; // For malloc

void main() async {
  final port = 8080;
  final address = InternetAddress.anyIPv4;

  // Paths to your ECDSA server certificate and private key
  final serverCertificatePath = 'server_ecdsa.crt';
  final serverPrivateKeyPath = 'server_ecdsa.key';

  // Load certificate and private key as Uint8List
  final certificateChainBytes = File(serverCertificatePath).readAsBytesSync();
  final privateKeyBytes = File(serverPrivateKeyPath).readAsBytesSync();

  // The precise cipher suite string for OpenSSL
  final String desiredCipher = 'ECDHE-ECDSA-AES128-GCM-SHA256';

  // Security level for OpenSSL. Level 2 is generally recommended for modern ciphers.
  // Lower it only if you encounter compatibility issues with very old clients.
  const int securityLevel = 2;

  print("Starting DTLS server on $address:$port");
  print("Attempting to use cipher: $desiredCipher");
  print("Using security level: $securityLevel");

  DtlsServer? dtlsServer;

  try {
    // Create a DtlsServerContext instance directly using the constructor
    // as defined in your provided class.
    final dtlsServerContext = DtlsServerContext(
      // For certificate-based authentication, we use DerCertificate for raw bytes.
      // PEM-encoded certificates can be converted or directly read by dtls2 if PemCertificate is used.
      // Ensure your certificates are correctly formatted (DER or PEM).
      // Assuming your generated certs are PEM-encoded and dtls2 handles conversion internally for Certificate objects.
      // The previous examples directly provided Uint8List to DtlsServerContext
      // This is the correct way per your provided class definition.
      rootCertificates: [
        PemCertificate(bytes: certificateChainBytes)
      ],
      // The private key is implicitly tied to the certificate and doesn't go into rootCertificates directly
      // It's part of the internal setup when binding the server.
      // The DtlsServer.bind method will take care of pairing the key with the context.

      ciphers: desiredCipher, // Set the desired cipher string
      securityLevel: securityLevel, // Apply the security level
      verify: true, // Enable peer verification (recommended for security)
      withTrustedRoots: false, // Set to true if you want to use system trusted roots
                               // and your server.crt is signed by a well-known CA.
                               // For self-signed, keep false or add server.crt to rootCertificates.
    );

    // DtlsServer.bind requires the private key separately, which it then
    // associates with the SSL_CTX created from DtlsServerContext.
    dtlsServer = await DtlsServer.bind(
      address,
      port,
      dtlsServerContext,
      privateKeyBytes: privateKeyBytes, // Provide the private key here
    );

    print("DTLS server listening...");

    dtlsServer.listen(
      (connection) {
        print("New DTLS connection from ");
        print("Negotiated cipher:"); // Should be ECDHE-ECDSA-AES128-GCM-SHA256
        print("Negotiated protocol: "); // Likely DTLSv1.2

        connection.listen(
          (event) async {
            print("Received data from client: ${utf8.decode(event.data)}");
            await connection.send(utf8.encode("Hello Client! Your ECDSA GCM connection is secure."));
          },
          onDone: () {
            print("Client connection closed: ");
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