import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Computes the TLS PRF using HMAC-SHA256.
Uint8List tlsPRF(
    Uint8List secret, String label, Uint8List seed, int outputLength) {
  // Concatenate label and seed
  Uint8List labelSeed = Uint8List.fromList(utf8.encode(label) + seed);

  // Compute the output using P_hash with HMAC-SHA256
  return pHash(secret, labelSeed, outputLength);
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
  var hmac = Hmac(sha256, key);
  return Uint8List.fromList(hmac.convert(data).bytes);
}

Uint8List hmacSha1(Uint8List key, Uint8List data) {
  var hmac = Hmac(sha1, key);
  return Uint8List.fromList(hmac.convert(data).bytes);
}

// Uint8List tlsPRF_TLS10(Uint8List secret, String label, Uint8List seed, int outputLength) {
//   int half = (secret.length / 2).ceil();
//   Uint8List s1 = secret.sublist(0, half);
//   Uint8List s2 = secret.sublist(secret.length - half);

//   Uint8List p_md5 = pHash(s1, Uint8List.fromList(utf8.encode(label) + seed), outputLength, md5);
//   Uint8List p_sha1 = pHash(s2, Uint8List.fromList(utf8.encode(label) + seed), outputLength, sha1);

//   // XOR P_MD5 and P_SHA1
//   Uint8List output = Uint8List(outputLength);
//   for (int i = 0; i < outputLength; i++) {
//     output[i] = p_md5[i] ^ p_sha1[i];
//   }
//   return output;
// }

/// TLS 1.3 PRF using HKDF (HMAC-based Key Derivation Function)
Uint8List tls13PRF(
    Uint8List secret, String label, Uint8List seed, int outputLength) {
  Uint8List info = Uint8List.fromList(utf8.encode(label) + seed);

  // Step 1: Extract
  Uint8List prk = hkdfExtract(secret);

  // Step 2: Expand
  return hkdfExpand(prk, info, outputLength);
}

/// HKDF-Extract using HMAC-SHA256
Uint8List hkdfExtract(Uint8List ikm, {Uint8List? salt}) {
  salt ??= Uint8List(32); // Default salt = 32 zero bytes
  var hmac = Hmac(sha256, salt);
  return Uint8List.fromList(hmac.convert(ikm).bytes);
}

/// HKDF-Expand using HMAC-SHA256
Uint8List hkdfExpand(Uint8List prk, Uint8List info, int outputLength) {
  List<int> output = [];
  Uint8List previousBlock = Uint8List(0);
  int counter = 1;

  while (output.length < outputLength) {
    var hmac = Hmac(sha256, prk);
    var data = Uint8List.fromList(previousBlock + info + [counter]);
    previousBlock = Uint8List.fromList(hmac.convert(data).bytes);

    output.addAll(previousBlock);
    counter++;
  }

  return Uint8List.fromList(output.sublist(0, outputLength));
}

/// Example Usage
void main() {
  Uint8List secret = Uint8List.fromList(utf8.encode("my_secret"));
  String label = "tls13 handshake";
  Uint8List seed = Uint8List.fromList(utf8.encode("random_data"));
  int outputLength = 32;

  Uint8List key = tls13PRF(secret, label, seed, outputLength);

  print(
      "Derived Key: ${key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}");
}

// void main() {
//   // Example usage
//   Uint8List secret = Uint8List.fromList(utf8.encode("my_secret"));
//   String label = "key expansion";
//   Uint8List seed = Uint8List.fromList(utf8.encode("random_data"));
//   int outputLength = 32;

//   Uint8List key = tlsPRF(secret, label, seed, outputLength);

//   print(
//       "Derived Key: ${key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}");
// }
// Compare this snippet from lib/ch09/hmac.dart:
