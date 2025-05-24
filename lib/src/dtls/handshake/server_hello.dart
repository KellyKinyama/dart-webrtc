import 'dart:typed_data';

import '../crypto.dart';
import 'extensions/extensions.dart';

import 'extension.dart';
import 'handshake.dart';
import 'tls_random.dart';

/**
 * Section 7.4.1.2
 */
class ServerHello {
  ProtocolVersion client_version;
  TlsRandom random;
  int session_id_length;
  List<int> session_id;
  int cipher_suite;
  int compression_method;
  List<Extension> extensions;
  Uint8List? extensionsData;

  ServerHello(
      this.client_version,
      this.random,
      this.session_id_length,
      this.session_id,
      this.cipher_suite,
      this.compression_method,
      this.extensions,
      {this.extensionsData});

  ContentType getContentType() {
    return ContentType.content_handshake;
  }

  HandshakeType getHandshakeType() {
    return HandshakeType.server_hello;
  }

  Uint8List encode() {
    final bb = BytesBuilder();
    bb.add([client_version.major, client_version.minor]);

    final randomBytes = random.marshal();
    print("Random bytes length: ${randomBytes.length}");
    bb.add(randomBytes);

    bb.addByte(session_id.length);
    print("Session id length: ${session_id.length}");
    bb.add(session_id);

    bb.add([0x00, 0x00]);
    // result = append(result, []byte{0x00, 0x00}...)
    // binary.BigEndian.PutUint16(result[len(result)-2:], uint16(m.CipherSuiteID))

    bb.add(Uint8List(2)
      ..buffer.asByteData().setUint16(0, cipher_suite, Endian.big));

    bb.addByte(compression_method);
    bb.add(encodeExtensions(extensions));

    // result = append(result, m.CompressionMethodID)

    // encodedExtensions := EncodeExtensionMap(m.Extensions)
    // result = append(result, encodedExtensions...)

    return bb.toBytes();
  }

  Uint8List marshal() {
    final bb = BytesBuilder();
    // Calculate the total size of the marshaled data

    // Allocate buffer for marshaling

    // Write ProtocolVersion
    bb.add([client_version.major, client_version.minor]);

    // Write HandshakeRandom

    bb.add(random.marshal());

    // Write Session ID (assuming no session ID, length = 0)
    bb.addByte(session_id_length);
    if (session_id.isNotEmpty) bb.add(session_id);

    // Write CipherSuite
    ByteData bd = ByteData(2);
    bd.setUint16(0, cipher_suite);
    bb.add(bd.buffer.asUint8List());

    // Write CompressionMethod
    bb.addByte(compression_method);

    // Write Extensions
    // bb.add(encodeExtensionMap(extensions));
    bb.add(extensionsData!);

    // Debug prints to check buffer sizes and offsets
    // print('Total Size: $totalSize');
    // print('Offset before setting extensions: $offset');
    // print('Extensions Buffer Length: ${extensionsBuffer.length}');

    // // Ensure the range is within the buffer size
    // if (offset + extensionsBuffer.length > totalSize) {
    //   throw RangeError('Extensions buffer exceeds allocated buffer size');
    // }

    // writer.buffer
    //     .asUint8List()
    //     .setRange(offset, offset + extensionsBuffer.length, extensionsBuffer);

    return bb.toBytes();
    // Return the marshaled data as Uint8List
    // return writer.buffer.asUint8List();
  }

  static (ServerHello, int, bool?) unmarshal(
      Uint8List data, int offset, int arrayLen) {
    var reader = ByteData.sublistView(data);

    final clientVersion =
        ProtocolVersion(reader.getUint8(offset), reader.getUint8(offset + 1));
    offset += 2;
    print("Protocol version: $clientVersion");

    final random = TlsRandom.unmarshal(data, offset, data.length);
    offset += 32;

    final session_id_length = reader.getUint8(offset);
    offset += 1;
    print("Session id length: $session_id_length");

    final sessionId = session_id_length > 0
        ? data.sublist(offset, offset + session_id_length)
        : Uint8List(0);
    offset += sessionId.length;
    print("Session id: $sessionId");

    // final cookieLength = data[offset];
    // offset += 1;

    // final cookie = data.sublist(offset, offset + cookieLength);
    // offset += cookie.length;

    final cipherSuiteID =
        ByteData.sublistView(data, offset, offset + 2).getUint16(0, Endian.big);
    offset += 2;

    final ompressionMethodID = data[offset];
    offset++;

    print("Compression methods: $ompressionMethodID");

    final (extensions, decodedExtensions) =
        decodeExtensions(data, offset, data.length);
    print("extensions: $extensions");

    return (
      ServerHello(clientVersion, random, session_id_length, sessionId,
          cipherSuiteID, ompressionMethodID, extensions),
      offset,
      null
    );
  }

