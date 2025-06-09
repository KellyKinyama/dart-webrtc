import 'dart:typed_data';

import 'dtls.dart';

class ApplicationData {
  Uint8List applicationData;
  ApplicationData(this.applicationData);

  ContentType getContentType() {
    return ContentType.applicationData;
  }

  static (ApplicationData, int, bool?) unmarshal(
      Uint8List buf, int offset, int arrayLen) {
    Uint8List applicationData = buf.sublist(offset);
    offset += applicationData.length;
    return (ApplicationData(applicationData), offset, null);
  }

  Uint8List marshal() {
    return applicationData;
  }

  // Handshake type
  // HandshakeType getHandshakeType() {
  //   return HandshakeType.client_key_exchange;
  // }
}
