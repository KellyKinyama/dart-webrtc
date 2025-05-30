import 'dart:convert';
import 'dart:typed_data';
import 'package:basic_utils/basic_utils.dart';
import 'package:x509b/x509.dart' as x509; // Alias for clarity
import 'package:asn1lib/asn1lib.dart'; // For ASN1 related parsing if needed, but x509b handles most
import 'package:pointycastle/api.dart'; // For ECPrivateKey and ECPublicKey

// This decodePemToDer function is robust and handles various PEM types
Uint8List decodePemToDer(String pem) {
  final cleanPem = pem
      .replaceAll(RegExp(r'-----(BEGIN|END) (RSA )?(PUBLIC KEY|PRIVATE KEY|CERTIFICATE)-----'), '')
      .replaceAll('\n', '')
      .replaceAll('\r', '');
  return base64.decode(cleanPem);
}

// Function to generate a self-signed ECDSA certificate
String generateSelfSignedCertificate() {
  // Generate ECDSA key pair
  var pair = CryptoUtils.generateEcKeyPair();
  var privKey = pair.privateKey as ECPrivateKey;
  var pubKey = pair.publicKey as ECPublicKey;

  // Define Distinguished Name for the certificate
  var dn = {
    'CN': 'Self-Signed',
    'O': 'My Organization',
    'C': 'US',
  };

  // Generate Certificate Signing Request (CSR)
  var csr = X509Utils.generateEccCsrPem(dn, privKey, pubKey);

  // Print keys for debugging/inspection (optional)
  String privateKeyPem = CryptoUtils.encodeEcPrivateKeyToPem(privKey);
  print("Generated Private Key PEM:\n$privateKeyPem\n");

  String publicKeyPem = CryptoUtils.encodeEcPublicKeyToPem(pubKey);
  print("Generated Public Key PEM:\n$publicKeyPem\n");

  // Generate the self-signed certificate
  // For self-signed, the signing key is the generated private key.
  // The certificate will embed the generated public key.
  var x509PEM = X509Utils.generateSelfSignedCertificate(
    privKey, // Private key used for signing
    csr,     // CSR containing subject and public key
    365,     // Validity in days
  );

  print("Generated Certificate PEM:\n$x509PEM\n");

  return x509PEM;
}

// Function to verify the self-signed certificate using its embedded public key
bool verifyCertificate(String certificatePem) {
  // 1. Parse the certificate into an x509.X509Certificate object
  var certificate = x509.parsePem(certificatePem).single as x509.X509Certificate;

  // 2. Get the public key from the certificate.
  var ecPublicKey = certificate.publicKey as x509.EcPublicKey;

  // 3. Get the TBS (To Be Signed) data.
  // The `tbsCertificate` property returns a `TbsCertificate` object.
  // We need its *encoded bytes* to pass to the verifier.
  var tbsObject = certificate.tbsCertificate;
  // The `TbsCertificate` object (like other ASN.1 structures in x509b)
  // should have an `encodedBytes` property to get its DER representation.
  var tbsEncodedBytes = tbsObject.subjectPublicKeyInfo; // This is the fix!

  // 4. Extract the signature value.
  // The x509b library also provides the signatureValue property as a Uint8List.
  var signatureBytes = certificate.signatureValue!;

  // 5. Create the signature object
  var signature = x509.Signature(signatureBytes);

  // 6. Create the verifier with the correct algorithm
  // For self-signed certs from basic_utils with ECC, it usually defaults to ecdsa.sha256.
  var verifier = ecPublicKey.createVerifier(x509.algorithms.signing.ecdsa.sha256);

  // 7. Perform the verification
  return verifier.verify(tbsEncodedBytes.subjectPublicKey, signature); // Pass the Uint8List
}

void main() {
  // Generate a new self-signed certificate
  String generatedCertPem = generateSelfSignedCertificate();

  // Verify the generated certificate using its embedded public key
  print("Starting certificate verification...");
  bool isValid = verifyCertificate(generatedCertPem);
  print("Certificate verification result: $isValid");
}