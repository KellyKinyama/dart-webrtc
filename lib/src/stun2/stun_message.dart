import 'dart:typed_data';

import 'package:dartls/src/stun/bits/bit_buffer.dart';

abstract class StunAttributes {
  static const int TYPE_RESERVED = 0x0000;
  static const int TYPE_MAPPED_ADDRESS = 0x0001;
  static const int TYPE_RESPONSE_ADDRESS = 0x0002;
  static const int TYPE_CHANGE_ADDRESS = 0x0003;
  static const int TYPE_CHANGE_REQUEST = 0x0003; // rfc5780
  static const int TYPE_SOURCE_ADDRESS = 0x0004;
  static const int TYPE_CHANGED_ADDRESS = 0x0005;
  static const int TYPE_USERNAME = 0x0006;
  static const int TYPE_PASSWORD = 0x0007;
  static const int TYPE_MESSAGE_INTEGRITY = 0x0008;
  static const int TYPE_ERROR_CODE = 0x0009;
  static const int TYPE_UNKNOWN_ATTRIBUTES = 0x000A;
  static const int TYPE_REFLECTED_FROM = 0x000B;
  static const int TYPE_REALM = 0x0014;
  static const int TYPE_NONCE = 0x0015;
  static const int TYPE_XOR_MAPPED_ADDRESS = 0x0020;
  static const int TYPE_PADDING = 0x0026; // rfc5780
  static const int TYPE_RESPONSE_PORT = 0x0027; // rfc5780

  // Comprehension-optional range (0x8000-0xFFFF):
  static const int TYPE_SOFTWARE = 0x8022;
  static const int TYPE_ALTERNATE_SERVER = 0x8023;
  static const int TYPE_FINGERPRINT = 0x8028;
  static const int TYPE_RESPONSE_ORIGIN = 0x802b; // rfc5780
  static const int TYPE_OTHER_ADDRESS = 0x802c; // rfc5780

  static final Map<int, String> TYPE_STRINGS = {
    TYPE_RESERVED: "RESERVED",
    TYPE_MAPPED_ADDRESS: "MAPPED-ADDRESS",
    TYPE_RESPONSE_ADDRESS: "RESPONSE-ADDRESS",
    TYPE_CHANGE_ADDRESS: "CHANGE-ADDRESS",
    TYPE_CHANGE_REQUEST: "CHANGE-REQUEST",
    TYPE_SOURCE_ADDRESS: "SOURCE-ADDRESS",
    TYPE_CHANGED_ADDRESS: "CHANGED-ADDRESS",
    TYPE_USERNAME: "USERNAME",
    TYPE_PASSWORD: "PASSWORD",
    TYPE_MESSAGE_INTEGRITY: "MESSAGE-INTEGRITY",
    TYPE_ERROR_CODE: "ERROR-CODE",
    TYPE_UNKNOWN_ATTRIBUTES: "UNKNOWN-ATTRIBUTES",
    TYPE_REFLECTED_FROM: "REFLECTED-FROM",
    TYPE_REALM: "REALM",
    TYPE_NONCE: "NONCE",
    TYPE_XOR_MAPPED_ADDRESS: "XOR-MAPPED-ADDRESS",
    TYPE_PADDING: "PADDING",
    TYPE_RESPONSE_PORT: "RESPONSE-PORT",
    TYPE_SOFTWARE: "SOFTWARE",
    TYPE_ALTERNATE_SERVER: "ALTERNATE-SERVER",
    TYPE_FINGERPRINT: "FINGERPRINT",
    TYPE_RESPONSE_ORIGIN: "RESPONSE-ORIGIN",
    TYPE_OTHER_ADDRESS: "OTHER-ADDRESS",
  };

  abstract int type;

  abstract int length;

  String? get typeDisplayName =>
      "${TYPE_STRINGS[type] ?? "Undefined"}(0x${type.toRadixString(16).padLeft(4, "0")})"; //todo

  fromBuffer(BitBufferReader reader, int type, int length) {
    assert(type == this.type);
    // this.type = type;
    // this.length = length;
  }

  Uint8List toBuffer();

  @override
  String toString() {
    return """
  ${typeDisplayName}: 暂未设置解析规则
    Attribute Type: ${typeDisplayName}
    Attribute Length: ${length}
  """;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StunAttributes &&
          runtimeType == other.runtimeType &&
          type == other.type;

  @override
  int get hashCode => type.hashCode;
}

abstract class StunUInt8ListAttributes extends StunAttributes {
  @override
  late int length = value.length;

  late List<int> value;

  @override
  fromBuffer(BitBufferReader reader, int type, int length) {
    super.fromBuffer(reader, type, length);
    this.value = reader.readIntList(length * 8,
        binaryDigits: 8, order: BitOrder.MSBFirst);
  }

