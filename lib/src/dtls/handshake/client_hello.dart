import 'dart:typed_data';

import 'extensions/extensions.dart';

import '../crypto.dart';
import 'extension.dart';
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
  List<Extension> extensions;
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
        decodeExtensions(data, offset, data.length);

    offset = decodedExtensions;
    // print("extensions: $extensions");

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
  ClientHello.unmarshal(raw_client_hello, 0, raw_client_hello.length);
}

final raw_client_hello = Uint8List.fromList([
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
