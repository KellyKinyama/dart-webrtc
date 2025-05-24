import 'dart:typed_data';

import 'handshake.dart';

class Certificate {
  static const int handshakeMessageCertificateLengthFieldSize = 3;
  final List<Uint8List> certificate;

  Certificate({required this.certificate});

  ContentType getContentType() {
    return ContentType.content_handshake;
  }

  // Handshake type
  HandshakeType getHandshakeType() {
    return HandshakeType.certificate;
  }

  // Calculate size
  int size() {
    int len = 3; // Initial payload size
    for (var r in certificate) {
      len += handshakeMessageCertificateLengthFieldSize + r.length;
    }
    return len;
  }

  // Marshal to byte array
  Uint8List marshal() {
    final byteData = BytesBuilder();

    // Calculate total payload size
    int payloadSize = 0;
    for (var r in certificate) {
      payloadSize += handshakeMessageCertificateLengthFieldSize + r.length;
    }

    // Write total payload size
    _writeUint24(byteData, payloadSize);

    // Write each certificate
    for (var r in certificate) {
      // Write certificate length
      _writeUint24(byteData, r.length);

      // Write certificate body
      byteData.add(r);
    }

    return byteData.toBytes();
  }

  // Unmarshal from byte array
  static Certificate unmarshal(Uint8List data) {
    final reader = ByteData.sublistView(data);
    int offset = 0;

    // Read total payload size
    final payloadSize = _readUint24(reader, offset);
    offset += handshakeMessageCertificateLengthFieldSize;

    final List<Uint8List> certificates = [];
    int currentOffset = 0;

    while (currentOffset < payloadSize) {
      // Read certificate length
      final certificateLen = _readUint24(reader, offset);
      offset += handshakeMessageCertificateLengthFieldSize;

      // Read certificate body
      final certificate =
          Uint8List.sublistView(data, offset, offset + certificateLen);
      certificates.add(certificate);

      offset += certificateLen;
      currentOffset +=
          handshakeMessageCertificateLengthFieldSize + certificateLen;
    }

    return Certificate(certificate: certificates);
  }

  // Helper to write a 3-byte integer (u24)
  static void _writeUint24(BytesBuilder builder, int value) {
    builder.add([
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
  }

  // Helper to read a 3-byte integer (u24)
  static int _readUint24(ByteData reader, int offset) {
    return (reader.getUint8(offset) << 16) |
        (reader.getUint8(offset + 1) << 8) |
        reader.getUint8(offset + 2);
  }

  @override
  String toString() {
    return 'HandshakeMessageCertificate(certificates: ${certificate.length} items)';
  }

  static decode(Uint8List buf, int offset, int arrayLen) {}
}

void main() {
  // Example usage
  final message = Certificate(
    certificate: [
      Uint8List.fromList([0x01, 0x02, 0x03]),
      Uint8List.fromList([0x04, 0x05, 0x06, 0x07]),
    ],
  );

  // Marshal the message
  final marshalledData = message.marshal();
  //print('Marshalled Data: $marshalledData');

  // Unmarshal back to an object
  final unmarshalledMessage = Certificate.unmarshal(marshalledData);
  //print('Unmarshalled Message: $unmarshalledMessage');
}
