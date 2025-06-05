// server_hello.dart (Converted from serverhello.go)

import 'dart:typed_data';
import 'dtls.dart'; // For common DTLS types
import 'extensions.dart';
import 'handshake_header.dart'; // For Extension and extension map functions

class ServerHello {
  ProtocolVersion version;
  DtlsRandom random;
  List<int> sessionId;
  CipherSuiteId cipherSuiteID;
  int compressionMethodID;
  Map<ExtensionTypeValue, Extension> extensions;

  ServerHello({
    required this.version,
    required this.random,
    required this.sessionId,
    required this.cipherSuiteID,
    required this.compressionMethodID,
    required this.extensions,
  });

  ContentType getContentType() {
    return ContentType.handshake;
  }

  HandshakeType getHandshakeType() {
    return HandshakeType.serverHello;
  }

  static (ServerHello, int, dynamic) unmarshal(
      Uint8List data, int offset, int arrayLen) {
    var reader = ByteData.sublistView(data);

    final version =
        ProtocolVersion(reader.getUint8(offset), reader.getUint8(offset + 1));
    offset += 2;

    final decodedRandom = DtlsRandom.decode(data, offset);
    offset = decodedRandom.$2;
    final random = decodedRandom.$1;

    final sessionIdLength = reader.getUint8(offset);
    offset++;
    final sessionId = data.sublist(offset, offset + sessionIdLength).toList();
    offset += sessionIdLength;

    final cipherSuiteID = CipherSuiteId.fromInt(reader.getUint16(offset));
    offset += 2;

    final compressionMethodID = reader.getUint8(offset);
    offset++;

    final (extensionsMap, newOffsetExts) =
        decodeExtensionMap(data, offset, arrayLen);
    offset = newOffsetExts;

    return (
      ServerHello(
        version: version,
        random: random,
        sessionId: sessionId,
        cipherSuiteID: cipherSuiteID,
        compressionMethodID: compressionMethodID,
        extensions: extensionsMap,
      ),
      offset,
      null
    );
  }

  Uint8List encode() {
    BytesBuilder result = BytesBuilder();

    result.add([version.major, version.minor]);
    result.add(random.encode());
    result.addByte(sessionId.length);
    result.add(Uint8List.fromList(sessionId));

    result.add(
        (ByteData(2)..setUint16(0, cipherSuiteID.value)).buffer.asUint8List());
    result.addByte(compressionMethodID);
    result.add(encodeExtensionMap(extensions));

    return result.toBytes();
  }

  @override
  String toString() {
    final extensionsStr = extensions.values
        .map((ext) => ext.toString())
        .join('\n')
        .split('\n')
        .map((line) => '  $line')
        .join('\n');
    String sessionIdStr = sessionId.isEmpty
        ? "<nil>"
        : sessionId.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');

//     return """ServerHello(
//   version: $version,
//   random: $random,
//   session_id: $sessionIdStr,
//   cipher_suite_id: 0x${cipherSuiteID.value.toRadixString(16).padLeft(4, '0')},
//   compression_method_id: $compressionMethodID,
//   extensions:
// $extensionsStr
// )""";

    return """ServerHello(
  version: $version,
  random: $random,
  session_id: $sessionIdStr,
  cipher_suite_id: $cipherSuiteID,
  compression_method_id: $compressionMethodID,
  extensions:
$extensionsStr
)""";
  }
}

void main() {
  final (serverHello, _, _) =
      ServerHello.unmarshal(rawServerHello, 0, rawServerHello.length);
  print("Server hello unmarshalled successfully: $serverHello}");
  print("Marshalled: ${serverHello.encode()}");
  print("Expected:   $rawServerHello");
  print("");
  print("Random bytes: ${serverHello.random.bytes}");
  print("Expected:     $randomBytes");
}

final randomBytes = Uint8List.fromList([
  0x81,
  0x0e,
  0x98,
  0x6c,
  0x85,
  0x3d,
  0xa4,
  0x39,
  0xaf,
  0x5f,
  0xd6,
  0x5c,
  0xcc,
  0x20,
  0x7f,
  0x7c,
  0x78,
  0xf1,
  0x5f,
  0x7e,
  0x1c,
  0xb7,
  0xa1,
  0x1e,
  0xcf,
  0x63,
  0x84,
  0x28,
]);

final rawServerHello = Uint8List.fromList([
  0xfe,
  0xfd,
  0x21,
  0x63,
  0x32,
  0x21,
  0x81,
  0x0e,
  0x98,
  0x6c,
  0x85,
  0x3d,
  0xa4,
  0x39,
  0xaf,
  0x5f,
  0xd6,
  0x5c,
  0xcc,
  0x20,
  0x7f,
  0x7c,
  0x78,
  0xf1,
  0x5f,
  0x7e,
  0x1c,
  0xb7,
  0xa1,
  0x1e,
  0xcf,
  0x63,
  0x84,
  0x28,
  0x00,
  0xc0,
  0x2b,
  0x00,
  0x00,
  0x00,
]);
