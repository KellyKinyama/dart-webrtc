import 'dart:typed_data';

import 'package:dartls/src/tls/handshake/handshake_header.dart';
import 'package:dartls/src/tls/record_layer.dart';
import 'package:dartls/src/tls/test_data.dart';

class TlsMessage {
  RecordLayer recordLayer;
  HandshakeHeader handshakeHeader;
  dynamic message;

  TlsMessage(this.recordLayer, this.handshakeHeader, this.message);

  factory TlsMessage.unmarshal(Uint8List data, int offset, int arrayLen) {
    RecordLayer recordLayer = RecordLayer.unmarshal(data, offset, arrayLen);
    offset += 5;

    switch (recordLayer.contentType) {
      case TlsContentType.content_handshake:
        HandshakeHeader handshakeHeader =
            HandshakeHeader.unmarshal(data, offset, arrayLen);
        offset += 4;

        var (handshake, decodedOffset) =
            decodeHandshake(handshakeHeader, data, offset, data.length);
        print("decoded handshake: $handshake");

        return TlsMessage(recordLayer, handshakeHeader, handshake!);
      default:
        {
          throw "Unhandle content type: ${recordLayer.contentType}";
        }
    }
  }

  @override
  String toString() {
    // TODO: implement toString
    return """Tls Message{
      record layer: $recordLayer,
      handshake header: $handshakeHeader,
      message: $message,
    }""";
  }
}

void main() {
  TlsMessage tlsMessage =
      TlsMessage.unmarshal(rawClientHello, 0, rawClientHello.length);
  print("Tls message: $tlsMessage");
}
