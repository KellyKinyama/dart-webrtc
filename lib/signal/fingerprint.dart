// import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';

String fingerprint(Uint8List certDer) {
// Create SHA-256 fingerprint
  Digest fingerprint = sha256.convert(certDer);

// Convert to uppercase hexadecimal representation
  String fingerprintHex = fingerprint.toString().toUpperCase();
  print("Fingerprint: $fingerprintHex");
  // Format the digest as a colon-separated string
  String fingerprintOut = fingerprintHex;
  fingerprintOut = fingerprintOut
      .replaceAllMapped(RegExp(r'.{2}'), (match) => '${match.group(0)}:')
      .substring(
          0, (fingerprintOut.length + fingerprintOut.length ~/ 2).toInt());

  fingerprintOut = fingerprintOut.substring(0, fingerprintOut.length - 1);
  return fingerprintOut;
}

// void main() {
//   print("Fingerprint sdp: ${fingerprint()}");
// }
