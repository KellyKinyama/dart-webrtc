import 'dart:typed_data';

import 'dtls.dart';
import 'handshake_header.dart';

class ServerHelloDone {
  ContentType getContentType() {
    return ContentType.handshake;
  }

  HandshakeType getHandshakeType() {
    return HandshakeType.serverHelloDone;
  }

  Uint8List encode() {
    return Uint8List(0);
  }

  static (ServerHelloDone, int, bool?) unmarshal(
      Uint8List buf, int offset, int arrayLen) {
    return (ServerHelloDone(), offset, null);
  }
}
