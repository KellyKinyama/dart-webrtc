import 'dart:typed_data';

import 'package:dartls/src/dtls/crypto/crypto_ccm.dart';
import 'package:dartls/src/dtls/crypto/crypto_ccm8.dart';

import '../crypto/crypto_gcm5.dart';
import '../dtls_state.dart';
import '../enums.dart';
import 'extension.dart';
import 'handshake.dart';

import '../key_exchange_algorithm.dart';
import 'extensions/extensions.dart';
import 'tls_random.dart';

class HandshakeContext {
  Flight flight = Flight.Flight0;

  late Uint8List serverKeySignature;

  late DTLSState dTLSState;

  late ProtocolVersion protocolVersion;

  late Uint8List cookie;

  late int cipherSuite;

  late TlsRandom clientRandom;

  late TlsRandom serverRandom;

  late Uint8List serverPublicKey;

  late Uint8List serverPrivateKey;

  late int curve;

  late Uint8List expectedFingerprintHash;

  List<Uint8List> clientCertificates = [];

  var clientKeyExchangePublic;

  bool isCipherSuiteInitialized = false;

  Map<HandshakeType, Uint8List> HandshakeMessagesReceived = {};

  Map<HandshakeType, Uint8List> HandshakeMessagesSent = {};

  late Uint8List serverMasterSecret;

  int serverSequenceNumber = 0;

  int serverHandshakeSequenceNumber = 0;

  late Uint8List extensionsData;

  void increaseServerSequence() {
    serverSequenceNumber++;
  }

  void increaseServerHandshakeSequence() {
    serverHandshakeSequenceNumber++;
  }

  int serverEpoch = 0;

  bool UseExtendedMasterSecret = false;

  late int srtpProtectionProfile;

  int clientEpoch = 0;

  late Uint8List session_id;

  Uint8List? keyingMaterialCache;

  List<Extension> extensions = [];

  var compression_methods;

  late GCM gcm;

  late CCM ccm;

  late CCM8 ccm8;
  void increaseServerEpoch() {
    serverEpoch++;
    serverSequenceNumber = 0;
  }

  // https://github.com/pion/dtls/blob/bee42643f57a7f9c85ee3aa6a45a4fa9811ed122/state.go#L182
  Uint8List exportKeyingMaterial(int length)
// ([]byte, error)
  {
    if (keyingMaterialCache != null) {
      return keyingMaterialCache!;
    }
    final encodedClientRandom = clientRandom.raw();
    final encodedServerRandom = serverRandom.marshal();
    // var err error
    print(
        "Exporting keying material from DTLS context (<u>expected length: $length)...");
    keyingMaterialCache = generateKeyingMaterial(
        serverMasterSecret, encodedClientRandom, encodedServerRandom, length);
    // if err != nil {
    // 	return nil, err
    // }
    return keyingMaterialCache!;
  }
}
