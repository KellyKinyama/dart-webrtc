import 'dart:convert';
import 'dart:typed_data';
import 'package:basic_utils/basic_utils.dart';
// import 'package:cryptography/cryptography.dart' as cryptography;
// import 'package:asn1lib/asn1lib.dart' as asn;
import 'package:elliptic/elliptic.dart' as ec;
import 'package:hex/hex.dart';

// import 'dart:convert';
import 'dart:math';
// import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

// import 'hex2.dart';

void ecSignature() {
  // the private key
  // ECPrivateKey? privateKey;

  var keyPair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
  var privateKey = keyPair.privateKey as ECPrivateKey;
  // var publicKey = keyPair.publicKey as ECPublicKey;

  // some bytes to sign
  final bytes = Uint8List(0);

  // a suitable random number generator - create it just once and reuse
  final rand = Random.secure();
  final fortunaPrng = FortunaRandom()
    ..seed(KeyParameter(Uint8List.fromList(List<int>.generate(
      32,
      (_) => rand.nextInt(256),
    ))));

  // the ECDSA signer using SHA-256
  final signer = ECDSASigner(SHA256Digest())
    ..init(
      true,
      ParametersWithRandom(
        PrivateKeyParameter(privateKey!),
        fortunaPrng,
      ),
    );

  // sign the bytes
  final ecSignature = signer.generateSignature(bytes) as ECSignature;

  // encode the two signature values in a common format
  // hopefully this is what the server expects
  final encoded = ASN1Sequence(elements: [
    ASN1Integer(ecSignature.r),
    ASN1Integer(ecSignature.s),
  ]).encode();

  // and finally base 64 encode it
  final signature = base64UrlEncode(encoded);

  print("signature: $signature");
}

/// Generates an EC key pair, a self-signed certificate, and retrieves their PEM and byte formats.
Uint8List generateKeysAndCertificate() {
  // Generate an EC (Elliptic Curve) key pair
  // prime256v1
  var keyPair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
  var privateKey = keyPair.privateKey as ECPrivateKey;
  var publicKey = keyPair.publicKey as ECPublicKey;

  // // Encode private key to PEM
  String privateKeyPem = CryptoUtils.encodeEcPrivateKeyToPem(privateKey);

  // // Encode public key to PEM
  String publicKeyPem = CryptoUtils.encodeEcPublicKeyToPem(publicKey);

  // Generate a self-signed certificate
  var distinguishedName = {'CN': 'Self-Signed'};
  //x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
  var csrPem =
      X509Utils.generateEccCsrPem(distinguishedName, privateKey, publicKey);
  var certificatePem = X509Utils.generateSelfSignedCertificate(
      privateKey, csrPem, 365, keyUsage: [
    KeyUsage.KEY_ENCIPHERMENT,
    KeyUsage.DIGITAL_SIGNATURE,
    KeyUsage.KEY_CERT_SIGN
  ], extKeyUsage: [
    ExtendedKeyUsage.SERVER_AUTH,
    ExtendedKeyUsage.CLIENT_AUTH
  ]);

  X509CertificateData parsedPEM =
      X509Utils.x509CertificateFromPem(certificatePem);

  // print("Certificate: $certificatePem");
  // print("Private key: $privateKeyPem");

  // print("Public key: $publicKeyPem");

  // // Convert PEM to raw bytes
  // List<int> privateKeyBytes = _pemToBytes(privateKeyPem);
  // List<int> publicKeyBytes = _pemToBytes(publicKeyPem);
  List<int> certificateBytes = pemToBytes(certificatePem);

  // // Print PEM values
  // print('Private Key (PEM):\n$privateKeyPem');
  // print('Public Key (PEM):\n$publicKeyPem');
  // print('Certificate (PEM):\n$certificatePem');

  // // Print raw byte values
  // print('Private Key (Bytes): $privateKeyBytes');
  // print('Public Key (Bytes): $publicKeyBytes');
  // print('Certificate (Bytes): $certificateBytes');
  return CryptoUtils.getBytesFromPEMString(certificatePem);

  // return certificatePem;
}

