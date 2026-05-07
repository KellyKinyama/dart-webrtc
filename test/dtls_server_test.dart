// Integration test for the new modular [DtlsServer] / [DtlsSession]
// dispatcher. Drives a full DTLS 1.2 handshake against the existing
// [DtlsClient] and confirms that an application_data record is delivered
// through the per-peer [DtlsSession.onApplicationData] callback.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/src/dtls/examples/client/dtls_client.dart';
import 'package:pure_dart_webrtc/src/dtls/server/dtls_server.dart';
import 'package:pure_dart_webrtc/src/dtls/server/dtls_session.dart';
import 'package:pure_dart_webrtc/src/dtls/tests/verify_ecdsa_256_cert1.dart';
import 'package:test/test.dart';

void main() {
  test('DtlsServer accepts a DtlsClient and surfaces application_data',
      () async {
    final server = await DtlsServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      certificate: generateSelfSignedCertificate(),
    );
    addTearDown(server.close);

    final connectedCompleter = Completer<DtlsSession>();
    final appDataCompleter = Completer<Uint8List>();

    server.onSession = (session, _, __) {
      session.onConnected = () {
        if (!connectedCompleter.isCompleted) {
          connectedCompleter.complete(session);
        }
      };
      session.onApplicationData = (data) {
        if (!appDataCompleter.isCompleted) {
          appDataCompleter.complete(data);
        }
      };
    };

    final client = DtlsClient(InternetAddress.loopbackIPv4, server.port);
    addTearDown(client.close);

    await client.connect().timeout(const Duration(seconds: 10));

    final session =
        await connectedCompleter.future.timeout(const Duration(seconds: 5));
    expect(session.isConnected, isTrue);

    final payload = Uint8List.fromList('hello-modular'.codeUnits);
    await client.sendApplicationData(payload);

    final received =
        await appDataCompleter.future.timeout(const Duration(seconds: 5));
    expect(received, equals(payload));
  }, timeout: const Timeout(Duration(seconds: 25)));

  test('handshake completes when records are fragmented (small MTU)', () async {
    // Force every server-sent handshake message that exceeds 80 body
    // bytes (Certificate ~295 B, ServerKeyExchange ~140 B, even
    // ServerHello may exceed) to be split across multiple DTLS records.
    final server = await DtlsServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      certificate: generateSelfSignedCertificate(),
      maxHandshakeFragmentLength: 80,
    );
    addTearDown(server.close);

    final connectedCompleter = Completer<DtlsSession>();
    final appDataCompleter = Completer<Uint8List>();

    server.onSession = (session, _, __) {
      session.onConnected = () {
        if (!connectedCompleter.isCompleted) {
          connectedCompleter.complete(session);
        }
      };
      session.onApplicationData = (data) {
        if (!appDataCompleter.isCompleted) {
          appDataCompleter.complete(data);
        }
      };
    };

    final client = DtlsClient(InternetAddress.loopbackIPv4, server.port);
    addTearDown(client.close);

    await client.connect().timeout(const Duration(seconds: 10));

    final session =
        await connectedCompleter.future.timeout(const Duration(seconds: 5));
    expect(session.isConnected, isTrue);

    final payload = Uint8List.fromList('hello-fragmented'.codeUnits);
    await client.sendApplicationData(payload);

    final received =
        await appDataCompleter.future.timeout(const Duration(seconds: 5));
    expect(received, equals(payload));
  }, timeout: const Timeout(Duration(seconds: 25)));
}
