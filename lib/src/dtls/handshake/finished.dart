import 'dart:typed_data';

import 'handshake.dart';

class Finished {
  Uint8List verifyData;

  Finished(this.verifyData);

  ContentType getContentType() {
    return ContentType.content_handshake;
  }

  // Handshake type
  HandshakeType getHandshakeType() {
    return HandshakeType.finished;
  }

  //Finished(HandshakeType type, Uint8List data) : super(type, data);

  static (Finished, int, bool?) unmarshal(
      Uint8List buf, int offset, int arrayLen) {
    // 	m.VerifyData = make([]byte, arrayLen)
    // copy(m.VerifyData, buf[offset:offset+arrayLen])
    final verifyData = buf.sublist(offset);
    offset += verifyData.length;
    return (Finished(verifyData), offset, null);
// return
  }

  Uint8List marshal() {
    // 	m.VerifyData = make([]byte, arrayLen)
    // copy(m.VerifyData, buf[offset:offset+arrayLen])
    // offset += len(m.VerifyData)
    return verifyData;
// return
  }

  @override
  String toString() {
    // TODO: implement toString
    return "Finished {verifyData: $verifyData}";
  }
}