({Uint8List privateKey, Uint8List publicKey}) generateKeys() {
  // Generate an EC (Elliptic Curve) key pair
  // prime256v1
  var keyPair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
  var privateKey = keyPair.privateKey as ECPrivateKey;
  var publicKey = keyPair.publicKey as ECPublicKey;

  // // Encode private key to PEM
  String privateKeyPem = CryptoUtils.encodeEcPrivateKeyToPem(privateKey);

  // // Encode public key to PEM
  String publicKeyPem = CryptoUtils.encodeEcPublicKeyToPem(publicKey);

  // // Print PEM values
  // print('Private Key (PEM):\n$privateKeyPem');
  // print('Public Key (PEM):\n$publicKeyPem');
  // print('Certificate (PEM):\n$certificatePem');

  // // Print raw byte values
  // print('Private Key (Bytes): $privateKeyBytes');
  // print('Public Key (Bytes): $publicKeyBytes');
  // print('Certificate (Bytes): $certificateBytes');

  final parsed =
      ASN1Sequence.fromBytes(Uint8List.fromList(pemToBytes(publicKeyPem)));

  return (
    privateKey: Uint8List.fromList(pemToBytes(privateKeyPem)),
    publicKey: parsed.encode()
  );
}

// ({Uint8List privateKey, Uint8List publicKey}) generateP256Keys() {
//   var eCurve = ec.getP256();
//   var priv = eCurve.generatePrivateKey();
//   ec.PublicKey pub = priv.publicKey;

//   // pub.print("public key: ${hexDecode(pub.t).length}");
//   print("priv: ${priv.bytes.length}");
//   print("public key length: ${hexDecode(pub.X.toRadixString(16)).length}");

// // pub.
//   // print(HEX.decode(encoded));

//   // var test = ASN1Parser(Uint8List.fromList(hexDecode(pub.X.toRadixString(16))));
//   //  test.

//   // final encoded = ASN1Sequence(elements: [
//   //   ASN1Integer(pub.curve.p),
//   //   ASN1Integer(pub.X),
//   //   ASN1Integer(pub.Y),
//   // ]).encode();

//   // final encoded =ASN1Integer(hexDecode(pub.X.toRadixString(16))).encode();

//   print("public key length: ${hexDecode(pub.toHex()).length}");

//   // final parsed =
//   //     ASN1Sequence.fromBytes(Uint8List.fromList(hexDecode(pub.toHex())));

//   // final parsed = ASN1Sequence.fromBytes(
//   //     Uint8List.fromList(hexDecode(pub.X.toRadixString(16))));

//   return (
//     privateKey: Uint8List.fromList(priv.bytes),
//     // publicKey: Uint8List.fromList(hexDecode(pub.toCompressedHex()))
//     publicKey: Uint8List.fromList(hexDecode(pub.toHex()))
//     // publicKey: Uint8List.fromList(hexDecode(pub.X.toRadixString(16)))
//     // publicKey: parsed.encode()
//   );
// }

({Uint8List privateKey, Uint8List publicKey}) generateP256Keys() {
  var eCurve = ec.getP256();
  var priv = eCurve.generatePrivateKey();
  ec.PublicKey pub = priv.publicKey;

  // Extract X and Y coordinates
  BigInt x = pub.X;
  BigInt y = pub.Y;

  // Ensure they are correctly padded to 32 bytes
  Uint8List xBytes = _bigIntToBytes(x, 32);
  Uint8List yBytes = _bigIntToBytes(y, 32);

  // Create the uncompressed public key format (0x04 || X || Y)
  Uint8List uncompressedPublicKey =
      Uint8List.fromList([0x04, ...xBytes, ...yBytes]);

  print("Private Key: ${HEX.encode(priv.bytes)}");
  print("Public Key: ${HEX.encode(uncompressedPublicKey)}");

  return (
    privateKey: Uint8List.fromList(priv.bytes),
    publicKey: uncompressedPublicKey,
  );
}

// Convert BigInt to Uint8List with fixed length (zero-padded)
Uint8List _bigIntToBytes(BigInt value, int length) {
  var bytes = value.toUnsigned(256).toRadixString(16).padLeft(length * 2, '0');
  return Uint8List.fromList(HEX.decode(bytes));
}

void main() {
  var keys = generateP256Keys();
  print("Generated keys successfully!");
}

({Uint8List privateKey, Uint8List publicKey}) generateECKeys() {
  // Generate an EC (Elliptic Curve) key pair
  // prime256v1
  var keyPair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
  var privateKey = keyPair.privateKey as ECPrivateKey;
  var publicKey = keyPair.publicKey as ECPublicKey;

  // // Encode private key to PEM
  String privateKeyPem = CryptoUtils.encodeEcPrivateKeyToPem(privateKey);

  // // Encode public key to PEM
  String publicKeyPem = CryptoUtils.encodeEcPublicKeyToPem(publicKey);

  // // Print PEM values
  // print('Private Key (PEM):\n$privateKeyPem');
  // print('Public Key (PEM):\n$publicKeyPem');
  // print('Certificate (PEM):\n$certificatePem');

  // // Print raw byte values
  // print('Private Key (Bytes): $privateKeyBytes');
  // print('Public Key (Bytes): $publicKeyBytes');
  // print('Certificate (Bytes): $certificateBytes');

  return (
    privateKey: Uint8List.fromList(pemToBytes(privateKeyPem)),
    publicKey: Uint8List.fromList(pemToBytes(publicKeyPem))
  );
}

