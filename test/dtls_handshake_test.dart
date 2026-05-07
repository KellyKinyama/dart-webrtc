// Integration test: runs the DTLS server (HandshakeManager) and the new
// DtlsClient against each other in-process and verifies the handshake
// completes successfully and an application_data record can be exchanged.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/src/dtls/examples/client/dtls_client.dart';
import 'package:pure_dart_webrtc/src/dtls/handshaker/aes_gcm_128_sha_256.dart';
import 'package:pure_dart_webrtc/src/dtls/tests/verify_ecdsa_256_cert1.dart';
import 'package:test/test.dart';

void main() {
  test(
    'DtlsClient completes a full DTLS 1.2 handshake against the server',
    () async {
      // Bind the server to an ephemeral UDP port on the loopback address.
      final serverSocket =
          await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(serverSocket.close);

      final cert = generateSelfSignedCertificate();
      final manager = HandshakeManager(serverSocket, cert);

      final serverSub = serverSocket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = serverSocket.receive();
        if (dg == null) return;
        manager.port = dg.port;
        // Fire-and-forget; processDtlsMessage is async but the server
        // example treats it the same way.
        manager.processDtlsMessage(dg.data);
      });
      addTearDown(serverSub.cancel);

      final client = DtlsClient(
        InternetAddress.loopbackIPv4,
        serverSocket.port,
      );
      addTearDown(client.close);

      await client.connect().timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException(
                'DTLS handshake did not complete within 10s'),
          );

      // If we reach here, both sides verified each other's Finished.
      // Send a piece of application data — the handshaker echoes
      // ApplicationData back on the server side, so this also exercises the
      // record cipher in both directions.
      await client.sendApplicationData(
          Uint8List.fromList([104, 101, 108, 108, 111])); // 'hello'
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
