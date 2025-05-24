import 'dart:typed_data';

import 'package:dartls/src/tls/test_data.dart';

import '../../types/types.dart';
import 'protocol_version.dart';

enum TlsContentType {
  content_change_cipher_spec(20),
  content_alert(21),
  content_handshake(22),
  content_application_data(23);

  const TlsContentType(this.value);
  final int value;

  factory TlsContentType.fromInt(Uint8 key) {
    return values.firstWhere((element) => element.value == key.value);
  }
}

class RecordLayer {
  TlsContentType contentType;
  ProtocolVersion protocolVersion;
  Uint16 length;
  // Uint48 sequenceNumber;
  // Uint16 contentLength;

  RecordLayer(this.contentType, this.protocolVersion, this.length //,
      // this.sequenceNumber,
      // this.contentLength
      );

  factory RecordLayer.unmarshal(Uint8List data, int offset, int arrayLen) {
    ByteData reader = ByteData.sublistView(data);
    final contentType = TlsContentType.fromInt(Uint8(data[offset]));
    offset++;
    final protocolVersion =
        ProtocolVersion(Uint8(data[offset]), Uint8(data[offset + 1]));
    offset += 2;

    Uint16 length = Uint16(reader.getUint16(offset));
    offset += 2;

    return RecordLayer(contentType, protocolVersion, length
        // , sequenceNumber,
        //  contentLength
        );
  }

  Uint8List marshal() {
    BytesBuilder bb = BytesBuilder();
    bb.addByte(contentType.value);
    bb.add(protocolVersion.marshal());

    bb.add(length.toBytes());
    return bb.toBytes();
  }

  @override
  String toString() {
    // TODO: implement toString
    return """Record Header{
      Content type: $contentType,
      protocol version: $protocolVersion,
      length: $length,
    }""";
  }
}

void main() {
  final recordLayer =
      RecordLayer.unmarshal(rawClientHello, 0, rawClientHello.length);
  print("Record header: $recordLayer");
  print("raw length: ${rawClientHello.length}");
}
