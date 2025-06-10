import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as pc;

import 'crypto_gcm.dart';
import 'ecdsa.dart';
import 'enums.dart';
import 'shared_secret.dart';

// enum HashAlgorithm {
//   Md2(0), // Blacklisted
//   Md5(1), // Blacklisted
//   Sha1(2), // Blacklisted
//   Sha224(3),
//   Sha256(4),
//   Sha384(5),
//   Sha512(6),
//   Ed25519(8),
//   unsupported(255),
//   sha256(2);

//   const HashAlgorithm(this.value);
//   final int value;

//   factory HashAlgorithm.fromInt(int key) {
//     return values.firstWhere((element) => element.value == key);
//   }
// }

// enum SignatureAlgorithm {
//   Rsa(1),
//   Ecdsa(3),
//   Ed25519(7),
//   unsupported(255);

//   const SignatureAlgorithm(this.value);
//   final int value;

//   factory SignatureAlgorithm.fromInt(int key) {
//     return values.firstWhere((element) {
//       return element.value == key;
//     }, orElse: () {
//       return SignatureAlgorithm.unsupported;
//     });
//   }
// }

// class SignatureHashAlgorithm {
//   final HashAlgorithm hash;
//   final SignatureAlgorithm signatureAgorithm;

//   SignatureHashAlgorithm({required this.hash, required this.signatureAgorithm});

//   @override
//   String toString() {
//     return 'SignatureHashAlgorithm(hash: $hash, signature: $signatureAgorithm)';
//   }
// }

class EncryptionKeys {
  final Uint8List masterSecret;
  final Uint8List clientWriteKey;
  final Uint8List serverWriteKey;
  final Uint8List clientWriteIV;
  final Uint8List serverWriteIV;

  EncryptionKeys({
    required this.masterSecret,
    required this.clientWriteKey,
    required this.serverWriteKey,
    required this.clientWriteIV,
    required this.serverWriteIV,
  });

  @override
  String toString() {
    return '''
EncryptionKeys(
  masterSecret: $masterSecret}
  clientWriteKey: $clientWriteKey}
  serverWriteKey: $serverWriteKey}
  clientWriteIV: $clientWriteIV}
  serverWriteIV: $serverWriteIV}
)''';
  }
}

Uint8List generateKeyValueMessages(Uint8List clientRandom,
    Uint8List serverRandom, Uint8List publicKey, Uint8List privateKey) {
  ByteData serverECDHParams = ByteData(4);
  serverECDHParams.setUint8(0, ECCurveType.Named_Curve.value);
  serverECDHParams.setUint16(1, NamedCurve.prime256v1.value);
  serverECDHParams.setUint8(3, publicKey.length);

  final bb = BytesBuilder();
  bb.add(clientRandom);
  bb.add(serverRandom);
  bb.add(serverECDHParams.buffer.asUint8List());
  bb.add(publicKey);

  return bb.toBytes();
}

Uint8List generateKeySignature(Uint8List clientRandom, Uint8List serverRandom,
    Uint8List publicKey, Uint8List privateKey) {
  final msg = generateKeyValueMessages(
      clientRandom, serverRandom, publicKey, privateKey);
  final handshakeMessage = pc.sha256.convert(msg).bytes;
  final signatureBytes = ecdsaSign(privateKey, handshakeMessage);
  return Uint8List.fromList(signatureBytes);
}

Uint8List generatePreMasterSecret(Uint8List publicKey, Uint8List privateKey) {
  // final algorithm =cryptography.Ecdh.p256(length: 32);

  // We can now calculate a 32-byte shared secret key.
  // final sharedSecretKey = await algorithm.sharedSecretKey(
  //   keyPair: aliceKeyPair,
  //   remotePublicKey: bobPublicKey,
  // );
  // TODO: For now, it generates only using X25519
  // https://github.com/pion/dtls/blob/bee42643f57a7f9c85ee3aa6a45a4fa9811ed122/pkg/crypto/prf/prf.go#L106
  // return X25519(privateKey, publicKey);
  // return X25519(publicKey, privateKey);
  return generateP256SharedSecret(publicKey, privateKey);
}

Uint8List createHash(Uint8List message) {
  return Uint8List.fromList(pc.sha256.convert(message).bytes);
}

Uint8List generateExtendedMasterSecret(
    Uint8List preMasterSecret, Uint8List handshakeHash) {
  final seed = Uint8List.fromList(
      [...utf8.encode("extended master secret"), ...handshakeHash]);
  final result = pHash(preMasterSecret, seed, 48);
  print(
      "Generated extended MasterSecret using Pre-Master Secret, Client Random and Server Random via <u>%s</u>: <u>0x%x</u> (<u>%d bytes</u>) SHA256");
  return result;
}

Uint8List generateKeyingMaterial(
    Uint8List masterSecret,
    Uint8List clientRandom,
    Uint8List serverRandom,
// , hashAlgorithm HashAlgorithm,
    int length) {
  final seed = Uint8List.fromList([
    ...utf8.encode("EXTRACTOR-dtls_srtp"),
    ...clientRandom,
    ...serverRandom
  ]);
  final result = pHash(masterSecret, seed, length //, hashAlgorithm
      );

  print(
      "Generated Keying Material using Master Secret, Client Random and Server Random via SHA-256: \n$result \n${result.length} bytes)");
  return result;
}

