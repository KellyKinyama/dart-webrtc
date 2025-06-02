import 'dart:typed_data';

import '../../dtls3/extensions.dart';
// import 'extensions/extensions.dart';

import '../crypto.dart';
// import 'extension.dart';
import 'handshake.dart';
import 'tls_random.dart';

/**
 * Section 7.4.1.2
 */
class ClientHello {
  ProtocolVersion client_version;
  TlsRandom random;
  int session_id_length;
  List<int> session_id;
  Uint8List cookie;
  int cipher_suites_length;
  List<CipherSuiteId> cipher_suites;
  int compression_methods_length;
  List<int> compression_methods;
  Map<ExtensionTypeValue, Extension> extensions;
  Uint8List? extensionsData;

  ClientHello(
      this.client_version,
      this.random,
      this.session_id_length,
      this.session_id,
      this.cookie,
      this.cipher_suites_length,
      this.cipher_suites,
      this.compression_methods_length,
      this.compression_methods,
      this.extensions,
      {this.extensionsData});

  static (ClientHello, int, bool?) unmarshal(
      Uint8List data, int offset, int arrayLen) {
    print("Client hello data: ${data.sublist(offset, arrayLen)}");
    var reader = ByteData.sublistView(data);

    final client_version =
        ProtocolVersion(reader.getUint8(offset), reader.getUint8(offset + 1));
    offset += 2;
    // print("Protocol version: $client_version");

    final random = TlsRandom.fromBytes(data, offset);
    offset += 32;

    final session_id_length = reader.getUint8(offset);
    offset += 1;
    // print("Session id length: $session_id_length");

    final session_id = session_id_length > 0
        ? data.sublist(offset, offset + session_id_length)
        : Uint8List(0);
    offset += session_id.length;
    // print("Session id: $session_id");

    final cookieLength = data[offset];
    offset += 1;

    final cookie = data.sublist(offset, offset + cookieLength);
    offset += cookie.length;

    var (cipherSuiteIds, decodedOffset, _) =
        decodeCipherSuiteIDs(data, offset, data.length);

    // print(
    // "Offset: $offset, decordedOffest:$decodedOffset, arrayLen: ${data.length}");

    offset = decodedOffset;

    // print("Cipher suite IDs: $cipherSuiteIds");

    var (compression_methods, dof, _) =
        decodeCompressionMethodIDs(data, offset, data.length);
    offset = dof;

    // print("Compression methods: $compression_methods");
    final extensionsData = data.sublist(offset);

    final (extensions, decodedExtensions) =
        decodeExtensionMap(data, offset, data.length);

    offset = decodedExtensions;
    print("extensions: $extensions");

    return (
      ClientHello(
          client_version,
          random,
          session_id_length,
          session_id,
          cookie,
          cipherSuiteIds.length,
          cipherSuiteIds,
          compression_methods.length,
          compression_methods,
          extensions,
          extensionsData: extensionsData),
      offset,
      null
    );
  }

  static (List<CipherSuiteId>, int, bool?) decodeCipherSuiteIDs(
      Uint8List buf, int offset, int arrayLen) {
    final length =
        ByteData.sublistView(buf, offset, offset + 2).getUint16(0, Endian.big);
    final count = length / 2;
    offset += 2;

    // print("Cipher suite length: $length");

    List<CipherSuiteId> result =
        List.filled(count.toInt(), CipherSuiteId.Unsupported);
    for (int i = 0; i < count.toInt(); i++) {
      result[i] = CipherSuiteId.fromInt(
          ByteData.sublistView(buf, offset, offset + 2)
              .getUint16(0, Endian.big));
      offset += 2;
      // print("cipher suite: ${result[i]}");
    }

    // print("Cipher suites: $result");
    return (result, offset, null);
  }

  static (List<int>, int, bool?) decodeCompressionMethodIDs(
      Uint8List buf, int offset, int arrayLen) {
    final count = buf[offset];
    offset += 1;
    List<int> result = List.filled(count.toInt(), 0);
    for (int i = 0; i < count; i++) {
      result[i] = ByteData.sublistView(buf, offset, offset + 2).getUint8(0);
      offset += 1;
    }

    return (result, offset, null);
  }

  String cipherSuitesToString(List<int> cipherSuites) {
    return cipherSuites.map((e) => e.toString()).join(", ");
  }

  @override
  String toString() {
    // TODO: implement toString
    return "ClientHello(client_version: $client_version, random: $random, session_id_length: $session_id_length, session_id: $session_id, cipher_suites_length: $cipher_suites_length, cipher_suites: ${cipher_suites}, compression_methods_length: $compression_methods_length, compression_methods: $compression_methods, extensions: $extensions)";
  }
}

void main() {
  ClientHello.unmarshal(chromeClientHelloData, 0, chromeClientHelloData.length);
}

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
