import 'dart:typed_data';

import 'handshake/handshake.dart';

class RecordLayerHeader {
  final ContentType contentType;
  final ProtocolVersion protocolVersion;
  final int epoch;
  final int sequenceNumber; // uint48 in spec
  int contentLen;

  static const MAX_SEQUENCE_NUMBER = 0x0000FFFFFFFFFFFF;
  static const RECORD_LAYER_HEADER_SIZE = 13;

  RecordLayerHeader({
    required this.contentType,
    required this.protocolVersion,
    required this.epoch,
    required this.sequenceNumber,
    required this.contentLen,
  });

  int size() {
    return RECORD_LAYER_HEADER_SIZE;
  }

  Uint8List marshalSequence() {
    final bd = ByteData(6);
    bd.setUint8(0, (sequenceNumber >> 40) & 0xFF);
    bd.setUint8(1, (sequenceNumber >> 32) & 0xFF);
    bd.setUint8(2, (sequenceNumber >> 24) & 0xFF);
    bd.setUint8(3, (sequenceNumber >> 16) & 0xFF);
    bd.setUint8(4, (sequenceNumber >> 8) & 0xFF);
    bd.setUint8(5, sequenceNumber & 0xFF);
    return bd.buffer.asUint8List();
  }

  Uint8List marshal() {
    if (sequenceNumber > MAX_SEQUENCE_NUMBER) {
      throw ArgumentError("Sequence number exceeds maximum allowed value.");
    }
    final bb = BytesBuilder();
// Encode content type
    bb.addByte(contentType.value);
// Encode version
    bb.addByte(protocolVersion.major);
    bb.addByte(protocolVersion.minor);

    // Encode epoch
    ByteData bd = ByteData(2);
    bd.setUint16(0, epoch);
    bb.add(bd.buffer.asUint8List());

    // Encode sequence number as uint48 (first 6 bytes of an 8-byte integer)
    bd = ByteData(6);
    bd.setUint8(0, (sequenceNumber >> 40) & 0xFF);
    bd.setUint8(1, (sequenceNumber >> 32) & 0xFF);
    bd.setUint8(2, (sequenceNumber >> 24) & 0xFF);
    bd.setUint8(3, (sequenceNumber >> 16) & 0xFF);
    bd.setUint8(4, (sequenceNumber >> 8) & 0xFF);
    bd.setUint8(5, sequenceNumber & 0xFF);
    bb.add(bd.buffer.asUint8List());

// Encode length
    bd = ByteData(2);
    bd.setUint16(0, contentLen, Endian.big);
    bb.add(bd.buffer.asUint8List());
    return bb.toBytes();
  }

  // Uint8List encode() {
  //   final buffer = BytesBuilder();

  //   // Encode content type
  //   buffer.addByte(contentType.value);

  //   // Encode version
  //   final versionBytes = ByteData(2);
  //   versionBytes.setUint16(0, version.value, Endian.big);
  //   buffer.add(versionBytes.buffer.asUint8List());

  //   // Encode epoch
  //   final epochBytes = ByteData(2);
  //   epochBytes.setUint16(0, epoch, Endian.big);
  //   buffer.add(epochBytes.buffer.asUint8List());

  //   // Encode sequence number
  //   buffer.add(sequenceNumber);

  //   // Encode length
  //   final lengthBytes = ByteData(2);
  //   lengthBytes.setUint16(0, length, Endian.big);
  //   buffer.add(lengthBytes.buffer.asUint8List());

  //   return buffer.toBytes();
  // }

  static (RecordLayerHeader, int, bool?) unmarshal(Uint8List data,
      {required int offset, required int arrayLen}) {
    if (data.length < RECORD_LAYER_HEADER_SIZE) {
      throw ArgumentError("Insufficient data length for unmarshaling.");
    }

    final reader = ByteData.sublistView(data);

    ContentType contentType = ContentType.fromInt(reader.getUint8(offset++));

    if (contentType != ContentType.content_handshake) {
      print("Content type: $contentType");
    }
    int major = reader.getUint8(offset++);
    int minor = reader.getUint8(offset++);
    int epoch = reader.getUint16(offset, Endian.big);
    offset += 2;

    // Decode sequence number as uint48 (6 bytes)
    int sequenceNumber = (reader.getUint8(offset) << 40) |
        (reader.getUint8(offset + 1) << 32) |
        (reader.getUint8(offset + 2) << 24) |
        (reader.getUint8(offset + 3) << 16) |
        (reader.getUint8(offset + 4) << 8) |
        reader.getUint8(offset + 5);
    offset += 6;

    ProtocolVersion protocolVersion = ProtocolVersion(major, minor);

    int contentLen = reader.getUint16(offset, Endian.big);
    offset += 2;

    return (
      RecordLayerHeader(
        contentType: contentType,
        protocolVersion: protocolVersion,
        epoch: epoch,
        sequenceNumber: sequenceNumber,
        contentLen: contentLen,
      ),
      offset,
      null
    );
  }

  @override
  String toString() {
    return '''
RecordLayerHeader {
  contentType: ${contentType.name} (${contentType.value}),
  protocolVersion: $protocolVersion,
  epoch: $epoch,
  sequenceNumber: $sequenceNumber,
  contentLen: $contentLen
}''';
  }

  // static (RecordLayerHeader, int, bool?) decode(
  //     Uint8List buf, int offset, int arrayLen) {
  //   final (rh, decodedOffset, err) =
  //       RecordLayerHeader.unmarshal(buf, offset: offset, arrayLen: arrayLen);
  //   return (rh, decodedOffset, null);
  // }
}

void main() {
  // Example usage of RecordLayerHeader
  // final header = RecordLayerHeader(
  //   contentType: ContentType.handshake,
  //   protocolVersion: ProtocolVersion.VERSION_DTLS12,
  //   epoch: 1,
  //   sequenceNumber: 12345678901234,
  //   contentLen: 100,
  // );

  // final size = header.size();
  // print('RecordLayerHeader size: $size');

  // final writer = ByteData(size);
  // header.marshal(writer);
  // print('Marshaled data: ${writer.buffer.asUint8List()}');

  var (unmarshalledHeader, _, _) = RecordLayerHeader.unmarshal(changeCipherSpec,
      offset: 0, arrayLen: changeCipherSpec.length);
  print('Unmarshalled RecordLayerHeader: $unmarshalledHeader');

  final encdeCodeRecordHeader = unmarshalledHeader.marshal();
  print("Marshalled: $encdeCodeRecordHeader");
  print("Expected:   $changeCipherSpec");

  (unmarshalledHeader, _, _) = RecordLayerHeader.unmarshal(
      encdeCodeRecordHeader,
      offset: 0,
      arrayLen: encdeCodeRecordHeader.length);

  print('Re-unmarshalled RecordLayerHeader: $unmarshalledHeader');
}

final changeCipherSpec = Uint8List.fromList([
  0x14,
  0xfe,
  0xff,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x12,
  0x00,
  0x01,
  0x01,
]);