/// Converts a PEM string to raw bytes by decoding the Base64 content.
List<int> pemToBytes(String pem) {
  // Remove the PEM headers and footers
  final base64Content = pem
      .replaceAll(RegExp(r'-----BEGIN [^-]+-----'), '')
      .replaceAll(RegExp(r'-----END [^-]+-----'), '')
      .replaceAll(RegExp(r'\s+'), '');

  // Decode the Base64 content

  // final parsed = ASN1Sequence.fromBytes(base64.decode(base64Content));

  // return parsed.encode();
  return base64.decode(base64Content);
}

({List<int> privateKey, List<int> publicKey, List<int> certificate})
    generateKeysAndCertificateStruct() {
  // Generate an EC (Elliptic Curve) key pair
  var keyPair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
  var privateKey = keyPair.privateKey as ECPrivateKey;
  var publicKey = keyPair.publicKey as ECPublicKey;

  // Encode private key to PEM
  String privateKeyPem = CryptoUtils.encodeEcPrivateKeyToPem(privateKey);

  // Encode public key to PEM
  String publicKeyPem = CryptoUtils.encodeEcPublicKeyToPem(publicKey);

  // Generate a self-signed certificate
  var distinguishedName = {'CN': 'Self-Signed'};
  var csrPem =
      X509Utils.generateEccCsrPem(distinguishedName, privateKey, publicKey);

  var certificatePem = X509Utils.generateSelfSignedCertificate(
      privateKey, csrPem, 365, keyUsage: [
    KeyUsage.KEY_ENCIPHERMENT,
    KeyUsage.DIGITAL_SIGNATURE,
    KeyUsage.KEY_CERT_SIGN
  ], extKeyUsage: [
    ExtendedKeyUsage.SERVER_AUTH,
    ExtendedKeyUsage.CLIENT_AUTH
  ]);

  // Convert PEM to raw bytes
  List<int> privateKeyBytes = pemToBytes(privateKeyPem);
  List<int> publicKeyBytes = pemToBytes(publicKeyPem);
  List<int> certificateBytes = pemToBytes(certificatePem);

  // // Print PEM values
  // print('Private Key (PEM):\n$privateKeyPem');
  // print('Public Key (PEM):\n$publicKeyPem');
  // print('Certificate (PEM):\n$certificatePem');

  // // Print raw byte values
  // print('Private Key (Bytes): $privateKeyBytes');
  // print('Public Key (Bytes): $publicKeyBytes');
  // print('Certificate (Bytes): $certificateBytes');
  return (
    privateKey: privateKeyBytes,
    publicKey: publicKeyBytes,
    certificate: certificateBytes
  );
}

// Future<void> verifyCertificate() async {
//   // Extract public key coordinates (X, Y)
//   final x = BigInt.parse(
//       '467c479634c29bcf7c6513d50fe9f7675b98b3ef55fc78e83bff48a1418538c', radix: 16);
//   final y = BigInt.parse(
//       '802527d19b45aa848740e10821e4c6bb326627a07180bb503d1b1c434f1b8c', radix: 16);

//   // Reconstruct the public key
//   final publicKey = cryptography.EcPublicKey(x: x, y: y, curve: cryptography.ellipticCurveP256);

//   // Simulate a message and its signature
//   final message = utf8.encode("Test message");
//   final signature = Uint8List.fromList([...]); // Provide the raw signature bytes here.cryptography

//   // Verify the signature
//   final algorithm = cryptography.Ecdsa.p256(cryptography.Sha256());
//   final verified = await algorithm.verify(
//     message,
//     signature: cryptography.Signature(signature, publicKey: publicKey),
//   );

//   print('Signature verified: $verified');
// }

