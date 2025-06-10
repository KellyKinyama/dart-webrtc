// client_hello.dart (Converted from clienthello.go)

import 'dart:typed_data';
import 'dtls.dart'; // For common DTLS types
import 'extensions.dart';
import 'handshake_header.dart';
import 'hex.dart';
import 'simple_extensions.dart'; // For Extension and extension map functions

class ClientHello {
  ProtocolVersion clientVersion;
  DtlsRandom random;
  int sessionIdLength; // Redundant if using sessionId.length
  List<int> sessionId;
  Uint8List cookie;
  int cipherSuitesLength; // Redundant if using cipherSuites.length * 2
  List<CipherSuiteId> cipherSuites;
  int compressionMethodsLength; // Redundant if using compressionMethods.length
  List<int> compressionMethods;
  Map<ExtensionTypeValue, Extension> extensions;

  ClientHello({
    required this.clientVersion,
    required this.random,
    required this.sessionIdLength,
    required this.sessionId,
    required this.cookie,
    required this.cipherSuitesLength,
    required this.cipherSuites,
    required this.compressionMethodsLength,
    required this.compressionMethods,
    required this.extensions,
  });

  ContentType getContentType() {
    return ContentType.handshake;
  }

  HandshakeType getHandshakeType() {
    return HandshakeType.clientHello;
  }

  static (ClientHello, int) unmarshal(
      Uint8List data, int offset, int arrayLen) {
    var reader = ByteData.sublistView(data);

    final clientVersion =
        ProtocolVersion(reader.getUint8(offset), reader.getUint8(offset + 1));
    offset += 2;

    final decodedRandom = DtlsRandom.decode(data, offset);
    offset = decodedRandom.$2;
    final random = decodedRandom.$1;

    final sessionIdLength = reader.getUint8(offset);
    offset++;
    final sessionId = data.sublist(offset, offset + sessionIdLength).toList();
    offset += sessionIdLength;

    final cookieLength = reader.getUint8(offset);
    offset++;
    final cookie = data.sublist(offset, offset + cookieLength);
    offset += cookieLength;

    final (cipherSuiteIDs, newOffsetCs, errCs) =
        _decodeCipherSuiteIDs(data, offset, arrayLen);
    // if (errCs != null) { /* Handle error */ }
    offset = newOffsetCs;

    final (compressionMethodIDs, newOffsetCm, errCm) =
        _decodeCompressionMethodIDs(data, offset, arrayLen);
    // if (errCm != null) { /* Handle error */ }
    offset = newOffsetCm;

    final (exts, newOffsetExts) = decodeExtensionMap(data, offset, arrayLen);
    offset = newOffsetExts;

    return (
      ClientHello(
        clientVersion: clientVersion,
        random: random,
        sessionIdLength: sessionIdLength,
        sessionId: sessionId,
        cookie: cookie,
        cipherSuitesLength: cipherSuiteIDs.length * 2,
        cipherSuites: cipherSuiteIDs,
        compressionMethodsLength: compressionMethodIDs.length,
        compressionMethods: compressionMethodIDs,
        extensions: exts,
      ),
      offset
    );
  }

  Uint8List encode() {
    BytesBuilder result = BytesBuilder();

    result.add([clientVersion.major, clientVersion.minor]);
    result.add(random.encode());
    result.addByte(sessionId.length);
    result.add(Uint8List.fromList(sessionId));
    result.addByte(cookie.length);
    result.add(cookie);

    result.add((ByteData(2)..setUint16(0, cipherSuites.length * 2))
        .buffer
        .asUint8List());
    for (var cs in cipherSuites) {
      result.add((ByteData(2)..setUint16(0, cs.value)).buffer.asUint8List());
    }

    result.addByte(compressionMethods.length);
    result.add(Uint8List.fromList(compressionMethods));

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
    final cipherSuiteIDsStr =
        cipherSuites.map((cs) => cs.toString()).join(', ');
    String cookieStr = cookie.isEmpty
        ? "<nil>"
        : "0x${cookie.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}";

    return """ClientHello(
  client_version: $clientVersion,
  random: $random,
  session_id_length: $sessionIdLength,
  session_id: $sessionId,
  cookie: $cookieStr,
  cipher_suites_length: ${cipherSuites.length * 2},
  cipher_suites: $cipherSuiteIDsStr,
  compression_methods_length: ${compressionMethods.length},
  compression_methods: $compressionMethods,
  extensions:
$extensionsStr
)""";
  }
}