  // Uint8List encodeExtensionMap(Map<ExtensionType, dynamic> extensions) {
  //   // Calculate the total length of the encoded extensions
  //   int totalLength = extensions.entries.fold(0, (sum, entry) {
  //     int extensionLength = entry.value.size();
  //     return sum +
  //         4 +
  //         extensionLength; // 2 bytes for type, 2 bytes for length, and extension data
  //   });

  //   // Create a ByteData buffer to write the encoded extensions
  //   ByteData writer = ByteData(2 + totalLength);
  //   int offset = 0;

  //   // Write the total length of the extensions (2 bytes)
  //   writer.setUint16(offset, totalLength, Endian.big);
  //   offset += 2;

  //   // Iterate over the extensions and write each one
  //   extensions.forEach((extensionType, extension) {
  //     // Write ExtensionType (2 bytes)
  //     if (extension is ExtUnknown) {
  //       writer.setUint16(offset, extension.type, Endian.big);
  //     } else {
  //       writer.setUint16(offset, extensionType.value, Endian.big);
  //     }
  //     offset += 2;

  //     // Write the length of the extension data (2 bytes)
  //     int extensionLength = extension.size();
  //     writer.setUint16(offset, extensionLength, Endian.big);
  //     offset += 2;

  //     // Write the extension data
  //     ByteData extensionData = ByteData(extensionLength);
  //     //extension.marshal(extensionData);
  //     writer.buffer.asUint8List().setRange(
  //         offset, offset + extensionLength, extensionData.buffer.asUint8List());
  //     offset += extensionLength;
  //   });

  //   return writer.buffer.asUint8List();
  // }

  // Uint8List encodeExtensionMap(Map<ExtensionType, dynamic> extensions) {
  //   final bb = BytesBuilder();
  //   final extensionsToBe = extensions.entries.toList();
  //   // encodedBody := make([]byte, 0)
  //   for (final extension in extensionsToBe) {
  //     final encodedExtension = extension.encode();
  //     // bb.add(encodedExtension);

  //     bb.add(Uint8List(2)
  //       ..buffer
  //           .asByteData()
  //           .setUint16(extension.extensionType(), cipher_suite, Endian.big));
  //     // binary.BigEndian.PutUint16(encodedExtType, uint16(extension.extensionType()))
  //     // encodedBody = append(encodedBody, encodedExtType...)

  //     // encodedExtLen := make([]byte, 2)
  //     // binary.BigEndian.PutUint16(encodedExtLen, uint16(len(encodedExtension)))

  //     bb.add(Uint8List(2)
  //       ..buffer
  //           .asByteData()
  //           .setUint16(encodedExtension.length, cipher_suite, Endian.big));
  //     // encodedBody = append(encodedBody, encodedExtLen...)
  //     // encodedBody = append(encodedBody, encodedExtension...)
  //     bb.add(encodedExtension);
  //   }
  //   final extensionBytes = bb.toBytes();

  //   bb.add(Uint8List(2)
  //     ..buffer
  //         .asByteData()
  //         .setUint16(extensionBytes.length, cipher_suite, Endian.big));

  //   // binary.BigEndian.PutUint16(result[0:], uint16(len(encodedBody)))
  //   // result = append(result, encodedBody...)
  //   return bb.toBytes();
  // }
}

void main() {
  final (serverHello, _, _) =
      ServerHello.unmarshal(raw_server_hello, 0, raw_server_hello.length);
  print("Server hello: $serverHello");

  print("Got random:      ${serverHello.random.randomBytes}");
  print("Expected random: $random_bytes");

  print("Got cipher:      ${CipherSuiteId.fromInt(serverHello.cipher_suite)}");
  print(
      "Expected cipher: ${CipherSuiteId.Tls_Ecdhe_Ecdsa_With_Aes_128_Gcm_Sha256}");

  print("marshalled Server hello: ${serverHello.marshal()}");
  print("Expected:                $raw_server_hello");
}

final raw_server_hello = Uint8List.fromList([
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

final random_bytes = Uint8List.fromList([
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
