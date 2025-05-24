import 'dart:typed_data';
import 'package:elliptic/elliptic.dart';
import 'hex2.dart'; // Your hex encode/decode helper functions

/// Convert public key to 33-byte compressed format (1-byte prefix + 32-byte X coordinate)
Uint8List compressPublicKey(PublicKey pub) {
  var x = pub.X;
  var y = pub.Y;

  // Determine prefix: 0x02 for even Y, 0x03 for odd Y
  int prefix = y.isEven ? 0x02 : 0x03;

  // Combine prefix + X coordinate
  return Uint8List.fromList(
      [prefix] + hexDecode(x.toRadixString(16).padLeft(64, '0')));
}

/// Recover full (uncompressed) public key from 33-byte compressed key
PublicKey decompressPublicKey(Uint8List compressedKey, EllipticCurve curve) {
  if (compressedKey.length != 33) {
    throw ArgumentError('Compressed key must be 33 bytes.');
  }

  BigInt x = BigInt.parse(hexEncode(compressedKey.sublist(1)), radix: 16);
  bool isEven = compressedKey[0] == 0x02;

  // Solve for Y using curve equation: y² = x³ + ax + b
  BigInt ySquared =
      (x.modPow(BigInt.from(3), curve.p) + (curve.a * x) + curve.b) % curve.p;
  BigInt y = ySquared.modPow((curve.p + BigInt.one) >> 2, curve.p);

  // Ensure correct parity
  if (y.isEven != isEven) {
    y = curve.p - y;
  }

  return PublicKey(curve, x, y);
}

void main() {
  var ec = getP256(); // Get elliptic curve
  var priv = ec.generatePrivateKey();
  var pub = priv.publicKey;

  print("Original Public Key (Uncompressed): ${pub.toHex()}");
  print("Original Public Key Length: ${hexDecode(pub.toHex()).length}");

  // Compress Public Key
  Uint8List compressedKey = compressPublicKey(pub);
  print("Compressed Public Key (Hex): ${hexEncode(compressedKey)}");

  // Decompress Public Key
  PublicKey recoveredPub = decompressPublicKey(compressedKey, ec);
  print("Recovered Public Key (Uncompressed): ${recoveredPub.toHex()}");

  // Verify that decompressed key matches original
  assert(recoveredPub.toHex() == pub.toHex());
  print("✅ Public key recovered successfully!");
}
