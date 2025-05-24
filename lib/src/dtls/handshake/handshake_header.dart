import 'dart:typed_data';

import '../dtls_message.dart';
import '../record_layer_header.dart';
import 'certificate.dart';
import 'certificate_verify.dart';
import 'client_hello.dart';
import 'client_key_exchange.dart';
import 'finished.dart';
import 'handshake.dart';
import 'hello_verify_request.dart';
import 'server_hello.dart';
import 'server_key_exchange.dart';

class Uint24 {
  final int value;

  Uint24(this.value);

  factory Uint24.fromBytes(Uint8List bytes) {
    return Uint24((bytes[0] << 16) | (bytes[1] << 8) | bytes[2]);
  }

  factory Uint24.fromUInt32(int value) {
    return Uint24(value & 0xFFFFFF);
  }

  int toUint32() {
    return value;
  }

  Uint8List toBytes() {
    return Uint8List(3)
      ..[0] = (value >> 16) & 0xFF
      ..[1] = (value >> 8) & 0xFF
      ..[2] = value & 0xFF;
  }

  @override
  String toString() {
    // TODO: implement toString
    return "{Uin24: $value}";
  }
}

class HandshakeHeader {
  final HandshakeType handshakeType;
  final Uint24 length; // uint24 in spec
  final int messageSequence;
  final Uint24 fragmentOffset; // uint24 in spec
  final Uint24 fragmentLength; // uint24 in spec

  static const HANDSHAKE_HEADER_LENGTH = 12;

  HandshakeHeader({
    required this.handshakeType,
    required this.length,
    required this.messageSequence,
    required this.fragmentOffset,
    required this.fragmentLength,
  });

  int size() {
    return 1 +
        3 +
        2 +
        3 +
        3; // 1 byte for handshake type, 3 for length, 2 for message_sequence, 3 for fragment_offset, 3 for fragment_length
  }

  Uint8List marshal() {
    final bb = BytesBuilder();
    bb.addByte(handshakeType.value);
    bb.add(length.toBytes());

    ByteData bd = ByteData(2);
    bd.setUint16(0, messageSequence);
    bb.add(bd.buffer.asUint8List());

    bb.add(fragmentOffset.toBytes());

    bb.add(fragmentLength.toBytes());

    return bb.toBytes();
  }

  static (HandshakeHeader, int, bool?) unmarshal(
      Uint8List data, int offset, int arrayLen) {
    //int offset = 0;
    HandshakeType handshakeType = HandshakeType.fromInt(data[offset]);
    offset++;

    final length = Uint24.fromBytes(data.sublist(offset, offset + 3));
    offset = offset + 3;
    final messageSequence =
        ByteData.sublistView(data, offset, offset + 2).getUint16(0, Endian.big);
    offset += 2;
    final fragmentOffset = Uint24.fromBytes(data.sublist(offset, offset + 3));
    offset += 3;
    final fragmentLength = Uint24.fromBytes(data.sublist(offset, offset + 3));
    offset += 3;

    return (
      HandshakeHeader(
        handshakeType: handshakeType,
        length: length,
        messageSequence: messageSequence,
        fragmentOffset: fragmentOffset,
        fragmentLength: fragmentLength,
      ),
      offset,
      null
    );
  }

  @override
  String toString() {
    return 'HandshakeHeader(\n'
        '  handshakeType: ${handshakeType.name},\n'
        '  length: $length,\n'
        '  messageSequence: $messageSequence,\n'
        '  fragmentOffset: $fragmentOffset,\n'
        '  fragmentLength: $fragmentLength\n'
        ')';
  }

  static (HandshakeHeader, int, bool?) decode(
      Uint8List buf, int offset, int arrayLen) {
    var (hh, decodedOffset, err) =
        HandshakeHeader.unmarshal(buf, offset, arrayLen);
    // (handshakeHeader, decodedOffset, err)
    offset = decodedOffset;
    return (hh, offset, false);
  }
}

(dynamic, int, bool?) decodeHandshake(RecordLayerHeader header,
    HandshakeHeader handshakeHeader, Uint8List buf, int offset, int arrayLen) {
  // late BaseDtlsMessage result;
  dynamic result;
  switch (handshakeHeader.handshakeType) {
    case HandshakeType.client_hello:
      return ClientHello.unmarshal(buf, offset, arrayLen);
    //break;
    case HandshakeType.hello_verify_request:
      return HelloVerifyRequest.unmarshal(buf, offset, arrayLen);

    case HandshakeType.server_hello:
      return ServerHello.unmarshal(buf, offset, arrayLen);

    case HandshakeType.certificate:
      return Certificate.decode(buf, offset, arrayLen);

    case HandshakeType.server_key_exchange:
      return ServerKeyExchange.decode(buf, offset, arrayLen);
    // break;
    // case HandshakeType.certificate_request:
    //   return CertificateRequest.decode(buf, offset, arrayLen);

    // case HandshakeType.server_hello_done:
    //   return ServerHelloDone.unmarshal(buf, offset, arrayLen);

    case HandshakeType.client_key_exchange:
      // print("Handshake: $handshakeHeader");
      return ClientKeyExchange.unmarshal(buf, offset, arrayLen);

    case HandshakeType.certificate_verify:
      return CertificateVerify.decode(buf, offset, arrayLen);

    case HandshakeType.finished:
      // print("Handshake type: ${handshakeHeader.handshakeType}");
      return Finished.unmarshal(buf, offset, arrayLen);
    default:
      print("Unkown handshake type: ${handshakeHeader.handshakeType}");
      throw ArgumentError(DtlsErrors.errUnknownDtlsHandshakeType);
  }
  // var (decodeOffset, err) = result.decode(buf, offset, arrayLen);
  return result;
}

void main() {
  // Example usage of HandshakeHeader
  // final header = HandshakeHeader(
  //   handshakeType: HandshakeType.clientHello,
  //   length: 12345,
  //   messageSequence: 1,
  //   fragmentOffset: 10,
  //   fragmentLength: 20,
  // );

  // final size = header.size();
  // print('HandshakeHeader size: $size');

  // final writer = ByteData(size);
  // header.marshal(writer);
  // print('Marshaled data: ${writer.buffer.asUint8List()}');

  final (unmarshalledHeader, _, _) = HandshakeHeader.unmarshal(
      raw_handshake_message, 0, raw_handshake_message.length);

  print('Unmarshalled HandshakeHeader: $unmarshalledHeader');
  print("Re-marshalled: ${unmarshalledHeader.marshal()}");

  print("Expected:      $raw_handshake_message");
}

final raw_handshake_message = Uint8List.fromList([
  0x01,
  0x00,
  0x00,
  0x29,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x29,
  0xfe,
  0xfd,
  0xb6,
  0x2f,
  0xce,
  0x5c,
  0x42,
  0x54,
  0xff,
  0x86,
  0xe1,
  0x24,
  0x41,
  0x91,
  0x42,
  0x62,
  0x15,
  0xad,
  0x16,
  0xc9,
  0x15,
  0x8d,
  0x95,
  0x71,
  0x8a,
  0xbb,
  0x22,
  0xd7,
  0x47,
  0xec,
  0xd8,
  0x3d,
  0xdc,
  0x4b,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
]);
