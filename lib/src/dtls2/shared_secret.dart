import 'dart:typed_data';

import 'package:elliptic/ecdh.dart';
import 'package:elliptic/elliptic.dart';

BigInt privateKeyFromUint8List(Uint8List data) {
  // Ensure the data is not empty
  if (data.isEmpty) {
    throw ArgumentError("Private key data cannot be empty");
  }

  // Convert the Uint8List to a hexadecimal string
  String hexString =
      data.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  // Parse the hexadecimal string to BigInt
  return BigInt.parse(hexString, radix: 16);
}

// Convert Uint8List to public key (uncompressed format)
List<BigInt> publicKeyFromUint8List(Uint8List data) {
  if (data.length != 65 || data[0] != 0x04) {
    print("Data length: ${data.length}");
    throw ArgumentError("Invalid uncompressed public key format");
  }
  BigInt x = BigInt.parse(
      data
          .sublist(1, 33)
          .map((e) => e.toRadixString(16).padLeft(2, '0'))
          .join(),
      radix: 16);
  BigInt y = BigInt.parse(
      data
          .sublist(33, 65)
          .map((e) => e.toRadixString(16).padLeft(2, '0'))
          .join(),
      radix: 16);
  return [x, y];
}

Uint8List generateP256SharedSecret(Uint8List publicKey, Uint8List privateKey) {
  final bobPublicKey = publicKeyFromUint8List(publicKey);

  final privateAlice = PrivateKey.fromBytes(getP256(), privateKey);

  final publicBob = PublicKey(getP256(), bobPublicKey[0], bobPublicKey[1]);

  // Compute the shared secret
  return Uint8List.fromList(computeSecret(privateAlice, publicBob));
}
