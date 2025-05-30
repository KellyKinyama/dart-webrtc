import 'dart:convert';
import 'dart:typed_data';
import 'package:basic_utils/basic_utils.dart';
import 'package:x509b/x509.dart' as x509;
import 'package:asn1lib/asn1lib.dart';

import 'cert_util2.dart'; // Assuming this contains decodePemToDer

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

bool verifyCertificate() {
  // Parse public key from PEM string
  var x1PublicKey =
      (x509.parsePem(strX1PublicKeyInfo).single as x509.SubjectPublicKeyInfo)
          .subjectPublicKey as x509.EcPublicKey;

  // Convert PEM certificate to DER bytes
  var certDer = decodePemToDer(strX2Certificate);

  // Parse the full certificate using ASN1
  var asn1Parser = ASN1Parser(certDer);
  var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

  // The 'tbsCertificate' is the first element of the top-level sequence.
  // We need its original encoded bytes for verification.
  var tbsCertificateSeq = topLevelSeq.elements[0] as ASN1Sequence;
  var tbsEncodedBytes = tbsCertificateSeq.encodedBytes;

  // The signatureValue is the third element (index 2) and is a BIT STRING.
  // We need to extract its value bytes, which for ECDSA is typically
  // a DER-encoded SEQUENCE of R and S integers.
  var signatureBitString = topLevelSeq.elements[2] as ASN1BitString;
  var signatureBytes = signatureBitString
      .valueBytes(); // Correctly extracts the raw signature bytes

  // Create an x509.Signature object
  var signature = x509.Signature(Uint8List.fromList(signatureBytes));

  // Create a verifier using the public key and the correct algorithm
  // For your self-signed certificate, the signature algorithm is `ecdsa.sha256`
  var verifier =
      x1PublicKey.createVerifier(x509.algorithms.signing.ecdsa.sha256);

  // Verify the signature against the tbsEncodedBytes
  return verifier.verify(tbsEncodedBytes, signature);
}

// Assuming cert_util2.dart contains this or similar:
Uint8List decodePemToDer(String pem) {
  final cleanPem = pem
      .replaceAll('-----BEGIN PUBLIC KEY-----', '')
      .replaceAll('-----END PUBLIC KEY-----', '')
      .replaceAll('-----BEGIN CERTIFICATE-----', '')
      .replaceAll('-----END CERTIFICATE-----', '')
      .replaceAll('\n', '')
      .replaceAll('\r', '')
      .trim();
  return base64.decode(cleanPem);
}

void main() {
  print("Certificate verification result: ${verifyCertificate()}");
}
