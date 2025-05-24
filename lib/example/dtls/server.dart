import 'dart:io';

import '../../src/dtls/cipher/const.dart';
import '../../src/dtls/context/cipher.dart';
import '../../src/dtls/dtls_server.dart';

Future<void> main() async {
  final (certPem, keyPem, signatureHash) =
      CipherContext.createSelfSignedCertificateWithKey(
    SignatureHash(HashAlgorithm.sha256_4, SignatureAlgorithm.ecdsa_3),
    NamedCurveAlgorithm.secp256r1_23,
  );

  final server = DtlsServer(
    await RawDatagramSocket.bind("127.0.0.1", 4444).then((socket) {
      return socket;
    }),
    extendedMasterSecret: true,
    certPem: certPem,
    keyPem: keyPem,
    signatureHash: signatureHash,
  );
}
