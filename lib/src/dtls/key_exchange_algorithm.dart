import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart';
import 'package:dartls/src/dtls/crypto/crypto_ccm.dart';
import 'crypto/crypto_ccm8.dart';
import 'ecdsa_example.dart';
import 'handshake/tls_random.dart';
import 'package:hex/hex.dart';
import 'package:x25519/x25519.dart';
import 'package:collection/collection.dart';
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:elliptic/elliptic.dart';

import 'crypto.dart';
import 'crypto/crypto_gcm5.dart';
import 'ecdsa3.dart';
import 'hex2.dart';
import 'prf2.dart';
import 'shared_secret7.dart';

enum ECCurveType {
  Named_Curve(3);

  const ECCurveType(this.value);
  final int value;

  factory ECCurveType.fromInt(int value) {
    switch (value) {
      case 3:
        return Named_Curve;
      default:
        throw ArgumentError('Invalid ECCurveType value: $value');
    }
  }
}

// enum NamedCurve {
//   secp256r1,
//   secp384r1,
//   secp521r1,
//   x25519,
//   x448,
//   ffdhe2048,
//   ffdhe3072,
//   ffdhe4096,
//   ffdhe6144,
//   ffdhe8192;

//   const NamedCurve(this.value);
//   final int value;
// }

// enum NamedCurve {
//   prime256v1(0x0017),
//   prime384v1(0x0018),
//   prime521v1(0x0019),
//   x25519(0x001D),
//   x448(0x001E),
//   ffdhe2048(0x0100),
//   ffdhe3072(0x0101),
//   ffdhe4096(0x0102),
//   ffdhe6144(0x0103),
//   ffdhe8192(0x0104),
//   secp256k1(0x0012);
//   // secp256r1(0x0017),
//   // secp384r1(0x0018),
//   // secp521r1(0x0019),
//   // secp256k1(0x0012),
//   // secp256r1(0x0017),
//   // secp384r1(0x0018),
//   // secp521r1(0x0019),
//   // secp256k1(0x0012),
//   // secp256r1(0x0017),

//   const NamedCurve(this.value);
//   final int value;

//   factory NamedCurve.fromInt(int key) {
//     return values.firstWhere((element) => element.value == key);
//   }
// }

// enum ECCurve { X25519, X448, Curve25519, Curve448 }

