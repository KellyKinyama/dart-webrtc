import 'dart:typed_data';

import 'package:dartls/src/tls/protocol_version.dart';

import '../../../types/types.dart';
import '../extensions/extensions.dart';
import '../tls_random.dart';

class ServerHello {
  ProtocolVersion protocolVersion;
  TlsRandom tlsRandom;
  Uint8List sessionId;
  // Uint8List cookie;
  Uint16 cipherSuite;
  Uint8 compressionMethod;
  List<Extension> extensions;

  ServerHello(this.protocolVersion, this.tlsRandom, this.sessionId,
      this.cipherSuite, this.compressionMethod, this.extensions);

  Uint8List marshal() {
    final bb = BytesBuilder();

    bb.add(protocolVersion.marshal());
    bb.add(tlsRandom.marshal());

    bb.addByte(sessionId.length);
    // print("Session id length: $session_id_length");

    bb.add(sessionId);

    bb.add(cipherSuite.toBytes());

    bb.add(compressionMethod.toBytes());

    bb.add(encodeExtensions(extensions));

    return bb.toBytes();
  }

  factory ServerHello.unmarshal(Uint8List data, int offset, int arrayLen) {
    final reader = ByteData.sublistView(data);

    ProtocolVersion protocolVersion =
        ProtocolVersion(Uint8(data[offset]), Uint8(data[offset + 1]));
    offset += 2;
    TlsRandom tlsRandom = TlsRandom.unmarshal(data, offset, arrayLen);
    offset += 32;

    final sessionIdLength = Uint8(reader.getUint8(offset));
    offset += 1;
    // print("Session id length: $session_id_length");

    final sessionId = sessionIdLength.value > 0
        ? data.sublist(offset, offset + sessionIdLength.value)
        : Uint8List(0);
    offset += sessionId.length;

    final cipherSuiteID = Uint16(ByteData.sublistView(data, offset, offset + 2)
        .getUint16(0, Endian.big));
    offset += 2;

    final ompressionMethodID = Uint8(data[offset]);
    offset++;

    print("Compression methods: $ompressionMethodID");

    final (extensions, decodeExteensions) =
        decodeExtensions(data, offset, data.length);
    print("extensions: $extensions");
    offset = decodeExteensions;

    return ServerHello(protocolVersion, tlsRandom, sessionId, cipherSuiteID,
        ompressionMethodID, extensions);
  }
}
