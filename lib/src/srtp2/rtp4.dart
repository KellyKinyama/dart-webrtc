import 'dart:typed_data';

// --- Constants (matching Rust) ---
const int HEADER_LENGTH = 4;
const int VERSION_SHIFT = 6;
const int VERSION_MASK = 0x3;
const int PADDING_SHIFT = 5;
const int PADDING_MASK = 0x1;
const int EXTENSION_SHIFT = 4;
const int EXTENSION_MASK = 0x1;
const int EXTENSION_PROFILE_ONE_BYTE = 0xBEDE; // Corrected value
const int EXTENSION_PROFILE_TWO_BYTE = 0x1000;
const int EXTENSION_ID_RESERVED = 0xF;
const int CC_MASK = 0xF;
const int MARKER_SHIFT = 7;
const int MARKER_MASK = 0x1;
const int PT_MASK = 0x7F;
// Offsets are not directly used with ByteData's read methods,
// but help define structure
const int SEQ_NUM_OFFSET = 2;
const int SEQ_NUM_LENGTH = 2;
const int TIMESTAMP_OFFSET = 4;
const int TIMESTAMP_LENGTH = 4;
const int SSRC_OFFSET = 8;
const int SSRC_LENGTH = 4;
const int CSRC_OFFSET = 12; // This is the offset *after* SSRC
const int CSRC_LENGTH = 4;

// Custom Error class
class RtpError implements Exception {
  final String message;
  const RtpError(this.message);

  @override
  String toString() => 'RtpError: $message';

  static const RtpError headerSizeInsufficient =
      RtpError('Header size insufficient');
  static const RtpError headerSizeInsufficientForExtension =
      RtpError('Header size insufficient for extension');
  static const RtpError malformedExtension =
      RtpError('Malformed RTP extension');
  static const RtpError shortPacket =
      RtpError('Short packet'); // Corresponds to ErrShortPacket
}

enum ExtensionProfile {
  OneByte(EXTENSION_PROFILE_ONE_BYTE), // 0xBEDE
  TwoByte(EXTENSION_PROFILE_TWO_BYTE), // 0x1000
  unknown(-1); // For profiles that don't match known ones

  const ExtensionProfile(this.value);
  final int value;

  factory ExtensionProfile.fromInt(int key) {
    return values.firstWhere((element) => element.value == key,
        orElse: () => ExtensionProfile.unknown);
  }
}

class Extension {
  int id;
  Uint8List payload;

  Extension({required this.id, required this.payload});

