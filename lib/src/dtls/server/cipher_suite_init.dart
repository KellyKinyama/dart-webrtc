// Cipher-suite initialisation for TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256.
//
// Computes the (Extended) Master Secret from the ECDHE pre-master and the
// handshake transcript hash, then derives the AES-128-GCM session keys and
// stores them on the [HandshakeContext].

import 'dart:typed_data';

import '../handshake/handshake_context.dart';
import '../key_exchange_algorithm.dart';

import 'transcript.dart';

/// Initialises the AEAD cipher state on [context] using the values that
/// have already been populated during the handshake (client/server randoms,
/// ECDHE keys and the handshake transcript).
Future<void> initEcdheEcdsaAes128GcmSha256(HandshakeContext context) async {
  final preMasterSecret = generatePreMasterSecret(
    context.clientKeyExchangePublic,
    context.serverPrivateKey,
  );

  final transcript = buildHandshakeTranscript(context);
  final transcriptHash = createHash(transcript);

  context.serverMasterSecret =
      generateExtendedMasterSecret(preMasterSecret, transcriptHash);

  final clientRandomBytes = context.clientRandom.raw();
  final Uint8List serverRandomBytes = context.serverRandom.marshal();

  context.gcm = await initGCM(
    context.serverMasterSecret,
    clientRandomBytes,
    serverRandomBytes,
  );
  context.isCipherSuiteInitialized = true;
}
