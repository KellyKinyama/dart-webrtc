import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart' as crypto;
// import 'package:dart_webrtc/src/dtls/hex2.dart';
// import 'package:ecdsa/ecdsa.dart' as ecdsa;
// import 'package:elliptic/elliptic.dart' as ec;
// import 'package:pointycastle/export.dart' as pc;
// import 'package:asn1lib/asn1lib.dart';

import '../../../signal/fingerprint.dart';
import 'ecdsa.dart'; // Assuming this file contains ecdsaSign and ecdsaVerify

// Private Key PEM:
const constEcPubKey = """-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIH20P2HOwfaKhh/GuaB+1bGJPRnOravjwj3guXHHfKa6oAoGCCqGSM49
AwEHoUQDQgAE6vBg4dCF5EpP/F9QJfzf08pZyMPkStHKKnLsWctLpQ7OH9X08/8X
oPw+4fpsFMkuJGNdeqR5fmZgsGQT+HcwKg==
-----END EC PRIVATE KEY-----""";

// Public Key PEM:
const constPubKey = """-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE6vBg4dCF5EpP/F9QJfzf08pZyMPk
StHKKnLsWctLpQ7OH9X08/8XoPw+4fpsFMkuJGNdeqR5fmZgsGQT+HcwKg==
-----END PUBLIC KEY-----""";

const constCert = """-----BEGIN CERTIFICATE-----
MIIBHDCBwaADAgECAgEBMAwGCCqGSM49BAMCBQAwFjEUMBIGA1UEAxMLU2VsZi1T
aWduZWQwHhcNMjUwNjAxMTMzMzAwWhcNMjYwNjAxMTMzMzAwWjAWMRQwEgYDVQQD
EwtTZWxmLVNpZ25lZDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABOrwYOHQheRK
T/xfUCX839PKWcjD5ErRyipy7FnLS6UOzh/V9PP/F6D8PuH6bBTJLiRjXXqkeX5m
YLBkE/h3MCowDAYIKoZIzj0EAwIFAANIADBFAiEAqZR1wnX+hs/BeU4V0NlumNfr
bnWc/Ig47ou5PknNix4CIGbfTkFDVnBFEj1YOqoMyNreTnCFA6pGVZbiMvSdkz+e
-----END CERTIFICATE-----""";

class EcdsaCert {
  Uint8List cert;
  Uint8List privateKey; // Raw private key (scalar)
  Uint8List publickKey; // Raw public key (uncompressed point)
  EcdsaCert(
      {required this.privateKey, required this.publickKey, required this.cert});

  // factory EcdsaCert.fromPem({required String certPem, required String publickKeyPem, required String privateKeyPem}){

  // }

  // factory EcdsaCert.fromConstPem(){
  //   X509Utils.

  // }
}

EcdsaCert generateSelfSignedCertificate() {
  var pair = CryptoUtils.generateEcKeyPair();
  var privKey = pair.privateKey as ECPrivateKey;
  var pubKey = pair.publicKey as ECPublicKey;
  var dn = {
    'CN': 'Self-Signed',
  };
  var csr = X509Utils.generateEccCsrPem(dn, privKey, pubKey);

  // Encode private key to PEM
  String privateKeyPem = CryptoUtils.encodeEcPrivateKeyToPem(privKey);
  // print("Private Key PEM:\n$privateKeyPem\n");

  // Encode public key to PEM
  String publicKeyPem = CryptoUtils.encodeEcPublicKeyToPem(pubKey);
  // print("Public Key PEM:\n$publicKeyPem\n");

  var x509PEM = X509Utils.generateSelfSignedCertificate(
    privKey,
    csr,
    365,
  );

  // Extract raw public key and private key from the Pointy Castle objects
  Uint8List rawPublicKey = _encodeECPublicKeyToRaw(pubKey);
  Uint8List rawPrivateKey = _encodeECPrivateKeyToRaw(privKey);

  // print("Raw Public Key length: ${rawPublicKey.length}");
  final certDer = decodePemToDer(x509PEM);

  print("Certificate finger print: ${fingerprint(certDer)}");

  // print("Certificate PEM:\n$x509PEM\n");
  return EcdsaCert(
      privateKey: rawPrivateKey, publickKey: rawPublicKey, cert: certDer);
}

