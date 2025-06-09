// Placeholder for HandshakeContext. You'll need to define this based on your Go code.
// For now, it's a minimal class to allow the code to compile.
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_webrtc/src/dtls2/crypto_gcm.dart';
import 'package:dart_webrtc/src/dtls2/dtls.dart';
import 'package:dart_webrtc/src/dtls2/enums.dart';
import 'package:dart_webrtc/src/dtls2/extensions.dart';

import 'cert_utils.dart';
import 'crypto.dart';
import 'handshake_header.dart';
import 'handshaker/server.dart';

class HandshakeContext {
  int clientEpoch = 0;
  int serverEpoch = 0;
  bool isCipherSuiteInitialized = false;
  RawDatagramSocket serverSocket;
  String ip;
  int port;

  EcdsaCert serverEcCertificate;
  // HandshakeContext(this.serverEcCertificate);

  Flight flight = Flight.Flight0;

  late Uint8List cookie;

  late DtlsRandom clientRandom;

  late ProtocolVersion protocolVersion;

  int serverHandshakeSequenceNumber = 0;
  int serverSequenceNumber = 0;

  Map<HandshakeType, Uint8List> handshakeMessagesSent = {};
  Map<HandshakeType, Uint8List> handshakeMessagesReceived = {};
  late List<int> sessionId;

  late List<int> compressionMethods;
  late int compressionMethodID;

  late Map<ExtensionTypeValue, Extension> extensions;

  late DtlsRandom serverRandom;

  late Uint8List serverPublicKey;

  late Uint8List serverPrivateKey;

  late Uint8List serverKeySignature;

  late Uint8List clientKeyExchangePublic;

  late Uint8List serverMasterSecret;

  late GCM gcm;

  DTLSState dTLSState = DTLSState.disconnected;

  Function? onConnected;

  HandshakeContext(
      this.serverSocket, this.ip, this.port, this.serverEcCertificate,
      {this.onConnected});
  // GCM cipher; // Uncomment and define if you have a GCM implementation

  void increaseServerHandshakeSequence() {
    serverHandshakeSequenceNumber++;
  }

  void increaseServerEpoch() {
    serverEpoch++;
    serverSequenceNumber = 0;
  }

  void increaseServerSequence() {
    serverSequenceNumber++;
  }

  // https://github.com/pion/dtls/blob/bee42643f57a7f9c85ee3aa6a45a4fa9811ed122/state.go#L182
  Uint8List exportKeyingMaterial(int length) {
    final encodedClientRandom = clientRandom.encode();
    final encodedServerRandom = serverRandom.encode();

    print(
        "Exporting keying material from DTLS context (expected length: $length)...");
    final keyingMaterialCache = generateKeyingMaterial(
        serverMasterSecret, encodedClientRandom, encodedServerRandom, length);

    return keyingMaterialCache;
  }
}