void extractPublicKey(String publicKeyPem) {
  // Parse the public key from PEM
  var publicKey = CryptoUtils.ecPublicKeyFromPem(publicKeyPem);

  if (publicKey is ECPublicKey) {
    // Extract the elliptic curve name
    //var curveName = CryptoUtils.ecCurveNameFromPublicKey(publicKey);

    // Get X and Y coordinates
    var xCoordinate = publicKey.Q!.x;
    var yCoordinate = publicKey.Q!.y;

    // Print details
    //print('Elliptic Curve: $curveName');
    print('X Coordinate: $xCoordinate');
    print('Y Coordinate: $yCoordinate');
  } else {
    print('Invalid public key format.');
  }
}

void extractPrivateKey(String privateKeyPem) {
  // Parse the private key from PEM
  var privateKey = CryptoUtils.ecPrivateKeyFromPem(privateKeyPem);

  // Print details of the private key
  if (privateKey is ECPrivateKey) {
    print('Private Key D (Hex): ${privateKey.d}');
    //print('Associated Curve: ${CryptoUtils.getEcCurveNameFromPrivateKey(privateKey)}');
  } else {
    print('Invalid private key format.');
  }
}

// bool verifyCertificateSignature(
//     String certificatePem, String issuerPublicKeyPem) {
//   // Parse the certificate
//   var certificate = X509Utils.x509CertificateFromPem(certificatePem);

//   // Extract the public key from the issuer's PEM
//   var issuerPublicKey = CryptoUtils.ecPublicKeyFromPem(issuerPublicKeyPem);

//   if (issuerPublicKey is ECPublicKey) {
//     // Extract the signature from the certificate
//     var signature = certificate.signature;

//     // Verify the certificate's signature using the issuer's public key
//     var isValidSignature = _verifySignature(
//         signature, certificate.tbsCertificate, issuerPublicKey);

//     if (isValidSignature) {
//       print('Certificate signature is valid.');
//     } else {
//       print('Certificate signature is invalid.');
//     }

//     return isValidSignature;
//   } else {
//     print('Invalid issuer public key.');
//     return false;
//   }
// }

// bool _verifySignature(
//     Uint8List signature, Uint8List data, ECPublicKey publicKey) {
//   // Create a signer for the elliptic curve signature verification
//   var signer = Signer('SHA-256/ECDSA')
//     ..init(false, PublicKeyParameter<ECPublicKey>(publicKey));

//   // Perform signature verification
//   return signer.verifySignature(data, ECSignature(signature));
// }

// void main() {
//generateKeysAndCertificate();

//   String cert = """-----BEGIN CERTIFICATE-----
// MIIBTjCB8qADAgECAgEBMAwGCCqGSM49BAMCBQAwFjEUMBIGA1UEAxMLU2VsZi1T
// aWduZWQwHhcNMjUwMTI4MDY1NzA3WhcNMjYwMTI4MDY1NzA3WjAWMRQwEgYDVQQD
// EwtTZWxmLVNpZ25lZDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABBGfEeWNMKbz
// 3xlE9UP592dbmLPvVfx46Dv/SKFAYU4yAlJ9GbRaqEh0DhCCHkxrsyZiegcYC7UD
// 0bHENPG8mL2jLzAtMAwGA1UdDwQFAwMBpAEwHQYDVR0lBBYwFAYIKwYBBQUHAwEG
// CCsGAQUFBwMCMAwGCCqGSM49BAMCBQADSQAwRgIhAI/vyfiKa0WFovjA8yzBx9TT
// tTa3t6dUouQApdo+itegAiEA4yB74rWR45HWz0C+PEnp1aAMajQsAjgoBA/ZPHwh
// 7AY=
// -----END CERTIFICATE-----""";

//   String pubkey = """-----BEGIN PUBLIC KEY-----
// MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEEZ8R5Y0wpvPfGUT1Q/n3Z1uYs+9V
// /HjoO/9IoUBhTjICUn0ZtFqoSHQOEIIeTGuzJmJ6BxgLtQPRscQ08byYvQ==
// -----END PUBLIC KEY-----""";

//   String privkey = """-----BEGIN EC PRIVATE KEY-----
// MHcCAQEEIIuFDM6WKrthMfcCCtzgJZOnyQuWUeBWie3VJ/jmSlzLoAoGCCqGSM49
// AwEHoUQDQgAEEZ8R5Y0wpvPfGUT1Q/n3Z1uYs+9V/HjoO/9IoUBhTjICUn0ZtFqo
// SHQOEIIeTGuzJmJ6BxgLtQPRscQ08byYvQ==
// -----END EC PRIVATE KEY-----""";
//   extractPublicKey(pubkey);
//   extractPrivateKey(privkey);

//   ecSignature();
// }