// String fingerprint(Uint8List certDer) {
//   return certDer
//       .map((b) => b.toRadixString(16).padLeft(2, '0'))
//       .join(":")
//       .toUpperCase();
// }

// Helper to decode PEM to DER (your existing function)
Uint8List decodePemToDer(pem) {
  var startsWith = [
    '-----BEGIN PUBLIC KEY-----',
    '-----BEGIN PRIVATE KEY-----',
    '-----BEGIN CERTIFICATE-----',
    '-----BEGIN EC PRIVATE KEY-----'
  ];
  var endsWith = [
    '-----END PUBLIC KEY-----',
    '-----END PRIVATE KEY-----',
    '-----END CERTIFICATE-----',
    '-----END EC PRIVATE KEY-----'
  ];

  for (var s in startsWith) {
    if (pem.startsWith(s)) pem = pem.substring(s.length);
  }

  for (var s in endsWith) {
    if (pem.endsWith(s)) pem = pem.substring(0, pem.length - s.length);
  }

  pem = pem.replaceAll('\n', '');
  pem = pem.replaceAll('\r', '');
  return Uint8List.fromList(base64.decode(pem));
}

// New helper to extract raw public key bytes (uncompressed)
// Uint8List _encodeECPublicKeyToRaw(ECPublicKey publicKey) {
//   // Pointy Castle's ECPublicKey stores the Q (point) which can be encoded directly.
//   // The '04' prefix indicates uncompressed format.
//   // The curve used by basic_utils is prime256v1, which means x and y are 32 bytes each.
//   final xBytes = publicKey.Q!.x!.toUnsignedBigInt().asBytes();
//   final yBytes = publicKey.Q!.y!.toUnsignedBigInt().asBytes();

//   final xBytes = publicKey.Q!.x!.toBigInteger();
//   final yBytes = publicKey.Q!.y!.toBigInteger();

//   // Ensure x and y are 32 bytes long, padded with leading zeros if necessary
//   final paddedX = Uint8List(32);
//   paddedX.setRange(32 - xBytes.length, 32, xBytes);

//   final paddedY = Uint8List(32);
//   paddedY.setRange(32 - yBytes.length, 32, yBytes);

//   return Uint8List.fromList([0x04, ...paddedX, ...paddedY]);
// }

// New helper to extract raw public key bytes (uncompressed)
Uint8List _encodeECPublicKeyToRaw(ECPublicKey publicKey) {
  // Pointy Castle's ECPublicKey stores the Q (point)
  // For prime256v1, coordinates are 32 bytes.
  // final expectedByteLength = (publicKey.parameters!.curve.fieldSize + 7) ~/ 8;

  // Use toBytesPadded directly on the BigInt from the ECPoint
  final paddedX = bigIntToUint8List(
      publicKey.Q!.x!.toBigInteger()!); //.toBytesPadded(expectedByteLength);
  final paddedY = bigIntToUint8List(
      publicKey.Q!.y!.toBigInteger()!); //.toBytesPadded(expectedByteLength);
  print("Padded X length: ${paddedX.length}");
  print("Padded Y length: ${paddedY.length}");
  // Ensure x and y are 32 bytes long, padded with leading zeros if necessary

  return Uint8List.fromList([0x04, ...paddedX, ...paddedY]);
}

// New helper to extract raw private key bytes (scalar)
Uint8List _encodeECPrivateKeyToRaw(ECPrivateKey privateKey) {
  // Pointy Castle's ECPrivateKey stores the d (scalar)
  final dBytes = bigIntToUint8List(privateKey.d!);

  // Ensure the private key is 32 bytes long for prime256v1
  final paddedD = Uint8List(32);
  paddedD.setRange(32 - dBytes.length, 32, dBytes);
  return paddedD;
}

