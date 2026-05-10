// Builders for outgoing DTLS handshake messages from the server.

import 'dart:typed_data';

import '../../dtls3/extensions.dart';
import '../../dtls3/simple_extensions.dart';
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
    // Build a *server-side* extensions map. We MUST NOT echo back the
    // client's extension map verbatim — many extensions (e.g.
    // supported_groups, signature_algorithms) are illegal in a ServerHello
    // and modern stacks (Chrome / Firefox) reject the handshake with a
    // fatal `decode_error` alert if they appear.
    final clientExt = context.extensions;
    final serverExt = <ExtensionTypeValue, Extension>{};

    // extended_master_secret (RFC 7627) — empty body. Echo only if the
    // client offered it; required in WebRTC.
    if (clientExt.containsKey(ExtensionTypeValue.UseExtendedMasterSecret)) {
      context.UseExtendedMasterSecret = true;
      serverExt[ExtensionTypeValue.UseExtendedMasterSecret] =
          ExtUseExtendedMasterSecret();
    }

    // renegotiation_info (RFC 5746) — empty `renegotiated_connection` for
    // the initial handshake.
    serverExt[ExtensionTypeValue.RenegotiationInfo] = ExtRenegotiationInfo();

    // ec_point_formats — uncompressed (0) only.
    serverExt[ExtensionTypeValue.SupportedPointFormats] =
        ExtSupportedPointFormats([0]);

    // use_srtp (RFC 5764) — pick one profile from the client's list.
    // WebRTC requires this; without it the browser cannot derive SRTP keys.
    final clientUseSrtp = clientExt[ExtensionTypeValue.UseSrtp] as ExtUseSRTP?;
    if (clientUseSrtp != null && clientUseSrtp.protectionProfiles.isNotEmpty) {
      // Prefer SRTP_AEAD_AES_128_GCM (0x0007), then AES128_CM_HMAC_SHA1_80
      // (0x0001). Fall back to whatever the client put first.
      const preferred = [0x0007, 0x0001];
      int chosen = clientUseSrtp.protectionProfiles.first;
      for (final p in preferred) {
        if (clientUseSrtp.protectionProfiles.contains(p)) {
          chosen = p;
          break;
        }
      }
      context.srtpProtectionProfile = chosen;
      serverExt[ExtensionTypeValue.UseSrtp] =
          ExtUseSRTP([chosen], Uint8List(0));
    }

    return ServerHello(
      ProtocolVersion(254, 253),
      context.serverRandom,
      context.session_id.length,
      context.session_id,
      CipherSuiteId.Tls_Ecdhe_Ecdsa_With_Aes_128_Gcm_Sha256.value,
      context.compression_methods[0],
      serverExt,
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