void genKeyAndX25519() {
  var aliceKeyPair = generateKeyPair();
  var bobKeyPair = generateKeyPair();

  print("Alice public key: ${HEX.encode(aliceKeyPair.publicKey)}");
  print("Alice private key: ${HEX.encode(aliceKeyPair.privateKey)}");

  print("Bob public key: ${HEX.encode(bobKeyPair.publicKey)}");
  print("object Bob private key: ${HEX.encode(bobKeyPair.privateKey)}");

  var aliceSharedKey = X25519(aliceKeyPair.privateKey, bobKeyPair.publicKey);
  var bobSharedKey = X25519(bobKeyPair.privateKey, aliceKeyPair.publicKey);

  print("Secret is: ${ListEquality().equals(aliceSharedKey, bobSharedKey)}");
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

// ({Uint8List privateKey, Uint8List publicKey}) generateP256Keys() {
//   var ec = getP256();
//   var priv = ec.generatePrivateKey();
//   PublicKey pub = priv.publicKey;

//   // pub.print("public key: ${hexDecode(pub.t).length}");
//   print("priv: ${priv.bytes.length}");
//   print("public key: ${hexDecode(pub.X.toRadixString(8)).length}");

//   // print(HEX.decode(encoded));

//   // var test = ASN1Parser(Uint8List.fromList(hexDecode(pub.toHex())));
//   //  test.

//     final parsed =
//       ASN1Sequence.fromBytes(Uint8List.fromList(hexDecode(pub.toHex())));

//       //  final parsed =
//       // ASN1Sequence.fromBytes(Uint8List.fromList(pemToBytes(publicKeyPem)));

//   return (
//     privateKey: Uint8List.fromList(priv.bytes),
//     publicKey: parsed.encode()
//   );
// }

// Future<({Uint8List privateKey, Uint8List publicKey})> generateP256Keys() async {
//   // In this example, we use ECDSA-P256-SHA256
//   final algorithm = cryptography.Ecdsa.p256(cryptography.Sha256());

//   // Generate a random key pair
//   final kepair = await algorithm.newKeyPair();
//   final publicKey = await kepair.extractPublicKey();

//   final priv = await kepair.extract();

//   // Sign a message
//   // final message = <int>[1, 2, 3];
//   // final signature = await algorithm.sign(
//   //   [1, 2, 3],
//   //   secretKey: secretKey,
//   // );

//   // // Anyone can verify the signature
//   // final isVerified = await algorithm.verify(
//   //   message: message,
//   //   signature: signature,
//   // );

//   return (
//     privateKey: Uint8List.fromList(priv.d),
//     publicKey: Uint8List.fromList(publicKey.toDer())
//   );
// }

({Uint8List privateKey, Uint8List publicKey}) generateX25519Keys() {
  var aliceKeyPair = generateKeyPair();

  print("Alice public key: ${aliceKeyPair.publicKey.length}");
  print("Alice private key: ${aliceKeyPair.privateKey.length}");

  return (
    privateKey: Uint8List.fromList(aliceKeyPair.privateKey),
    publicKey: Uint8List.fromList(aliceKeyPair.publicKey)
  );
}

Uint8List generateKeySignature(Uint8List clientRandom, Uint8List serverRandom,
    Uint8List publicKey, Uint8List privateKey) {
  final msg = generateKeyValueMessages(
      clientRandom, serverRandom, publicKey, privateKey);
  final handshakeMessage = sha256.convert(msg).bytes;
  final signatureBytes = ecdsaSign(privateKey, handshakeMessage);
  return Uint8List.fromList(signatureBytes);
}

// The premaster secret is formed as follows: if the PSK is N octets
// long, concatenate a uint16 with the value N, N zero octets, a second
// uint16 with the value N, and the PSK itself.

//pskLength=PSK.length
//[...setUint16(pskLength),...List.fille(pskLength,0),...setUint16(pskLength),...psk
//
// https://tools.ietf.org/html/rfc4279#section-2
Uint8List prfPskPreMasterSecret(Uint8List psk) {
  final psk_len = psk.length;

  Uint8List pskLengthBytes = Uint8List(2);
  ByteData.sublistView(pskLengthBytes).setUint16(0, psk_len);
  return Uint8List.fromList([
    ...pskLengthBytes,
    ...List.filled(psk_len, 0),
    ...pskLengthBytes,
    ...psk
  ]);

  // out =Uint8List.fromList([]);

  // out.extend_from_slice(psk);
  // let be = (psk_len as u16).to_be_bytes();
  // out[..2].copy_from_slice(&be);
  // out[2 + psk_len..2 + psk_len + 2].copy_from_slice(&be);

  // out
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

// Future<Uint8List> generatePreMasterSecret(
//     Uint8List publicKey, Uint8List privateKey) async {
//   // Initialize the ECDH algorithm (P-256 curve).
//   final algorithm = cryptography.Ecdh.p256(length: 65);

//   // Create the key pair for Alice (using the private key).
//   // final alicePrivateKey = cryptography.SecretKey(privateKey);
//   final aliceKeyPair = await algorithm.newKeyPairFromSeed(privateKey);

//   // Create the public key for Bob (the remote party).
//   final bobPublicKey = cryptography.SimplePublicKey(publicKey,
//       type: cryptography.KeyPairType.x25519);

//   // Calculate the shared secret (premaster secret) using Alice's private key and Bob's public key.
//   final sharedSecretKey = await algorithm.sharedSecretKey(
//     keyPair: aliceKeyPair,
//     remotePublicKey: bobPublicKey,
//   );

//   final sharedSecretKeyBytes = await sharedSecretKey.extractBytes();

//   // Return the 32-byte shared secret (premaster secret).
//   return Uint8List.fromList(sharedSecretKeyBytes);
// }

// Future<Uint8List> generatePreMasterSecret(
//     Uint8List publicKey, Uint8List privateKey) async {
//   // Initialize the ECDH algorithm (P-256 curve).
//   final algorithm = cryptography.Ecdh.p256(length: 65);

//   // Create the SecretKey from the private key.
//   final privateKeyObj = cryptography.SecretKey(privateKey);

//   // Create the public key object from the given public key.
//   final publicKeyObj = cryptography.SimplePublicKey(publicKey,
//       type: cryptography.KeyPairType.p256);

//       algorithm.sharedSecretKey(keyPair: privateKeyObj, remotePublicKey: remotePublicKey)

//   // Calculate the shared secret (premaster secret) using Alice's private key and Bob's public key.
//   final sharedSecretKey = await algorithm.sharedSecretKey(
//     keyPair: await algorithm
//         .newKeyPairFromSeed(privateKey), // Create key pair using private key
//     remotePublicKey: publicKeyObj,
//   );

//   final sharedSecretKeyBytes = await sharedSecretKey.extractBytes();
//   // Return the 32-byte shared secret (premaster secret).
//   return Uint8List.fromList(sharedSecretKeyBytes);
// }

Uint8List generateMasterSecret(
    Uint8List preMasterSecret, Uint8List clientRandom, Uint8List serverRandom) {
  // seed := append(append([]byte("master secret"), clientRandom...), serverRandom...)

  // final random =TlsRandom.defaultInstance();
  final seed = Uint8List.fromList(
      [...utf8.encode("master secret"), ...clientRandom, ...serverRandom]);

  final result = pHash(preMasterSecret, seed, 48);
  print(
      "Generated MasterSecret (not Extended) using Pre-Master Secret, Client Random and Server Random via <u>%s</u>: <u>0x%x</u> (<u>%d bytes</u>) SHA256");
  return result;
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

Uint8List generateKeyingMaterial(Uint8List masterSecret, Uint8List clientRandom,
    Uint8List serverRandom, int length) {
  final seed = Uint8List.fromList([
    ...utf8.encode("EXTRACTOR-dtls_srtp"),
    ...clientRandom,
    ...serverRandom
  ]);
  final result = pHash(masterSecret, seed, length);
  print(
      "Generated Keying Material using Master Secret, Client Random and Server Random via <u>%s</u>: <u>0x%x</u> (<u>%d bytes</u>)");
  return result;
}

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

CCM initCCM(
    Uint8List masterSecret, Uint8List clientRandom, Uint8List serverRandom) {
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

  final gcm = CCM(keys.serverWriteKey, keys.serverWriteIV, keys.clientWriteKey,
      keys.clientWriteIV);
  // if err != nil {
  // 	return nil, err
  // }
  return gcm;
}

CCM8 initCCM8(
    Uint8List masterSecret, Uint8List clientRandom, Uint8List serverRandom) {
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

  final ccm = CCM8(keys.serverWriteKey, keys.serverWriteIV, keys.clientWriteKey,
      keys.clientWriteIV);
  // if err != nil {
  // 	return nil, err
  // }
  return ccm;
}

Uint8List prfVerifyData(
  Uint8List masterSecret,
  Uint8List handshakes,
  String label, [
  int size = 12,
]) {
  final bytes = sha256.convert(handshakes).bytes;
  return pHash(
    masterSecret,
    Uint8List.fromList(utf8.encode(label) + bytes),
    size,
  );
}

Uint8List createHash(Uint8List message) {
  return Uint8List.fromList(sha256.convert(message).bytes);
}

Uint8List prfVerifyDataClient(Uint8List masterSecret, Uint8List handshakes) {
  return prfVerifyData(masterSecret, handshakes, "client finished");
}

Uint8List prfVerifyDataServer(Uint8List masterSecret, Uint8List handshakes) {
  return prfVerifyData(masterSecret, handshakes, "server finished");
}

void main() {
  // genKeyAndX25519();
  final keys = generateX25519Keys();

  var hashHex =
      'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9';
  var hash = hexDecode(hashHex);
  final signatureBytes = ecdsaSign(keys.privateKey, hash);

  var result = ecdsaVerify(keys.publicKey, hash, signatureBytes);

  // var result = verify(pub, hash, Signature.fromCompact(signatureBytes));
  print("Is verified: $result");
}