Uint8List bigIntToUint8List(BigInt bigInt) =>
    bigIntToByteData(bigInt).buffer.asUint8List();

ByteData bigIntToByteData(BigInt bigInt) {
  final data = ByteData((bigInt.bitLength / 8).ceil());
  var _bigInt = bigInt;

  for (var i = 1; i <= data.lengthInBytes; i++) {
    data.setUint8(data.lengthInBytes - i, _bigInt.toUnsigned(8).toInt());
    _bigInt = _bigInt >> 8;
  }

  return data;
}

// Uint8List Uint8ListBigInt(BigInt bigInt) =>
//     bigIntToByteData(bigInt).buffer.asUint8List();

// ByteData bigIntToByteData(BigInt bigInt) {
//   final data = ByteData((bigInt.bitLength / 8).ceil());
//   var _bigInt = bigInt;

//   for (var i = 1; i <= data.lengthInBytes; i++) {
//     data.setUint8(data.lengthInBytes - i, _bigInt.toUnsigned(8).toInt());
//     _bigInt = _bigInt >> 8;
//   }

//   return data;
// }

void testCertificateVerify() {
  //test ECDSA256
  final certificateEcdsa256 = generateSelfSignedCertificate();

  print("Raw Public key length: ${certificateEcdsa256.publickKey.length}");
  print("Raw Private key length: ${certificateEcdsa256.privateKey.length}");

  final hash = crypto.sha256.convert(plainText).bytes;

  final certVerifyEcdsa256 = ecdsaSign(certificateEcdsa256.privateKey, hash);

  print("Signature length: ${certVerifyEcdsa256.length}");
  final verified = ecdsaVerify(
    certificateEcdsa256.publickKey,
    hash,
    certVerifyEcdsa256,
  );
  print("Verification ${verified ? 'successful!' : 'failed'}");
}

void main() {
  testCertificateVerify();
}

// void main() {
//   final certificateEcdsa256 = generateSelfSignedCertificate();
//   // var ec = getP256();
//   // var priv = certificateEcdsa256.privateKey;
//   final priv =
//       ec.PrivateKey.fromBytes(ec.getP256(), certificateEcdsa256.privateKey);

//   // var pub = priv.publicKey;
//   final pub = ec.PublicKey.fromHex(
//       ec.getP256(), hexEncode(certificateEcdsa256.publickKey));
//   print("priv: ${priv.toHex()}");
//   print("public key:          ${pub.toHex()}");
//   print("Expected public key: ${hexEncode(certificateEcdsa256.publickKey)}");
//   // var hashHex =
//   //     'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9';
//   // var hash = hexDecode(hashHex);
//   final hash = crypto.sha256.convert(plainText).bytes;
//   // print("hash: $hash");

//   var sig = ecdsa.signature(priv, hash);
//   print("Signature:     $sig");
//   print("Sig ASN1:      ${sig.toASN1Hex()}");
//   print("Sig Der Hex:   ${sig.toDERHex()}");
//   // print("Sig Compact Hex:   ${sig.toCompactHex()}");

//   var sig2 = ecdsaSign(certificateEcdsa256.privateKey, hash);
//   print("ecdsaSign:     ${hexEncode(sig2)}");

//   var result = ecdsa.verify(pub, hash, ecdsa.Signature.fromASN1(sig2));
//   print("Is verified: $result");
//   final verified = ecdsaVerify(certificateEcdsa256.publickKey, hash, sig2);
//   print("Is ecdsa verified: $verified");
// }

