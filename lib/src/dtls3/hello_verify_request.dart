import 'dart:typed_data';
import 'dtls.dart'; // Assuming DtlsVersion, ContentType, HandshakeType are here
import 'handshake_header.dart'; // For HandshakeType

/// Represents a DTLS HelloVerifyRequest message.
/// Corresponds to Go's `HelloVerifyRequest` struct.
class HelloVerifyRequest {
  ProtocolVersion version;
  Uint8List cookie;

  HelloVerifyRequest({
    required this.version,
    required this.cookie,
  });

  /// Returns the ContentType for this message.
  /// Corresponds to Go's `GetContentType` method.
  ContentType getContentType() {
    return ContentType.handshake;
  }

  /// Returns the HandshakeType for this message.
  /// Corresponds to Go's `GetHandshakeType` method.
  HandshakeType getHandshakeType() {
    return HandshakeType.helloVerifyRequest;
  }

  /// Decodes a HelloVerifyRequest from a byte array.
  /// Corresponds to Go's `Decode` method.
  static (HelloVerifyRequest, int, dynamic) decode(
      Uint8List buf, int offset, int arrayLen) {
    // if (offset + 3 > arrayLen) {
    //   // return (
    //   //   HelloVerifyRequest(
    //   //     version: ProtocolVersion.Unsupported,
    //   //     cookie: Uint8List(0),
    //   //   ),
    //   //   offset,
    //   //   'Incomplete HelloVerifyRequest'
    //   // );
    //   throw Exception('Incomplete HelloVerifyRequest');
    // }

    final reader = ByteData.sublistView(buf);
    final major = reader.getUint8(offset);
    offset++;
    final minor = reader.getUint8(offset);
    offset++;
    final version = ProtocolVersion(major, minor);
    // DtlsVersion.fromInt(reader.getUint16(0, Endian.big));
    // offset += 2;

    final cookieLength = reader.getUint8(offset);
    offset++;

    if (offset + cookieLength > arrayLen) {
      // return (
      //   HelloVerifyRequest(
      //     version: DtlsVersion.Unsupported,
      //     cookie: Uint8List(0),
      //   ),
      //   offset,
      //   'Incomplete HelloVerifyRequest cookie'
      // );
      throw Exception('Incomplete HelloVerifyRequest cookie');
    }
    final cookie =
        Uint8List.fromList(buf.sublist(offset, offset + cookieLength));
    offset += cookieLength;

    return (
      HelloVerifyRequest(
        version: version,
        cookie: cookie,
      ),
      offset,
      null
    );
  }

  /// Encodes the HelloVerifyRequest into a byte array.
  /// Corresponds to Go's `Encode` method.
  Uint8List encode() {
    final builder = BytesBuilder();
    builder.add([version.major, version.minor]);

    builder.addByte(cookie.length);
    builder.add(cookie);
    return builder.toBytes();
  }

  @override
  String toString() {
    final cookieStr = cookie.isEmpty
        ? '<nil>'
        : '0x${cookie.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}';
    return 'HelloVerifyRequest(version: ${version.toString().split('.').last}, cookie: $cookieStr)';
  }
}