  @override
  Uint8List toBuffer() {
    BitBuffer bitBuffer = BitBuffer();
    BitBufferWriter writer = BitBufferWriter(bitBuffer);
    writer.writeUint(type, binaryDigits: 16);
    writer.writeUint(length, binaryDigits: 16);
    writer.writeIntList(value, binaryDigits: 8, order: BitOrder.MSBFirst);
    return bitBuffer.toUint8List();
  }

  @override
  String toString() {
    return """
  ${typeDisplayName}:
    Attribute Type: ${typeDisplayName}
    Attribute Length: ${length}
    key: ${value}
  """;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StunUInt8ListAttributes &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;
}

abstract class StunTextAttributes extends StunAttributes {
  @override
  late int length = value.length;

  late String value;

  @override
  fromBuffer(BitBufferReader reader, int type, int length) {
    super.fromBuffer(reader, type, length);
    this.value = reader.readUtf8String(length * 8,
        binaryDigits: 8, order: BitOrder.MSBFirst);
  }

  @override
  Uint8List toBuffer() {
    BitBuffer bitBuffer = BitBuffer();
    BitBufferWriter writer = BitBufferWriter(bitBuffer);
    writer.writeUint(type, binaryDigits: 16);
    writer.writeUint(length, binaryDigits: 16);
    writer.writeUtf8String(value, binaryDigits: 8, order: BitOrder.MSBFirst);
    return bitBuffer.toUint8List();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StunTextAttributes &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;
}

abstract class AddressAttribute extends StunAttributes {
  static const int FAMILY_IPV4 = 0x01;
  static const int FAMILY_IPV6 = 0x02;
  static final FAMILY_STRINGS = {
    FAMILY_IPV4: "IPv4",
    FAMILY_IPV6: "IPv6",
  };

  @override
  int length = 8;

  String? get familyDisplayName => FAMILY_STRINGS[family];

  late int head;
  late int family;
  late int port;
  late int address;

  @override
  fromBuffer(BitBufferReader reader, int type, int length) {
    super.fromBuffer(reader, type, length);
    this.head = reader.readUint(binaryDigits: 8);
    this.family = reader.readUint(binaryDigits: 8);
    this.port = reader.readUint(binaryDigits: 16);
    switch (family) {
      case FAMILY_IPV4:
        this.address = reader.readUint(binaryDigits: 32);
      case FAMILY_IPV6:
        this.address = reader.readUint(binaryDigits: 128);
      default:
        throw ArgumentError();
    }
  }

  @override
  Uint8List toBuffer() {
    BitBuffer bitBuffer = BitBuffer();
    BitBufferWriter writer = BitBufferWriter(bitBuffer);
    writer.writeUint(type, binaryDigits: 16);
    writer.writeUint(length, binaryDigits: 16);
    writer.writeUint(head, binaryDigits: 8);
    writer.writeUint(family, binaryDigits: 8);
    writer.writeUint(port, binaryDigits: 16);

    switch (family) {
      case FAMILY_IPV4:
        writer.writeUint(address, binaryDigits: 32);
      case FAMILY_IPV6:
        writer.writeUint(address, binaryDigits: 128);
        length = 20;
      default:
        throw ArgumentError('Invalid address family: $family');
    }

    return bitBuffer.toUint8List();
  }

  String? get addressDisplayName {
    BitBuffer bitBuffer = BitBuffer();
    BitBufferWriter writer = BitBufferWriter(bitBuffer);
    BitBufferReader reader = BitBufferReader(bitBuffer);
    switch (family) {
      case FAMILY_IPV4:
        writer.writeUint(address, binaryDigits: 32, order: BitOrder.MSBFirst);
        return "${reader.readUint(binaryDigits: 8, order: BitOrder.MSBFirst)}.${reader.readUint(binaryDigits: 8, order: BitOrder.MSBFirst)}.${reader.readUint(binaryDigits: 8, order: BitOrder.MSBFirst)}.${reader.readUint(binaryDigits: 8, order: BitOrder.MSBFirst)}";
      case FAMILY_IPV6:
        writer.writeUint(address, binaryDigits: 128, order: BitOrder.MSBFirst);
        return "";
      default:
        return "";
    }
  }

  @override
  String toString() {
    return """
  ${typeDisplayName}: ${addressDisplayName}:${port}
    Attribute Type: ${typeDisplayName}
    Attribute Length: ${length}
    Reserved: ${head}
    Protocol Family: ${familyDisplayName} (0x0$family)
    Port: ${port}
    IP: ${addressDisplayName}
  """;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AddressAttribute &&
          runtimeType == other.runtimeType &&
          port == other.port &&
          address == other.address;

  @override
  int get hashCode => port.hashCode ^ address.hashCode;
}
