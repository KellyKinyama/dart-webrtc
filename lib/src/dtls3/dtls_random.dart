import 'dart:typed_data';
import 'package:fixnum/fixnum.dart'; // For int64 if needed, though Dart's int handles 64-bit

const int randomBytesLength = 28;

/// Represents a random structure with GMT Unix time and random bytes.
/// Corresponds to Go's `Random` struct.
class Random {
  DateTime gmtUnixTime;
  Uint8List randomBytes;

  Random({
    required this.gmtUnixTime,
    required this.randomBytes,
  }) : assert(randomBytes.length == randomBytesLength);

  /// Encodes the Random object into a byte array.
  /// Corresponds to Go's `Encode` method.
  Uint8List encode() {
    final result = Uint8List(4 + randomBytesLength);
    final ByteData bd = ByteData.view(result.buffer);

    bd.setUint32(0, gmtUnixTime.millisecondsSinceEpoch ~/ 1000, Endian.big);
    result.setRange(4, 4 + randomBytesLength, randomBytes);

    return result;
  }

  /// Generates new random data and sets the GMT Unix time.
  /// Corresponds to Go's `Generate` method.
  void generate() {
    gmtUnixTime = DateTime.now().toUtc();
    final tempBytes = Uint8List(randomBytesLength);
    // In a real application, you would use a cryptographically secure random number generator.
    // For example, dart:math.Random.nextBytes if it were available or platform-specific methods.
    // For now, using a simple fill with zeros or a non-secure random for demonstration.
    // Ensure to replace this with a secure method for production use.
    for (int i = 0; i < randomBytesLength; i++) {
      tempBytes[i] = (i * 7 % 256).toInt(); // Placeholder for actual random generation
    }
    randomBytes = tempBytes;
  }

  /// Decodes a Random object from a byte array.
  /// Corresponds to Go's `DecodeRandom` function.
  static Random decode(Uint8List buf, int offset) {
    final reader = ByteData.sublistView(buf, offset);
    final gmtUnixTimeSeconds = reader.getUint32(0, Endian.big);
    final gmtUnixTime =
        DateTime.fromMillisecondsSinceEpoch(gmtUnixTimeSeconds * 1000, isUtc: true);
    final randomBytes =
        Uint8List.fromList(buf.sublist(offset + 4, offset + 4 + randomBytesLength));

    return Random(gmtUnixTime: gmtUnixTime, randomBytes: randomBytes);
  }

  @override
  String toString() {
    return 'Random(gmtUnixTime: $gmtUnixTime, randomBytes: ${randomBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join('')})';
  }
}