// Helper functions (converted from Go)
(List<CipherSuiteId>, int, dynamic) _decodeCipherSuiteIDs(
    Uint8List buf, int offset, int arrayLen) {
  var reader = ByteData.sublistView(buf);
  final length = reader.getUint16(offset);
  final count = length ~/ 2;
  offset += 2;
  List<CipherSuiteId> result =
      List.filled(count, CipherSuiteId.TLS_NULL_WITH_NULL_NULL);

  for (int i = 0; i < count; i++) {
    result[i] = CipherSuiteId.fromInt(reader.getUint16(offset));
    offset += 2;
  }
  return (result, offset, null);
}

(List<int>, int, dynamic) _decodeCompressionMethodIDs(
    Uint8List buf, int offset, int arrayLen) {
  var reader = ByteData.sublistView(buf);
  final count = reader.getUint8(offset);
  offset += 1;
  List<int> result = List.filled(count, 0);

  for (int i = 0; i < count; i++) {
    result[i] = reader.getUint8(offset);
    offset += 1;
  }
  return (result, offset, null);
}

void main() {
  final clientHello = ClientHello.unmarshal(
      chromeClientHelloData, 0, chromeClientHelloData.length);
  print("Client hello unmarshalled successfully: $clientHello}");
}

final rawClientHello = Uint8List.fromList([
  0xfe,
  0xfd,
  0xb6,
  0x2f,
  0xce,
  0x5c,
  0x42,
  0x54,
  0xff,
  0x86,
  0xe1,
  0x24,
  0x41,
  0x91,
  0x42,
  0x62,
  0x15,
  0xad,
  0x16,
  0xc9,
  0x15,
  0x8d,
  0x95,
  0x71,
  0x8a,
  0xbb,
  0x22,
  0xd7,
  0x47,
  0xec,
  0xd8,
  0x3d,
  0xdc,
  0x4b,
  0x00,
  0x14,
  0xe6,
  0x14,
  0x3a,
  0x1b,
  0x04,
  0xea,
  0x9e,
  0x7a,
  0x14,
  0xd6,
  0x6c,
  0x57,
  0xd0,
  0x0e,
  0x32,
  0x85,
  0x76,
  0x18,
  0xde,
  0xd8,
  0x00,
  0x04,
  0xc0,
  0x2b,
  0xc0,
  0x0a,
  0x01,
  0x00,
  0x00,
  0x08,
  0x00,
  0x0a,
  0x00,
  0x04,
  0x00,
  0x02,
  0x00,
  0x1d,
]);

final chromeClientHelloData = Uint8List.fromList([
  254,
  253,
  200,
  200,
  80,
  239,
  109,
  109,
  63,
  18,
  9,
  71,
  197,
  116,
  105,
  89,
  165,
  13,
  20,
  80,
  81,
  47,
  87,
  208,
  101,
  165,
  24,
  216,
  10,
  145,
  107,
  13,
  37,
  110,
  0,
  20,
  93,
  172,
  194,
  139,
  142,
  51,
  43,
  177,
  46,
  86,
  251,
  2,
  191,
  116,
  55,
  29,
  214,
  95,
  26,
  106,
  0,
  22,
  192,
  43,
  192,
  47,
  204,
  169,
  204,
  168,
  192,
  9,
  192,
  19,
  192,
  10,
  192,
  20,
  0,
  156,
  0,
  47,
  0,
  53,
  1,
  0,
  0,
  64,
  0,
  13,
  0,
  20,
  0,
  18,
  4,
  3,
  8,
  4,
  4,
  1,
  5,
  3,
  8,
  5,
  5,
  1,
  8,
  6,
  6,
  1,
  2,
  1,
  0,
  11,
  0,
  2,
  1,
  0,
  255,
  1,
  0,
  1,
  0,
  0,
  10,
  0,
  8,
  0,
  6,
  0,
  29,
  0,
  23,
  0,
  24,
  0,
  14,
  0,
  9,
  0,
  6,
  0,
  1,
  0,
  8,
  0,
  7,
  0,
  0,
  23,
  0,
  0
]);
