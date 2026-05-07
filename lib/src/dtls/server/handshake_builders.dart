// Builders for outgoing DTLS handshake messages from the server.

import 'dart:typed_data';

import '../crypto.dart';
import '../handshake/certificate.dart';
import '../handshake/change_cipher_spec.dart';
import '../handshake/finished.dart';
import '../handshake/handshake.dart';
import '../handshake/handshake_context.dart';
import '../handshake/hello_verify_request.dart';
import '../handshake/server_hello.dart';
import '../handshake/server_hello_done.dart';
import '../handshake/server_key_exchange.dart';
import '../tests/verify_ecdsa_256_cert1.dart';

import 'cookie.dart';

/// Convenience namespace for outgoing handshake message constructors.
class HandshakeBuilders {
  HandshakeBuilders._();

  static HelloVerifyRequest helloVerifyRequest(HandshakeContext context) {
    return HelloVerifyRequest(
      version: context.protocolVersion,
      cookie: generateDtlsCookie(),
    );
  }

  static ServerHello serverHello(HandshakeContext context) {
    // Mark Extended Master Secret as in-use; the existing HandshakeContext
    // is also flagged for downstream key derivation.
    context.UseExtendedMasterSecret = true;
    return ServerHello(
      ProtocolVersion(254, 253),
      context.serverRandom,
      context.session_id.length,
      context.session_id,
      CipherSuiteId.Tls_Ecdhe_Ecdsa_With_Aes_128_Gcm_Sha256.value,
      context.compression_methods[0],
      context.extensions,
      extensionsData: context.extensionsData,
    );
  }

  static Certificate certificate(EcdsaCert serverCert) {
    return Certificate(certificate: [serverCert.cert]);
  }

  static ServerKeyExchange serverKeyExchange(HandshakeContext context) {
    return ServerKeyExchange(
      identityHint: const [],
      ellipticCurveType: EllipticCurveType.NamedCurve,
      namedCurve: NamedCurve.prime256v1,
      publicKey: context.serverPublicKey,
      signatureHashAlgorithm: SignatureHashAlgorithm(
        hash: HashAlgorithm.Sha256,
        signatureAgorithm: SignatureAlgorithm.Ecdsa,
      ),
      signature: context.serverKeySignature,
    );
  }

  static ServerHelloDone serverHelloDone() => ServerHelloDone();

  static ChangeCipherSpec changeCipherSpec() => ChangeCipherSpec();

  static Finished finished(Uint8List verifyData) => Finished(verifyData);
}
