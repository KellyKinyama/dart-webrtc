import 'dart:typed_data';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/ec_key_pair.dart';
import 'package:pointycastle/asymmetric/ec_public_key.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/random/fortuna_random.dart';

import 'package:pointycastle/asn1.dart'; // For ASN.1 encoding (useful for X.509)
import 'package:pointycastle/asymmetric/x509.dart'; // For X.509 structures (limited support)

// For generating random bytes (important for key generation)
import 'dart:math';

// Helper for generating secure random bytes
FortunaRandom _secureRandom() {
  final FortunaRandom random = FortunaRandom();
  final seedSource = Random.secure();
  final seeds = List<int>.generate(32, (_) => seedSource.nextInt(256));
  random.seed(KeyParameter(Uint8List.fromList(seeds)));
  return random;
}

Future<void> main() async {
  // 1. Generate EC Key Pair
  final EC_Fp secp256r1 = ECCurve_secp256r1(); // Choose your curve
  final ECKeyGenerator keyGen = ECKeyGenerator();

  keyGen.init(ParametersWithRandom(ECKeyGenerationParameters(secp256r1), _secureRandom()));

  final AsymmetricKeyPair<ECPublicKey, ECPrivateKey> keyPair = keyGen.generateKeyPair();

  final ECPublicKey publicKey = keyPair.publicKey;
  final ECPrivateKey privateKey = keyPair.privateKey;

  print('Public Key: ${publicKey.Q}');
  print('Private Key D: ${privateKey.d}');

  // 2. Define Certificate Information (Simplified)
  // In a real scenario, you'd build a more complete X.509 structure.
  // Pointycastle doesn't have high-level X.509 builders directly,
  // so you might need to construct ASN.1 structures manually or use other libraries.

  // For demonstration, let's just create some dummy data to sign.
  // In a real certificate, this would be the TBSCertificate (To Be Signed Certificate) structure.
  final String subjectDN = 'CN=My Self-Signed EC Cert,O=My Org,C=US';
  final String issuerDN = subjectDN; // Self-signed
  final BigInt serialNumber = BigInt.from(12345);
  final DateTime notBefore = DateTime.now().toUtc();
  final DateTime notAfter = notBefore.add(Duration(days: 365)).toUtc(); // Valid for 1 year

  // Example of what the "TBSCertificate" might look like conceptually (not actual ASN.1)
  final String tbsCertificateData = '''
    Version: 3
    SerialNumber: $serialNumber
    SignatureAlgorithm: id-ecPublicKey
    Issuer: $issuerDN
    Expiration: $notBefore to $notAfter
    Subject: $subjectDN
    PublicKey: ${publicKey.Q.toString()}
    ... (other extensions)
  ''';

  final Uint8List tbsBytes = Uint8List.fromList(tbsCertificateData.codeUnits);

  // 3. Sign the TBS Certificate Data
  final ECDSASigner signer = ECDSASigner(SHA256Digest());
  signer.init(true, PrivateKeyParameter(privateKey)); // `true` for signing

  final //ECSignature 
  signature = signer.generateSignature(tbsBytes);

  print('Signature R: ${signature}');
  print('Signature S: ${signature.s}');

  // 4. Encode the Certificate (Highly Simplified/Conceptual)
  // Generating a full X.509 certificate in DER/PEM format is complex
  // and involves meticulous ASN.1 encoding. Pointycastle provides ASN.1
  // building blocks, but not a high-level X.509 certificate builder.

  // You would typically construct an ASN.1 sequence representing the X.509 certificate:
  // SEQUENCE {
  //   TBSCertificate,
  //   AlgorithmIdentifier,
  //   BIT STRING signatureValue
  // }

  // A full implementation would involve:
  // - Creating ASN1Sequence for TBSCertificate
  // - Populating it with version, serial, algorithm, issuer, validity, subject, public key info, extensions.
  // - Creating ASN1Sequence for AlgorithmIdentifier (for ECDSA with SHA256)
  // - Creating ASN1BitString for the signature value.
  // - Combining them into the final ASN1Sequence for the certificate.

  // For example, to get a taste of ASN.1 encoding (this is NOT a full certificate):
  // final ASN1Sequence seq = ASN1Sequence();
  // seq.add(ASN1Integer(signature.r));
  // seq.add(ASN1Integer(signature.s));
  // final Uint8List encodedSignature = seq.encode();
  // print('Encoded Signature (ASN.1 DER): ${encodedSignature.toHexString()}');

  print('\n--- Further Steps ---');
  print('To generate a complete X.509 self-signed certificate, you would need to:');
  print('1. Construct the TBSCertificate structure using `asn1lib` or similar.');
  print('2. Include details like version, serial, algorithm, issuer, validity, subject, public key, and extensions.');
  print('3. Sign the DER-encoded TBSCertificate data using the generated EC private key.');
  print('4. Assemble the final certificate structure (TBSCertificate, SignatureAlgorithm, SignatureValue) into an ASN.1 sequence.');
  print('5. Encode the final ASN.1 sequence to DER bytes.');
  print('6. Optionally, convert the DER bytes to PEM format (Base64 encoding with headers/footers).');

  print('\n--- Considerations ---');
  print('- **X.509 Standard:** Generating valid X.509 certificates requires a deep understanding of the standard (RFC 5280).');
  print('- **ASN.1 Encoding:** You\'ll be working heavily with ASN.1 DER encoding for the certificate structure.');
  print('- **Extensions:** Implementing critical extensions like Basic Constraints (for CA flag) and Key Usage is crucial.');
  print('- **Subject Alternative Names (SANs):** For modern applications, SANs are often preferred over Common Name (CN).');
  print('- **Error Handling:** Robust error handling is essential for production code.');
  print('- **Security:** Ensure your random number generation is cryptographically secure.');
}

// Extension to convert Uint8List to hex string for easier printing
extension on Uint8List {
  String toHexString() {
    return map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}