final plainText = Uint8List.fromList([
  0x6f,
  0x47,
  0x97,
  0x85,
  0xcc,
  0x76,
  0x50,
  0x93,
  0xbd,
  0xe2,
  0x6a,
  0x69,
  0x0b,
  0xc3,
  0x03,
  0xd1,
  0xb7,
  0xe4,
  0xab,
  0x88,
  0x7b,
  0xa6,
  0x52,
  0x80,
  0xdf,
  0xaa,
  0x25,
  0x7a,
  0xdb,
  0x29,
  0x32,
  0xe4,
  0xd8,
  0x28,
  0x28,
  0xb3,
  0xe8,
  0x04,
  0x3c,
  0x38,
  0x16,
  0xfc,
  0x78,
  0xe9,
  0x15,
  0x7b,
  0xc5,
  0xbd,
  0x7d,
  0xfc,
  0xcd,
  0x83,
  0x00,
  0x57,
  0x4a,
  0x3c,
  0x23,
  0x85,
  0x75,
  0x6b,
  0x37,
  0xd5,
  0x89,
  0x72,
  0x73,
  0xf0,
  0x44,
  0x8c,
  0x00,
  0x70,
  0x1f,
  0x6e,
  0xa2,
  0x81,
  0xd0,
  0x09,
  0xc5,
  0x20,
  0x36,
  0xab,
  0x23,
  0x09,
  0x40,
  0x1f,
  0x4d,
  0x45,
  0x96,
  0x62,
  0xbb,
  0x81,
  0xb0,
  0x30,
  0x72,
  0xad,
  0x3a,
  0x0a,
  0xac,
  0x31,
  0x63,
  0x40,
  0x52,
  0x0a,
  0x27,
  0xf3,
  0x34,
  0xde,
  0x27,
  0x7d,
  0xb7,
  0x54,
  0xff,
  0x0f,
  0x9f,
  0x5a,
  0xfe,
  0x07,
  0x0f,
  0x4e,
  0x9f,
  0x53,
  0x04,
  0x34,
  0x62,
  0xf4,
  0x30,
  0x74,
  0x83,
  0x35,
  0xfc,
  0xe4,
  0x7e,
  0xbf,
  0x5a,
  0xc4,
  0x52,
  0xd0,
  0xea,
  0xf9,
  0x61,
  0x4e,
  0xf5,
  0x1c,
  0x0e,
  0x58,
  0x02,
  0x71,
  0xfb,
  0x1f,
  0x34,
  0x55,
  0xe8,
  0x36,
  0x70,
  0x3c,
  0xc1,
  0xcb,
  0xc9,
  0xb7,
  0xbb,
  0xb5,
  0x1c,
  0x44,
  0x9a,
  0x6d,
  0x88,
  0x78,
  0x98,
  0xd4,
  0x91,
  0x2e,
  0xeb,
  0x98,
  0x81,
  0x23,
  0x30,
  0x73,
  0x39,
  0x43,
  0xd5,
  0xbb,
  0x70,
  0x39,
  0xba,
  0x1f,
  0xdb,
  0x70,
  0x9f,
  0x91,
  0x83,
  0x56,
  0xc2,
  0xde,
  0xed,
  0x17,
  0x6d,
  0x2c,
  0x3e,
  0x21,
  0xea,
  0x36,
  0xb4,
  0x91,
  0xd8,
  0x31,
  0x05,
  0x60,
  0x90,
  0xfd,
  0xc6,
  0x74,
  0xa9,
  0x7b,
  0x18,
  0xfc,
  0x1c,
  0x6a,
  0x1c,
  0x6e,
  0xec,
  0xd3,
  0xc1,
  0xc0,
  0x0d,
  0x11,
  0x25,
  0x48,
  0x37,
  0x3d,
  0x45,
  0x11,
  0xa2,
  0x31,
  0x14,
  0x0a,
  0x66,
  0x9f,
  0xd8,
  0xac,
  0x74,
  0xa2,
  0xcd,
  0xc8,
  0x79,
  0xb3,
  0x9e,
  0xc6,
  0x66,
  0x25,
  0xcf,
  0x2c,
  0x87,
  0x5e,
  0x5c,
  0x36,
  0x75,
  0x86,
]);
