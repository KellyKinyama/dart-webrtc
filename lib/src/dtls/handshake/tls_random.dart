import 'dart:math';
import 'dart:typed_data';

const int RANDOM_BYTES_LENGTH = 28;
const int HANDSHAKE_RANDOM_LENGTH = RANDOM_BYTES_LENGTH + 4;

class TlsRandom {
  DateTime gmt_unix_time;
  List<int> randomBytes = List.filled(28, 0);

  Uint8List? unMarshalledRandomData;
  TlsRandom(this.gmt_unix_time, this.randomBytes,
      {this.unMarshalledRandomData}) {
    if (randomBytes.length != RANDOM_BYTES_LENGTH) {
      throw "Invalid random bytes length: ${randomBytes.length}";
    }
  }

  factory TlsRandom.fromBytes(Uint8List bytes, int offset) {
    int offSetBackup = offset;
    final secs = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.big);
    final gmtUnixTime =
        DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true);

    offset += 4;
    final random_bytes = bytes.sublist(offset, offset + RANDOM_BYTES_LENGTH);
    offset += RANDOM_BYTES_LENGTH;

    return TlsRandom(gmtUnixTime, random_bytes,
        unMarshalledRandomData: bytes.sublist(offSetBackup, offset));
  }

  factory TlsRandom.defaultInstance() {
    return TlsRandom(
      DateTime.now(),
      List.filled(RANDOM_BYTES_LENGTH, 0),
    );
  }

  /// Marshal the object into bytes
  Uint8List marshal() {
    final bb = BytesBuilder();
    int secs = gmt_unix_time.millisecondsSinceEpoch ~/ 1000;
    bb.add(Uint8List(4)..buffer.asByteData().setUint32(0, secs, Endian.big));

    if (randomBytes.length != RANDOM_BYTES_LENGTH) {
      throw "Invalid random bytes length: ${randomBytes.length}";
    }
    bb.add(Uint8List.fromList(randomBytes));
    return bb.toBytes();
  }

  Uint8List raw() {
    return unMarshalledRandomData!;
  }

  /// Unmarshal the object from bytes
  static TlsRandom unmarshal(Uint8List bytes, int offset, int arrayLen) {
    int offSetBackup = offset;
    // if (bytes.length != HANDSHAKE_RANDOM_LENGTH) {
    //   throw FormatException("Invalid HandshakeRandom length");
    // }

    final secs = ByteData.sublistView(bytes, offset, offset + 4)
        .getUint32(0, Endian.big);

    offset = offset + 4;
    final gmtUnixTime =
        DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true);
    final randomBytes = bytes.sublist(offset, offset + RANDOM_BYTES_LENGTH);

    if (randomBytes.length != RANDOM_BYTES_LENGTH) {
      throw "Invalid random bytes length: ${randomBytes.length}";
    }

    return TlsRandom(gmtUnixTime, randomBytes,
        unMarshalledRandomData: bytes.sublist(offSetBackup, offset));
  }

  /// Populate the random bytes and set the current time
  void populate() {
    gmt_unix_time = DateTime.now().toUtc();
    final rng = Random.secure();
    randomBytes = List.generate(RANDOM_BYTES_LENGTH, (_) => rng.nextInt(256));
  }
}

final serverRandom = Uint8List.fromList([
  0x70,
  0x71,
  0x72,
  0x73,
  0x74,
  0x75,
  0x76,
  0x77,
  0x78,
  0x79,
  0x7a,
  0x7b,
  0x7c,
  0x7d,
  0x7e,
  0x7f,
  0x80,
  0x81,
  0x82,
  0x83,
  0x84,
  0x85,
  0x86,
  0x87,
  0x88,
  0x89,
  0x8a,
  0x8b,
  0x8c,
  0x8d,
  0x8e,
  0x8f,
]);
