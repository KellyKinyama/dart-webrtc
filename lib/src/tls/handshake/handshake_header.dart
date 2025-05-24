import 'dart:typed_data';

import 'package:dartls/src/tls/handshake/client_hello.dart';
import 'package:dartls/types/types.dart';

enum HandshakeType {
  hello_request(0),
  client_hello(1),
  server_hello(2),
  hello_verify_request(3),
  certificate(11),
  server_key_exchange(12),
  certificate_request(13),
  server_hello_done(14),
  certificate_verify(15),
  client_key_exchange(16),
  finished(20);

  const HandshakeType(this.value);
  final int value;

  factory HandshakeType.fromInt(Uint8 key) {
    return values.firstWhere((element) => element.value == key.value);
  }
}

class HandshakeHeader {
  HandshakeType handshakeType;
  Uint24 payloadLength;
  HandshakeHeader(this.handshakeType, this.payloadLength);

  factory HandshakeHeader.unmarshal(Uint8List data, int offset, int arrayLen) {
    HandshakeType handshakeType = HandshakeType.fromInt(Uint8(data[offset]));
    offset++;
    Uint24 payloadLength = Uint24.fromBytes(data.sublist(offset, offset + 3));
    return HandshakeHeader(handshakeType, payloadLength);
  }

  Uint8List marshal() {
    BytesBuilder bb = BytesBuilder();
    bb.addByte(handshakeType.value);
    bb.add(payloadLength.toBytes());

    return bb.toBytes();
  }

  @override
  String toString() {
    // TODO: implement toString
    return """
HandshakeHeader {
  handshakeType: $handshakeType,
  payload length: $payloadLength
}
""";
  }
}

(dynamic, int) decodeHandshake(
    HandshakeHeader hh, Uint8List data, int offset, int arrayLen) {
  switch (hh.handshakeType) {
    case HandshakeType.client_hello:
      {
        return (ClientHello.unmarshal(data, offset, arrayLen), offset);
      }
    default:
      {
        throw "Unhandled handshake type";
      }
  }
}

void main() {}
