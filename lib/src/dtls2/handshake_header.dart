import 'dart:typed_data';
import 'dtls.dart'; // Assuming DtlsVersion and common types are here

// A custom class to handle 24-bit integers (3 bytes)
class Uint24 {
  final Uint8List bytes; // 3 bytes

  Uint24(this.bytes) : assert(bytes.length == 3);

  factory Uint24.fromUint32(int value) {
    final bd = ByteData(4)..setUint32(0, value, Endian.big);
    return Uint24(Uint8List.fromList(bd.buffer.asUint8List().sublist(1, 4)));
  }

  factory Uint24.fromBytes(Uint8List buf) {
    return Uint24(Uint8List.fromList(buf.sublist(0, 3)));
  }

  int toUint32() {
    final bd = ByteData(4)
      ..setUint8(1, bytes[0])
      ..setUint8(2, bytes[1])
      ..setUint8(3, bytes[2]);
    return bd.getUint32(0, Endian.big);
  }

  @override
  String toString() => toUint32().toString();
}

enum HandshakeType {
  helloRequest(0),
  clientHello(1),
  serverHello(2),
  helloVerifyRequest(3),
  certificate(11),
  serverKeyExchange(12),
  certificateRequest(13),
  serverHelloDone(14),
  certificateVerify(15),
  clientKeyExchange(16),
  finished(20),
  unsupported(99); // Placeholder for unknown types

  const HandshakeType(this.value);
  final int value;

  factory HandshakeType.fromInt(int val) {
    return values.firstWhere((element) => element.value == val,
        orElse: () => HandshakeType.unsupported);
  }

  @override
  String toString() {
    switch (this) {
      case HandshakeType.helloRequest:
        return 'HelloRequest';
      case HandshakeType.clientHello:
        return 'ClientHello';
      case HandshakeType.serverHello:
        return 'ServerHello';
      case HandshakeType.helloVerifyRequest:
        return 'HelloVerifyRequest';
      case HandshakeType.certificate:
        return 'Certificate';
      case HandshakeType.serverKeyExchange:
        return 'ServerKeyExchange';
      case HandshakeType.certificateRequest:
        return 'CertificateRequest';
      case HandshakeType.serverHelloDone:
        return 'ServerHelloDone';
      case HandshakeType.certificateVerify:
        return 'CertificateVerify';
      case HandshakeType.clientKeyExchange:
        return 'ClientKeyExchange';
      case HandshakeType.finished:
        return 'Finished';
      default:
        return 'Unknown type';
    }
  }
}

/// Represents the header of a DTLS handshake message.
/// Corresponds to Go's `HandshakeHeader` struct.
class HandshakeHeader {
  HandshakeType handshakeType;
  Uint24 length;
  int messageSequence;
  Uint24 fragmentOffset;
  Uint24 fragmentLength;

  HandshakeHeader({
    required this.handshakeType,
    required this.length,
    required this.messageSequence,
    required this.fragmentOffset,
    required this.fragmentLength,
  });

  /// Encodes the HandshakeHeader into a byte array.
  /// Corresponds to Go's `Encode` method.
  Uint8List encode() {
    final result = Uint8List(12);
    final ByteData bd = ByteData.view(result.buffer);

    bd.setUint8(0, handshakeType.value);
    result.setRange(1, 4, length.bytes);
    bd.setUint16(4, messageSequence, Endian.big);
    result.setRange(6, 9, fragmentOffset.bytes);
    result.setRange(9, 12, fragmentLength.bytes);

    return result;
  }

  /// Decodes a HandshakeHeader from a byte array.
  /// Corresponds to Go's `DecodeHandshakeHeader` function.
  static (HandshakeHeader, int) decode(
      Uint8List buf, int offset, int arrayLen) {
    if (offset + 12 > arrayLen) {
      // return (
      //   HandshakeHeader(
      //     handshakeType: HandshakeType.unsupported,
      //     length: Uint24(Uint8List(3)),
      //     messageSequence: 0,
      //     fragmentOffset: Uint24(Uint8List(3)),
      //     fragmentLength: Uint24(Uint8List(3)),
      //   ),
      //   offset,
      throw Exception('Incomplete DTLS handshake header');
      // );
    }

    final reader = ByteData.sublistView(buf, offset);

    final handshakeType = HandshakeType.fromInt(reader.getUint8(0));
    final length = Uint24.fromBytes(buf.sublist(offset + 1, offset + 4));
    final messageSequence = reader.getUint16(4, Endian.big);
    final fragmentOffset =
        Uint24.fromBytes(buf.sublist(offset + 6, offset + 9));
    final fragmentLength =
        Uint24.fromBytes(buf.sublist(offset + 9, offset + 12));

    return (
      HandshakeHeader(
        handshakeType: handshakeType,
        length: length,
        messageSequence: messageSequence,
        fragmentOffset: fragmentOffset,
        fragmentLength: fragmentLength,
      ),
      offset + 12
    );
  }

  @override
  String toString() {
    return 'HandshakeHeader(handshakeType: ${handshakeType.toString().split('.').last}, length: ${length.toUint32()}, messageSequence: $messageSequence, fragmentOffset: ${fragmentOffset.toUint32()}, fragmentLength: ${fragmentLength.toUint32()})';
  }
}
