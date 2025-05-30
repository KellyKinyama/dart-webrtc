import 'dart:convert';
import 'dart:typed_data';
import 'package:basic_utils/basic_utils.dart';
import 'package:x509b/x509.dart' as x509;
import 'package:asn1lib/asn1lib.dart';

import 'cert_util2.dart';

final strX1PublicKeyInfo = """-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAELAD7+G0y6cl90YpZ0vRC0uN6ep7D
H7DJ9Y26RwHjFfRDj5q9yqtzZLUMdlofD41zB03zJFxpSIdH3EC0nKRWwg==
-----END PUBLIC KEY-----""";

final strX2Certificate = """-----BEGIN CERTIFICATE-----
MIIBHDCBwaADAgECAgEBMAwGCCqGSM49BAMCBQAwFjEUMBIGA1UEAxMLU2VsZi1T
aWduZWQwHhcNMjUwNTI5MTMwMjA1WhcNMjYwNTI5MTMwMjA1WjAWMRQwEgYDVQQD
EwtTZWxmLVNpZ25lZDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABCwA+/htMunJ
fdGKWdL0QtLjenqewx+wyfWNukcB4xX0Q4+avcqrc2S1DHZaHw+NcwdN8yRcaUiH
R9xAtJykVsIwDAYIKoZIzj0EAwIFAANIADBFAiEA0bQAT4HekGDoamT4DNuRZh85
ZJBO1PQ8Nyx7t67H7KACIG6PhrIN6db/ZgwQDOMszr9V+FnBKRcRwo2cU1TQcWE/
-----END CERTIFICATE-----""";

// bool verifyCertificate(String certPem) {

//   var strX1PublicKeyInfo =
//       "-----BEGIN PUBLIC KEY-----\nSOME PUBLIC KEY\n-----END PUBLIC KEY-----";
//   var strX2Certificate =
//       "-----BEGIN CERTIFICATE-----\nSOME CERTIFICATE\n-----END CERTIFICATE-----";

//   var x1PublicKey =
//       (x509.parsePem(strX1PublicKeyInfo).single as x509.SubjectPublicKeyInfo)
//           .subjectPublicKey as x509.EcPublicKey;
//   // Parse the certificate
//   var certificate = x509.parsePem(certPem).single as x509.X509Certificate;
//   var publicKeyInfo = certificate.subjectPublicKeyInfo;
//   var publicKey = publicKeyInfo.subjectPublicKey as x509.EcPublicKey;

//   // Extract raw DER bytes from PEM
//   var certDer = decodePemToDer(certPem);

//   // Parse ASN.1
//   var asn1Parser = ASN1Parser(certDer);
//   var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

//   var tbsCertificateSeq = topLevelSeq.elements[0] as ASN1Sequence;
//   var signatureAlgorithm = topLevelSeq.elements[1] as ASN1Sequence;
//   var signatureBitString = topLevelSeq.elements[2] as ASN1BitString;

//   // The signature is stored as a BIT STRING with padding
//   var signatureBytes = signatureBitString.stringValues!;

//   // EC signatures in ASN.1 are typically DER-encoded (r, s) sequence
//   var signature = x509.Signature(Uint8List.fromList(signatureBytes));

//   // Use the EC public key to verify the signature
//   var verifier = publicKey.createVerifier(x509.algorithms.signing.ecdsa.sha256);

//   return verifier.verify(tbsCertificateSeq.encodedBytes, signature);
// }

// bool verifyCertificate() {
//   // var strX1PublicKeyInfo =
//   //     "-----BEGIN PUBLIC KEY-----\nSOME PUBLIC KEY\n-----END PUBLIC KEY-----";
//   // var strX2Certificate =
//   //     "-----BEGIN CERTIFICATE-----\nSOME CERTIFICATE\n-----END CERTIFICATE-----";

//   var x1PublicKey =
//       (x509.parsePem(strX1PublicKeyInfo).single as x509.SubjectPublicKeyInfo)
//           .subjectPublicKey as x509.EcPublicKey;
//   // var x2Certificate =
//   // x509.parsePem(strX2Certificate).single as x509.X509Certificate;
//   var x2CertificateDER = decodePemToDer(strX2Certificate);

// // Parse ASN.1
//   var asn1Parser = ASN1Parser(x2CertificateDER);
//   var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

//   var tbsCertificateSeq = topLevelSeq.elements[0] as ASN1Sequence;
//   // var signatureAlgorithm = topLevelSeq.elements[1] as ASN1Sequence;
//   var signatureBitString = topLevelSeq.elements[2] as ASN1BitString;

//   //   // The signature is stored as a BIT STRING with padding
//   var signatureBytes = signatureBitString.stringValue;
//   // EC signatures in ASN.1 are typically DER-encoded (r, s) sequence
//   var signature = x509.Signature(Uint8List.fromList(signatureBytes));

//   // Use the EC public key to verify the signature
//   var verifier =
//       x1PublicKey.createVerifier(x509.algorithms.signing.ecdsa.sha256);

//   return verifier.verify(tbsCertificateSeq.encodedBytes, signature);
// }

bool verifyCertificate() {
  // Parse public key
  var x1PublicKey =
      (x509.parsePem(strX1PublicKeyInfo).single as x509.SubjectPublicKeyInfo)
          .subjectPublicKey as x509.EcPublicKey;

  // Convert PEM certificate to DER bytes
  var certDer = decodePemToDer(strX2Certificate);

  // Parse the full certificate using ASN1
  var asn1Parser = ASN1Parser(certDer);
  var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

  // Parse the three main certificate components
  var tbsCertStart = 0; // The TBS starts at byte 0
  var tbsCertEnd = certDer.length; // We'll find its real end below

  // Reconstruct TBS DER correctly from the original DER
  var tbs = ASN1Parser(certDer).nextObject() as ASN1Sequence;
  var tbsEncoded = tbs.encodedBytes;

  // Extract signature BIT STRING and get the DER-encoded signature
  var signatureBitString = topLevelSeq.elements[2] as ASN1BitString;
  var signatureBytes = signatureBitString.valueBytes(); // already DER-encoded

  var signature = x509.Signature(Uint8List.fromList(signatureBytes));

  // Create a verifier with the correct algorithm
  var verifier =
      x1PublicKey.createVerifier(x509.algorithms.signing.ecdsa.sha256);

  // Verify the signature over the original TBS DER
  return verifier.verify(tbsEncoded, signature);
}

void main() {
  print("Certificate verification result: ${verifyCertificate()}");
  // print("Certificate verification result: ${verifyCertificate(strX2Certificate)}");
}