/// P_hash function using HMAC-SHA256
Uint8List pHash(Uint8List secret, Uint8List seed, int outputLength) {
  List<int> result = [];
  Uint8List a = seed;

  while (result.length < outputLength) {
    // A(i) = HMAC(secret, A(i-1))
    a = hmacSha256(secret, a);

    // HMAC(secret, A(i) + seed)
    Uint8List hmacResult = hmacSha256(secret, Uint8List.fromList(a + seed));

    result.addAll(hmacResult);
  }

  return Uint8List.fromList(result.sublist(0, outputLength));
}

/// Computes HMAC-SHA256
Uint8List hmacSha256(Uint8List key, Uint8List data) {
  var hmac = pc.Hmac(pc.sha256, key);
  return Uint8List.fromList(hmac.convert(data).bytes);
}

Future<GCM> initGCM(Uint8List masterSecret, Uint8List clientRandom,
    Uint8List serverRandom) async {
  //https://github.com/pion/dtls/blob/bee42643f57a7f9c85ee3aa6a45a4fa9811ed122/internal/ciphersuite/tls_ecdhe_ecdsa_with_aes_128_gcm_sha256.go#L60
  // const (
  final prfKeyLen = 16;
  final prfIvLen = 4;
  // )
  // logging.Descf(logging.ProtoCRYPTO, "Initializing GCM with Key Length: <u>%d</u>, IV Length: <u>%d</u>, these values are constants of <u>%s</u> cipher suite.",
  // 	prfKeyLen, prfIvLen, "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256")

  final keys = generateEncryptionKeys(
      masterSecret, clientRandom, serverRandom, prfKeyLen, prfIvLen);
  // if err != nil {
  // 	return nil, err
  // }

  // logging.Descf(logging.ProtoCRYPTO, "Generated encryption keys from keying material (Key Length: <u>%d</u>, IV Length: <u>%d</u>) (<u>%d bytes</u>)\n\tMasterSecret: <u>0x%x</u> (<u>%d bytes</u>)\n\tClientWriteKey: <u>0x%x</u> (<u>%d bytes</u>)\n\tServerWriteKey: <u>0x%x</u> (<u>%d bytes</u>)\n\tClientWriteIV: <u>0x%x</u> (<u>%d bytes</u>)\n\tServerWriteIV: <u>0x%x</u> (<u>%d bytes</u>)",
  // 	prfKeyLen, prfIvLen, prfKeyLen*2+prfIvLen*2,
  // 	keys.MasterSecret, len(keys.MasterSecret),
  // 	keys.ClientWriteKey, len(keys.ClientWriteKey),
  // 	keys.ServerWriteKey, len(keys.ServerWriteKey),
  // 	keys.ClientWriteIV, len(keys.ClientWriteIV),
  // 	keys.ServerWriteIV, len(keys.ServerWriteIV))

  final gcm = await GCM.create(keys.serverWriteKey, keys.serverWriteIV,
      keys.clientWriteKey, keys.clientWriteIV);
  // if err != nil {
  // 	return nil, err
  // }
  return gcm;
}

EncryptionKeys generateEncryptionKeys(Uint8List masterSecret,
    Uint8List clientRandom, Uint8List serverRandom, int keyLen, int ivLen) {
  final seed = Uint8List.fromList(
      [...utf8.encode("key expansion"), ...serverRandom, ...clientRandom]);

  final keyMaterial = pHash(masterSecret, seed, (2 * keyLen) + (2 * ivLen));

  // Slicing the key material into separate keys and IVs
  final clientWriteKey = keyMaterial.sublist(0, keyLen);
  final serverWriteKey = keyMaterial.sublist(keyLen, 2 * keyLen);
  final clientWriteIV = keyMaterial.sublist(2 * keyLen, 2 * keyLen + ivLen);
  final serverWriteIV = keyMaterial.sublist(2 * keyLen + ivLen);

  // Return the EncryptionKeys object
  return EncryptionKeys(
    masterSecret: masterSecret,
    clientWriteKey: clientWriteKey,
    serverWriteKey: serverWriteKey,
    clientWriteIV: clientWriteIV,
    serverWriteIV: serverWriteIV,
  );
}

Uint8List prfVerifyDataServer(Uint8List masterSecret, Uint8List handshakes) {
  return prfVerifyData(masterSecret, handshakes, "server finished");
}

Uint8List prfVerifyDataClient(Uint8List masterSecret, Uint8List handshakes) {
  return prfVerifyData(masterSecret, handshakes, "client finished");
}

Uint8List prfVerifyData(
  Uint8List masterSecret,
  Uint8List handshakes,
  String label, [
  int size = 12,
]) {
  final bytes = pc.sha256.convert(handshakes).bytes;
  return pHash(
    masterSecret,
    Uint8List.fromList(utf8.encode(label) + bytes),
    size,
  );
}
