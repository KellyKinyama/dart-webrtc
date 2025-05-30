import 'dart:convert';
import 'dart:typed_data';
import 'package:basic_utils/basic_utils.dart';
import 'package:x509b/x509.dart' as x509;
import 'package:asn1lib/asn1lib.dart';

bool verifyCertificate() {
  var strX1PublicKeyInfo =
      "-----BEGIN PUBLIC KEY-----\nSOME PUBLIC KEY\n-----END PUBLIC KEY-----";
  var strX2Certificate =
      "-----BEGIN CERTIFICATE-----\nSOME CERTIFICATE\n-----END CERTIFICATE-----";

  var x1PublicKey =
      (x509.parsePem(strX1PublicKeyInfo).single as x509.SubjectPublicKeyInfo)
          .subjectPublicKey as x509.RsaPublicKey;
  var x2Certificate =
      x509.parsePem(strX2Certificate).single as x509.X509Certificate;
  var x2CertificateDER = decodePemToDer(strX2Certificate);

  var asn1Parser = ASN1Parser(x2CertificateDER);
  var seq = asn1Parser.nextObject() as ASN1Sequence;
  var tbsSequence = seq.elements[0] as ASN1Sequence;

  var signature =
      x509.Signature(Uint8List.fromList(x2Certificate.signatureValue!));
  var verifier = x1PublicKey.createVerifier(x509.algorithms.signing.rsa.sha256);

  return verifier.verify(tbsSequence.encodedBytes, signature);
}

Uint8List decodePemToDer(pem) {
  var startsWith = [
    '-----BEGIN PUBLIC KEY-----',
    '-----BEGIN PRIVATE KEY-----',
    '-----BEGIN CERTIFICATE-----',
  ];
  var endsWith = [
    '-----END PUBLIC KEY-----',
    '-----END PRIVATE KEY-----',
    '-----END CERTIFICATE-----'
  ];

  //HACK
  for (var s in startsWith) {
    if (pem.startsWith(s)) pem = pem.substring(s.length);
  }

  for (var s in endsWith) {
    if (pem.endsWith(s)) pem = pem.substring(0, pem.length - s.length);
  }

  //Dart base64 decoder does not support line breaks
  pem = pem.replaceAll('\n', '');
  pem = pem.replaceAll('\r', '');
  return Uint8List.fromList(base64.decode(pem));
}

class EcdsaCert {
  Uint8List privateKey;
  Uint8List publickKey;
  EcdsaCert({required this.privateKey, required this.publickKey});
}

EcdsaCert generateSelfSignedCertificate() {
  var pair = CryptoUtils.generateEcKeyPair();
  var privKey = pair.privateKey as ECPrivateKey;
  var pubKey = pair.publicKey as ECPublicKey;
  var dn = {
    'CN': 'Self-Signed',
  };
  var csr = X509Utils.generateEccCsrPem(dn, privKey, pubKey);

  // // Encode private key to PEM
  String privateKeyPem = CryptoUtils.encodeEcPrivateKeyToPem(privKey);
  print("Private Key PEM:\n$privateKeyPem\n");

  // // Encode public key to PEM
  String publicKeyPem = CryptoUtils.encodeEcPublicKeyToPem(pubKey);
  print("Public Key PEM:\n$publicKeyPem\n");

  var x509PEM = X509Utils.generateSelfSignedCertificate(
    privKey,
    csr,
    365,
  );

  print("Certificate PEM:\n$x509PEM\n");
  return EcdsaCert(privateKey: privateKey, publickKey: publickKey);

  return x509PEM;
}
