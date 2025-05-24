import 'dart:typed_data';

import 'handshake.dart';

class ServerHelloDone {
  ContentType getContentType() {
    return ContentType.content_handshake;
  }

  HandshakeType getHandshakeType() {
    return HandshakeType.server_hello_done;
  }

  Uint8List marshal() {
    return Uint8List(0);
  }

  static (ServerHelloDone, int, bool?) unmarshal(
      Uint8List buf, int offset, int arrayLen) {
    return (ServerHelloDone(), offset, null);
  }
}
