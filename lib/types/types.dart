import 'dart:typed_data';

abstract class Uint {
  int value;
  Uint(this.value);

  Uint8List toBytes();

  factory Uint.fromBytes(Uint8List buf, int offset, int arrayLen) {
    // TODO: implement fromBytes
    throw UnimplementedError();
  }
}

class Uint8 extends Uint {
  Uint8(super.value);

  @override
  Uint8List toBytes() {
    // ByteData.sublistView(Uint8List(1).getUint16(0, Endian.big))
    var data = Uint8List(1);

    ByteData.sublistView(data).setUint8(0, value);
    // bd.buffer.asUint8List();
    // TODO: implement fromInt
    return data;
  }

  static Uint8 fromBytes(Uint8List buf, int offset, int arrayLen) {
    if (buf.length != 1) {
      throw ArgumentError("Incorrect buffer length: ${buf.length}");
    }
    final int val = buf[offset];
    return Uint8(val);
  }

  @override
  String toString() {
    // TODO: implement toString
    return "Uint8{$value}";
  }
}

class Uint16 extends Uint {
  Uint16(super.value);

  @override
  Uint8List toBytes() {
    // ByteData.sublistView(Uint8List(1).getUint16(0, Endian.big))
    var data = Uint8List(2);

    ByteData.sublistView(data).setUint16(0, value);
    // bd.buffer.asUint8List();
    // TODO: implement fromInt
    return data;
  }

  static Uint16 fromBytes(Uint8List buf, int offset, int arrayLen) {
    if (buf.length != 2) {
      throw ArgumentError("Incorrect buffer length: ${buf.length}");
    }
    return Uint16(ByteData.sublistView(buf).getUint16(offset));
  }

  @override
  String toString() {
    // TODO: implement toString
    return "Uint16{$value}";
  }
}

class Uint24 extends Uint {
  Uint24(super.value);

  @override
  Uint8List toBytes() {
    return Uint8List(3)
      ..[0] = (value >> 16) & 0xFF
      ..[1] = (value >> 8) & 0xFF
      ..[2] = value & 0xFF;
  }

  factory Uint24.fromBytes(Uint8List bytes) {
    return Uint24((bytes[0] << 16) | (bytes[1] << 8) | bytes[2]);
  }

  @override
  String toString() {
    // TODO: implement toString
    return "Uint24{$value}";
  }
}

class Uint32 extends Uint {
  Uint32(super.value);

  @override
  Uint8List toBytes() {
    // ByteData.sublistView(Uint8List(1).getUint16(0, Endian.big))
    var data = Uint8List(4);

    ByteData.sublistView(data).setUint32(0, value);
    // bd.buffer.asUint8List();
    // TODO: implement fromInt
    return data;
  }

  static Uint32 fromBytes(Uint8List buf) {
    if (buf.length != 4) {
      throw ArgumentError("Incorrect buffer length: ${buf.length}");
    }
    return Uint32(ByteData.sublistView(buf).getUint32(0));
  }

  @override
  String toString() {
    // TODO: implement toString
    return "Uint32{$value}";
  }
}

class Uint48 extends Uint {
  Uint48(super.value);

  @override
  Uint8List toBytes() {
    // TODO: implement fromInt
    return Uint8List(6)
      ..[5] = (value >> 16) & 0xFF
      ..[4] = (value >> 8) & 0xFF
      ..[3] = value & 0xFF
      ..[2] = (value >> 16) & 0xFF
      ..[1] = (value >> 8) & 0xFF
      ..[0] = value & 0xFF;
  }

  factory Uint48.fromBytes(Uint8List bytes) {
    if (bytes.length != 6) {
      throw ArgumentError("Incorrect buffer length: ${bytes.length}");
    }
    return Uint48((bytes[0] << 40) |
        (bytes[1] << 32) |
        (bytes[2] << 24) |
        (bytes[3] << 16) |
        (bytes[4] << 8) |
        bytes[5]);
  }

  @override
  String toString() {
    // TODO: implement toString
    return "Uint48{$value}";
  }
}

class Uint64 extends Uint {
  Uint64(super.value);

  @override
  Uint8List toBytes() {
    // ByteData.sublistView(Uint8List(1).getUint16(0, Endian.big))
    var data = Uint8List(8);

    ByteData.sublistView(data).setUint64(0, value);
    // bd.buffer.asUint8List();
    // TODO: implement fromInt
    return data;
  }

  static Uint8 fromBytes(Uint8List buf, int offset, int arrayLen) {
    if (buf.length != 8) {
      throw ArgumentError("Incorrect buffer length: ${buf.length}");
    }
    return Uint8(ByteData.sublistView(buf).getUint64(offset));
  }

  @override
  String toString() {
    // TODO: implement toString
    return "Uint64{$value}";
  }
}
