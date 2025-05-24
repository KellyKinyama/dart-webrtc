import 'dart:convert';
import 'dart:typed_data';
import 'package:typed_data/typed_data.dart';

const int EXTENSION_SERVER_NAME_TYPE_DNSHOST_NAME = 0;

class ExtensionServerName {
  final String serverName;

  ExtensionServerName(this.serverName);

  int get extensionValue => ExtensionValue.serverName;

  int size() {
    return 2 + 2 + 1 + 2 + utf8.encode(serverName).length;
  }

  Uint8List marshal() {
    final data = BytesBuilder();

    final serverNameBytes = utf8.encode(serverName);
    final totalLength = 2 + 1 + 2 + serverNameBytes.length;
    final entryLength = 1 + 2 + serverNameBytes.length;

    data.add(_uint16ToBytes(totalLength));
    data.add(_uint16ToBytes(entryLength));
    data.addByte(EXTENSION_SERVER_NAME_TYPE_DNSHOST_NAME);
    data.add(_uint16ToBytes(serverNameBytes.length));
    data.add(serverNameBytes);

    return data.toBytes();
  }

  static ExtensionServerName unmarshal(Uint8List bytes) {
    final buffer = ByteData.sublistView(bytes);
    int offset = 0;

    int _readUint16() {
      final value = buffer.getUint16(offset, Endian.big);
      offset += 2;
      return value;
    }

    int totalLength = _readUint16();
    int entryLength = _readUint16();
    int nameType = buffer.getUint8(offset++);
    if (nameType != EXTENSION_SERVER_NAME_TYPE_DNSHOST_NAME) {
      throw FormatException("Invalid SNI format");
    }

    int serverNameLength = _readUint16();
    final serverNameBytes = bytes.sublist(offset, offset + serverNameLength);
    final serverName = utf8.decode(serverNameBytes);

    return ExtensionServerName(serverName);
  }

  static Uint8List _uint16ToBytes(int value) {
    final bytes = Uint8List(2);
    final byteData = ByteData.sublistView(bytes);
    byteData.setUint16(0, value, Endian.big);
    return bytes;
  }
}

class ExtensionValue {
  static const int serverName = 0x0000; // Placeholder value
}
