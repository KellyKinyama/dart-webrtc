import 'dart:typed_data';

import 'dtls.dart';
import 'handshake_header.dart';

class Finished {
  Uint8List verifyData;

  Finished(this.verifyData);

  ContentType getContentType() {
    return ContentType.handshake;
  }

  // Handshake type
  HandshakeType getHandshakeType() {
    return HandshakeType.finished;
  }

  //Finished(HandshakeType type, Uint8List data) : super(type, data);

  static (Finished, int) decode(Uint8List buf, int offset, int arrayLen) {
    // 	m.VerifyData = make([]byte, arrayLen)
    // copy(m.VerifyData, buf[offset:offset+arrayLen])
    final verifyData = buf.sublist(offset);
    offset += verifyData.length;
    return (Finished(verifyData), offset);
// return
  }

  Uint8List encode() {
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