  @override
  String toString() {
    return 'Extension(id: $id, payload: $payload)'; // Added payload content for debugging
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Extension &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          _listEquals(payload, other.payload);

  @override
  int get hashCode => id.hashCode ^ payload.hashCode;

  static bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class Header {
  int version;
  bool padding;
  bool extension;
  bool marker;
  int payloadType;
  int sequenceNumber;
  int timestamp;
  int ssrc;
  List<int> csrc;
  ExtensionProfile extensionProfile; // Changed to ExtensionProfile enum
  List<Extension> extensions;
  int extensionsPadding;

  Header({
    required this.version,
    required this.padding,
    required this.extension,
    required this.marker,
    required this.payloadType,
    required this.sequenceNumber,
    required this.timestamp,
    required this.ssrc,
    List<int>? csrc,
    ExtensionProfile? extensionProfile,
    List<Extension>? extensions,
    this.extensionsPadding = 0,
  })  : csrc = csrc ?? [],
        extensionProfile = extensionProfile ?? ExtensionProfile.unknown,
        extensions = extensions ?? [];

  @override
  String toString() {
    return 'Header(\n'
        '  version: $version,\n'
        '  padding: $padding,\n'
        '  extension: $extension,\n'
        '  marker: $marker,\n'
        '  payloadType: $payloadType,\n'
        '  sequenceNumber: $sequenceNumber,\n'
        '  timestamp: $timestamp,\n'
        '  ssrc: $ssrc,\n'
        '  csrc: $csrc,\n'
        '  extensionProfile: $extensionProfile (${extensionProfile.value.toRadixString(16)}),\n'
        '  extensions: $extensions,\n'
        '  extensionsPadding: $extensionsPadding\n'
        ')';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Header &&
          runtimeType == other.runtimeType &&
          version == other.version &&
          padding == other.padding &&
          extension == other.extension &&
          marker == other.marker &&
          payloadType == other.payloadType &&
          sequenceNumber == other.sequenceNumber &&
          timestamp == other.timestamp &&
          ssrc == other.ssrc &&
          _listEquals(csrc, other.csrc) &&
          extensionProfile == other.extensionProfile &&
          _listEquals(extensions, other.extensions) &&
          extensionsPadding == other.extensionsPadding;

  @override
  int get hashCode =>
      version.hashCode ^
      padding.hashCode ^
      extension.hashCode ^
      marker.hashCode ^
      payloadType.hashCode ^
      sequenceNumber.hashCode ^
      timestamp.hashCode ^
      ssrc.hashCode ^
      csrc.hashCode ^
      extensionProfile.hashCode ^
      extensions.hashCode ^
      extensionsPadding.hashCode;

  static bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static (Header, int) unmarshal(Uint8List rawPacket, {int initialOffset = 0}) {
    int currentOffset = initialOffset;
    final int rawPacketLen = rawPacket.lengthInBytes;

    final ByteData reader = ByteData.view(
        rawPacket.buffer, rawPacket.offsetInBytes + initialOffset);

    final int remainingLength = rawPacketLen - initialOffset;

    if (remainingLength < HEADER_LENGTH) {
      throw RtpError.headerSizeInsufficient;
    }

    final int b0 = reader.getUint8(currentOffset - initialOffset);
    currentOffset += 1;

    final int version = (b0 >> VERSION_SHIFT) & VERSION_MASK;
    final bool padding = ((b0 >> PADDING_SHIFT) & PADDING_MASK) > 0;
    final bool extension = ((b0 >> EXTENSION_SHIFT) & EXTENSION_MASK) > 0;
    final int cc = b0 & CC_MASK;

    final int expectedMinLength = HEADER_LENGTH + (cc * CSRC_LENGTH);
    if (remainingLength < expectedMinLength) {
      throw RtpError.headerSizeInsufficient;
    }

    final int b1 = reader.getUint8(currentOffset - initialOffset);
    currentOffset += 1;

    final bool marker = ((b1 >> MARKER_SHIFT) & MARKER_MASK) > 0;
    final int payloadType = b1 & PT_MASK;

    final int sequenceNumber =
        reader.getUint16(currentOffset - initialOffset, Endian.big);
    currentOffset += 2;
    final int timestamp =
        reader.getUint32(currentOffset - initialOffset, Endian.big);
    currentOffset += 4;
    final int ssrc =
        reader.getUint32(currentOffset - initialOffset, Endian.big);
    currentOffset += 4;

    List<int> csrc = [];
    for (int i = 0; i < cc; i++) {
      csrc.add(reader.getUint32(currentOffset - initialOffset, Endian.big));
      currentOffset += 4;
    }

    int extensionsPadding = 0;
    ExtensionProfile extensionProfile = ExtensionProfile.unknown;
    List<Extension> extensions = [];

    if (extension) {
      if (remainingLength < (currentOffset - initialOffset) + 4) {
        throw RtpError.headerSizeInsufficientForExtension;
      }

      final int intExtProfile =
          reader.getUint16(currentOffset - initialOffset, Endian.big);
      extensionProfile = ExtensionProfile.fromInt(intExtProfile);
      currentOffset += 2;

      final int extensionLengthBytes =
          reader.getUint16(currentOffset - initialOffset, Endian.big) * 4;
      currentOffset += 2;

      if (remainingLength <
          (currentOffset - initialOffset) + extensionLengthBytes) {
        throw RtpError.headerSizeInsufficientForExtension;
      }

      final int extensionDataEnd = currentOffset + extensionLengthBytes;

      switch (extensionProfile) {
        case ExtensionProfile.OneByte:
          {
            while (currentOffset < extensionDataEnd) {
              final int b = reader.getUint8(currentOffset - initialOffset);
              currentOffset += 1;

              if (b == 0x00) {
                extensionsPadding += 1;
                continue;
              }

              final int extId = b >> 4;
              final int len = (b & 0x0F) + 1;

              if (extId == EXTENSION_ID_RESERVED) {
                extensionsPadding += (extensionDataEnd - currentOffset);
                currentOffset = extensionDataEnd;
                break;
              }

              if (currentOffset + len > extensionDataEnd) {
                throw RtpError.malformedExtension;
              }

              final Uint8List payload = Uint8List.view(rawPacket.buffer,
                  rawPacket.offsetInBytes + currentOffset, len);
              extensions.add(Extension(id: extId, payload: payload));
              currentOffset += len;
            }
          }
          break;

        case ExtensionProfile.TwoByte:
          {
            while (currentOffset < extensionDataEnd) {
              final int b = reader.getUint8(currentOffset - initialOffset);
              currentOffset += 1;

              if (b == 0x00) {
                extensionsPadding += 1;
                continue;
              }

              final int extId = b;
              if (currentOffset + 1 > extensionDataEnd) {
                throw RtpError.malformedExtension;
              }
              final int len = reader.getUint8(currentOffset - initialOffset);
              currentOffset += 1;

              if (currentOffset + len > extensionDataEnd) {
                throw RtpError.malformedExtension;
              }

              final Uint8List payload = Uint8List.view(rawPacket.buffer,
                  rawPacket.offsetInBytes + currentOffset, len);
              extensions.add(Extension(id: extId, payload: payload));
              currentOffset += len;
            }
          }
          break;

        default:
          final Uint8List payload = Uint8List.view(rawPacket.buffer,
              rawPacket.offsetInBytes + currentOffset, extensionLengthBytes);
          extensions.add(Extension(id: 0, payload: payload));
          currentOffset += extensionLengthBytes;
          break;
      }
    }

    final Header header = Header(
      version: version,
      padding: padding,
      extension: extension,
      marker: marker,
      payloadType: payloadType,
      sequenceNumber: sequenceNumber,
      timestamp: timestamp,
      ssrc: ssrc,
      csrc: csrc,
      extensionProfile: extensionProfile,
      extensions: extensions,
      extensionsPadding: extensionsPadding,
    );

    return (header, currentOffset - initialOffset);
  }
}

class Packet {
  Header header;
  Uint8List payload;

  Packet({
    required this.header,
    required this.payload,
  });

  factory Packet.createEmpty() {
    return Packet(
        header: Header(
          version: 0,
          padding: false,
          extension: false,
          marker: false,
          payloadType: 0,
          sequenceNumber: 0,
          timestamp: 0,
          ssrc: 0,
        ),
        payload: Uint8List(0));
  }

  @override
  String toString() {
    String out = "RTP PACKET:\n";
    out += "\tVersion: ${header.version}\n";
    out += "\tMarker: ${header.marker}\n";
    out += "\tPayload Type: ${header.payloadType}\n";
    out += "\tSequence Number: ${header.sequenceNumber}\n";
    out += "\tTimestamp: ${header.timestamp}\n";
    out += "\tSSRC: ${header.ssrc} (${header.ssrc.toRadixString(16)})\n";
    out += "\Extensions: ${header.extensions}\n";

    out += "\tPayload Length: ${payload.length}\n";
    return out;
  }

  static Packet unmarshal(Uint8List rawPacket) {
    final (header, headerLen) = Header.unmarshal(rawPacket, initialOffset: 0);

    int payloadLen = rawPacket.length - headerLen;

    Uint8List payload;
    if (payloadLen > 0) {
      payload = rawPacket.sublist(headerLen, headerLen + payloadLen);
    } else {
      payload = Uint8List(0);
    }

    if (header.padding) {
      if (payload.isNotEmpty) {
        final int paddingLen = payload[payload.length - 1];

        if (paddingLen <= payload.length) {
          return Packet(
            header: header,
            payload: payload.sublist(0, payload.length - paddingLen),
          );
        } else {
          throw RtpError.shortPacket;
        }
      } else {
        throw RtpError.shortPacket;
      }
    } else {
      return Packet(header: header, payload: payload);
    }
  }
}

// --- Main function with all test cases using assert ---
void main() {
  // Test case with a one-byte extension (from previous example)
  final Uint8List rtpPacketWithOneByteExtensionAndPayload = Uint8List.fromList([
    0x80, 0x60, 0x00,
    0x01, // V P X CC | M PT | Seq (0x80 means V=2, P=0, X=1, CC=0)
    0x00, 0x00, 0x03, 0xE8, // Timestamp (1000)
    0x00, 0x00, 0x30, 0x39, // SSRC (12345)
    0xBE, 0xDE, 0x00,
    0x01, // Extension Profile (0xBEDE), Length (1 word = 4 bytes)
    0x11, 0x22, 0x33,
    0x00, // Extension data (ID 1, L=1. Payload 0x22. Then 0x33, 0x00 padding)
    0xDE, 0xAD, 0xBE, 0xEF, 0x01 // Payload (5 bytes, example)
  ]);

  print(
      '--- Test Unmarshal Packet with One-Byte Extension and Payload (Previous) ---');
  try {
    final Packet packet =
        Packet.unmarshal(rtpPacketWithOneByteExtensionAndPayload);
    print('Successfully unmarshalled RTP Packet:');
    print(packet);

    assert(packet.header.version == 2);
    assert(packet.header.padding == false);
    assert(packet.header.extension == true);
    assert(packet.header.marker == false);
    assert(packet.header.payloadType == 96);
    assert(packet.header.sequenceNumber == 1);
    assert(packet.header.timestamp == 1000);
    assert(packet.header.ssrc == 12345);
    assert(packet.header.csrc.isEmpty);
    assert(packet.header.extensionProfile == ExtensionProfile.OneByte);
    assert(packet.header.extensions.length == 1);
    assert(packet.header.extensions[0].id == 1);
    assert(packet.header.extensions[0].payload.length == 1);
    assert(packet.header.extensions[0].payload[0] == 0x22);
    assert(packet.header.extensionsPadding == 2);
    assert(packet.payload.length == 5);
    assert(packet.payload[0] == 0xDE);
    assert(packet.payload[4] == 0x01);

    print(
        '\nAssertions passed for Packet unmarshal (one-byte extension, no padding flag)!');
  } on RtpError catch (e) {
    print('RTP Unmarshal Error: ${e.message}');
  } catch (e) {
    print('An unexpected error occurred: $e');
  }

  print('\n--- Test Unmarshal Packet with Padding Flag (Previous) ---');
  final Uint8List rtpPacketWithPadding = Uint8List.fromList([
    0xA0, 0x61, 0x00, 0x02, // Header
    0x00, 0x00, 0x07, 0xD0, // Timestamp
    0x00, 0x00, 0xD4, 0x31, // SSRC
    0xAA, 0xBB, 0xCC, 0xDD, 0x03 // Payload
  ]);

  try {
    final Packet packetWithPadding = Packet.unmarshal(rtpPacketWithPadding);
    print('Successfully unmarshalled RTP Packet with Padding:');
    print(packetWithPadding);

    assert(packetWithPadding.header.padding == true);
    assert(packetWithPadding.payload.length == 2);
    assert(packetWithPadding.payload[0] == 0xAA);
    assert(packetWithPadding.payload[1] == 0xBB);

    print('\nAssertions passed for Packet unmarshal (with padding flag)!');
  } on RtpError catch (e) {
    print('RTP Unmarshal Error: ${e.message}');
  } catch (e) {
    print('An unexpected error occurred: $e');
  }

  print('\n--- Test Unmarshal Packet with Short Padding (Previous) ---');
  final Uint8List rtpPacketShortPadding = Uint8List.fromList([
    0xA0, 0x61, 0x00, 0x02, // Header
    0x00, 0x00, 0x07, 0xD0,
    0x00, 0x00, 0xD4, 0x31,
    0xAA, 0xBB, 0xCC, 0x05 // Payload
  ]);

  try {
    Packet.unmarshal(rtpPacketShortPadding);
    print('Error: Expected ShortPacket error, but unmarshal succeeded.');
  } on RtpError catch (e) {
    if (e == RtpError.shortPacket) {
      print('Caught expected error: ${e.message}');
    } else {
      print('Caught unexpected RTP error: ${e.message}');
    }
  } catch (e) {
    print('Caught unexpected general error: $e');
  }

  print(
      '\n--- Test Unmarshal Packet with 0-length Payload and Padding Flag (Previous) ---');
  final Uint8List rtpPacketZeroLenPayloadPadding = Uint8List.fromList([
    0xA0, 0x61, 0x00, 0x02, // Header
    0x00, 0x00, 0x07, 0xD0,
    0x00, 0x00, 0xD4, 0x31,
  ]);

  try {
    Packet.unmarshal(rtpPacketZeroLenPayloadPadding);
    print('Error: Expected ShortPacket error, but unmarshal succeeded.');
  } on RtpError catch (e) {
    if (e == RtpError.shortPacket) {
      print('Caught expected error: ${e.message}');
    } else {
      print('Caught unexpected RTP error: ${e.message}');
    }
  } catch (e) {
    print('Caught unexpected general error: $e');
  }

  // --- NEW TEST CASES FROM TYPESCRIPT SNIPPET ---

  print('\n--- NEW TEST CASE: basic (TypeScript equivalent) ---');
  final Uint8List tsRawBasic = Uint8List.fromList([
    0x90,
    0xe0,
    0x69,
    0x8f,
    0xd9,
    0xc2,
    0x93,
    0xda,
    0x1c,
    0x64,
    0x27,
    0x82,
    0x00,
    0x01,
    0x00,
    0x01,
    0xff,
    0xff,
    0xff,
    0xff,
    0x98,
    0x36,
    0xbe,
    0x88,
    0x9e,
  ]);

  try {
    final Packet parsedBasic = Packet.unmarshal(tsRawBasic);
    print('Successfully unmarshalled Basic RTP Packet:');
    print(parsedBasic);

    assert(parsedBasic.header.version == 2);
    assert(parsedBasic.header.padding == false);
    assert(parsedBasic.header.extension == true);
    assert(parsedBasic.header.csrc.length == 0);
    assert(parsedBasic.header.marker == true);
    assert(parsedBasic.header.sequenceNumber == 27023);
    assert(parsedBasic.header.timestamp == 3653407706);
    assert(parsedBasic.header.ssrc == 476325762);
    assert(parsedBasic.header.extensionProfile == ExtensionProfile.unknown);
    assert(Header._listEquals(parsedBasic.header.extensions, [
      Extension(id: 0, payload: Uint8List.fromList([0xff, 0xff, 0xff, 0xff])),
    ]));
    // The total length of the raw packet minus the calculated header length should equal the payload length.
    assert(parsedBasic.payload.length == tsRawBasic.length - 20);
    assert(parsedBasic.header.payloadType == 96);

    print('\nAssertions passed for basic TypeScript test case!');
  } on RtpError catch (e) {
    print('RTP Unmarshal Error: ${e.message}');
  } catch (e) {
    print('An unexpected error occurred: $e');
  }

  print(
      '\n--- NEW TEST CASE: TestRFC8285OneByteExtension (TypeScript equivalent) ---');
  final Uint8List tsRawOneByteExtension = Uint8List.fromList([
    0x90,
    0xe0,
    0x69,
    0x8f,
    0xd9,
    0xc2,
    0x93,
    0xda,
    0x1c,
    0x64,
    0x27,
    0x82,
    0xbe,
    0xde,
    0x00,
    0x01,
    0x50,
    0xaa,
    0x00,
    0x00,
    0x98,
    0x36,
    0xbe,
    0x88,
    0x9e,
  ]);

  try {
    final Packet pOneByte = Packet.unmarshal(tsRawOneByteExtension);
    print('Successfully unmarshalled RFC8285 One Byte Extension RTP Packet:');
    print(pOneByte);

    assert(pOneByte.header.extension == true);
    assert(pOneByte.header.extensionProfile == ExtensionProfile.OneByte);
    assert(Header._listEquals(pOneByte.header.extensions, [
      Extension(id: 5, payload: Uint8List.fromList([0xaa])),
    ]));
    assert(
        pOneByte.payload.length == tsRawOneByteExtension.length - (12 + 4 + 4));

    print('\nAssertions passed for TestRFC8285OneByteExtension!');
  } on RtpError catch (e) {
    print('RTP Unmarshal Error: ${e.message}');
  } catch (e) {
    print('An unexpected error occurred: $e');
  }

  print(
      '\n--- NEW TEST CASE: TestRFC8285OneByteTwoExtensionOfTwoBytes (TypeScript equivalent) ---');
  final Uint8List tsRawTwoExtensions = Uint8List.fromList([
    0x90,
    0xe0,
    0x69,
    0x8f,
    0xd9,
    0xc2,
    0x93,
    0xda,
    0x1c,
    0x64,
    0x27,
    0x82,
    0xbe,
    0xde,
    0x00,
    0x01,
    0x10,
    0xaa,
    0x20,
    0xbb,
    0x98,
    0x36,
    0xbe,
    0x88,
    0x9e,
  ]);

  try {
    final Packet pTwoExtensions = Packet.unmarshal(tsRawTwoExtensions);
    print('Successfully unmarshalled RFC8285 Two Extensions RTP Packet:');
    print(pTwoExtensions);

    assert(pTwoExtensions.header.extensionProfile == ExtensionProfile.OneByte);
    assert(Header._listEquals(pTwoExtensions.header.extensions, [
      Extension(id: 1, payload: Uint8List.fromList([0xaa])),
      Extension(id: 2, payload: Uint8List.fromList([0xbb])),
    ]));
    assert(pTwoExtensions.payload.length ==
        tsRawTwoExtensions.length - (12 + 4 + 4));

    print('\nAssertions passed for TestRFC8285OneByteTwoExtensionOfTwoBytes!');
  } on RtpError catch (e) {
    print('RTP Unmarshal Error: ${e.message}');
  } catch (e) {
    print('An unexpected error occurred: $e');
  }

  print(
      '\nRemaining tests (dtmf, test_no_ssrc, test_padding_only_with_header_extensions, test_with_csrc)');
  print(
      'require a file loading utility in Dart (e.g., `dart:io` or Flutter assets).');
  print(
      'The `serialize_deserialize` test requires implementing the `serialize` methods first.');
}
