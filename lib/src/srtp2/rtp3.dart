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
    return 'Extension(id: $id, payloadLength: ${payload.length} bytes)';
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
    List<int>? csrc, // Make nullable to provide default in constructor
    ExtensionProfile? extensionProfile, // Make nullable
    List<Extension>? extensions, // Make nullable
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

  /// Unmarshal parses the passed byte slice and stores the result in the Header this method is called upon
  /// Returns a tuple of (Header, bytes_read_for_header).
  static (Header, int) unmarshal(Uint8List rawPacket, {int initialOffset = 0}) {
    int currentOffset = initialOffset;
    final int rawPacketLen = rawPacket.lengthInBytes;

    // Create a ByteData view for reading. This view starts from the rawPacket's
    // underlying buffer and the given initialOffset.
    final ByteData reader = ByteData.view(
        rawPacket.buffer, rawPacket.offsetInBytes + initialOffset);

    // This `remaining` is the length of the data available from `initialOffset` onwards.
    final int remainingLength = rawPacketLen - initialOffset;

    if (remainingLength < HEADER_LENGTH) {
      throw RtpError.headerSizeInsufficient;
    }

    /*
     * 0             1               2               3
     * 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
     * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
     * |V=2|P|X|  CC   |M|   PT        |       sequence number         |
     * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
     * |                           timestamp                           |
     * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
     * |            synchronization source (SSRC) identifier           |
     * +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
     * |           contributing source (CSRC) identifiers              |
     * |                               ....                            |
     * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
     */

    // Read first byte (b0)
    final int b0 = reader.getUint8(
        currentOffset - initialOffset); // offset relative to reader's view
    currentOffset += 1;

    final int version = (b0 >> VERSION_SHIFT) & VERSION_MASK;
    final bool padding = ((b0 >> PADDING_SHIFT) & PADDING_MASK) > 0;
    final bool extension = ((b0 >> EXTENSION_SHIFT) & EXTENSION_MASK) > 0;
    final int cc = b0 & CC_MASK;

    // Check if enough bytes are available for fixed header + all CSRC entries
    final int expectedMinLength = HEADER_LENGTH + (cc * CSRC_LENGTH);
    if (remainingLength < expectedMinLength) {
      throw RtpError.headerSizeInsufficient;
    }

    // Read second byte (b1)
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
      // Corrected: Each CSRC is 4 bytes
      csrc.add(reader.getUint32(currentOffset - initialOffset, Endian.big));
      currentOffset += 4;
    }

    int extensionsPadding = 0;
    ExtensionProfile extensionProfile =
        ExtensionProfile.unknown; // Default value
    List<Extension> extensions = [];

    if (extension) {
      // Need 4 bytes for extension header (profile and length)
      if (remainingLength < (currentOffset - initialOffset) + 4) {
        throw RtpError.headerSizeInsufficientForExtension;
      }

      final int intExtProfile =
          reader.getUint16(currentOffset - initialOffset, Endian.big);
      extensionProfile = ExtensionProfile.fromInt(intExtProfile);
      currentOffset += 2;

      // Extension length is in 32-bit words, so multiply by 4 for bytes
      final int extensionLengthBytes =
          reader.getUint16(currentOffset - initialOffset, Endian.big) * 4;
      currentOffset += 2;

      // Check if enough bytes are available for the declared extension data
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
              currentOffset += 1; // Consume the ID/length byte

              if (b == 0x00) {
                // Padding byte
                extensionsPadding += 1;
                continue;
              }

              final int extId = b >> 4;
              // Length is (L+1) bytes, where L is the lower 4 bits
              final int len = (b & 0x0F) + 1; // 0xFF ^ 0xF0 is 0x0F

              if (extId == EXTENSION_ID_RESERVED) {
                // This means the rest of the extension data in this block is padding.
                extensionsPadding += (extensionDataEnd -
                    currentOffset); // Count remaining as padding
                currentOffset =
                    extensionDataEnd; // Move offset to the end of the declared extension block
                break; // Stop parsing extensions for this block
              }

              if (currentOffset + len > extensionDataEnd) {
                // Malformed extension: declared payload length exceeds remaining extension data
                throw RtpError.malformedExtension;
              }

              // Create a view of the payload directly from the rawPacket's buffer
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
              currentOffset += 1; // Consume the ID byte

              if (b == 0x00) {
                // Padding byte
                extensionsPadding += 1;
                continue;
              }

              final int extId =
                  b; // ID is the full byte for two-byte extensions
              // Need to read the length byte
              if (currentOffset + 1 > extensionDataEnd) {
                // Check if length byte exists
                throw RtpError.malformedExtension;
              }
              final int len = reader.getUint8(currentOffset - initialOffset);
              currentOffset += 1; // Consume the length byte

              if (currentOffset + len > extensionDataEnd) {
                // Malformed extension: declared payload length exceeds remaining extension data
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
          // RFC3550 Extension - Unknown profile, treat entire extension data as one blob
          // The Rust code essentially puts the entire remaining extension_length into one payload
          final Uint8List payload = Uint8List.view(rawPacket.buffer,
              rawPacket.offsetInBytes + currentOffset, extensionLengthBytes);
          extensions.add(Extension(
              id: 0, payload: payload)); // ID 0 is often used for generic
          currentOffset +=
              extensionLengthBytes; // Advance by the entire block length
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

    return (
      header,
      currentOffset - initialOffset
    ); // Return the header and bytes read for it
  }
}

/// Represents an RTP Packet
/// NOTE: raw is not directly stored in Dart, as Uint8List views handle this.
class Packet {
  Header header;
  Uint8List payload;

  Packet({
    required this.header,
    required this.payload,
  });

  // Default constructor for convenience, similar to Rust's Default trait
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
    out += "\tPayload Length: ${payload.length}\n";
    return out;
  }

  /// Unmarshal parses the passed byte slice and stores the result in the Packet this method is called upon
  /// Returns the unmarshalled Packet or throws an RtpError.
  static Packet unmarshal(Uint8List rawPacket) {
    // Rust's `Header::unmarshal(raw_packet)?` means:
    // 1. Call Header::unmarshal, passing the *same* mutable buffer.
    // 2. Header::unmarshal will read its portion and advance the buffer's internal cursor.
    // 3. If Header::unmarshal returns an error, propagate it.
    //
    // In Dart, we replicate this by explicitly managing the offset.

    // Start unmarshalling the header from the beginning of the rawPacket (offset 0).
    final (header, headerLen) = Header.unmarshal(rawPacket, initialOffset: 0);

    // After unmarshalling the header, the 'remaining' part of the rawPacket is the payload.
    // Rust's `raw_packet.remaining()` is equivalent to `rawPacket.length - headerLen`.
    int payloadLen = rawPacket.length - headerLen;

    // Rust's `raw_packet.copy_to_bytes(payload_len)` copies the remaining bytes.
    // In Dart, we can get a sublist (copy) or a view (no copy) of the remaining bytes.
    // For payload, a copy is often safer if the original buffer might be reused/modified.
    // If performance is critical and payload won't be mutated, use Uint8List.view.
    Uint8List payload;
    if (payloadLen > 0) {
      payload = rawPacket.sublist(headerLen, headerLen + payloadLen);
    } else {
      payload = Uint8List(0); // Empty payload if nothing remains
    }

    if (header.padding) {
      if (payload.isNotEmpty) {
        // Use isNotEmpty instead of payloadLen > 0 for Dart lists
        // Rust: let padding_len = payload[payload_len - 1] as usize;
        // In Dart, payloadLen - 1 is the last byte index.
        final int paddingLen = payload[payload.length - 1];

        if (paddingLen <= payload.length) {
          return Packet(
            header: header,
            // Rust: payload.slice(..payload_len - padding_len)
            // Dart: Creates a sublist from the start up to (but not including) the padding bytes.
            payload: payload.sublist(0, payload.length - paddingLen),
          );
        } else {
          // This happens if the last byte indicates a padding length
          // that is larger than the actual remaining payload.
          throw RtpError.shortPacket;
        }
      } else {
        // Payload length is 0 but padding flag is set, which is an error for padding.
        throw RtpError.shortPacket;
      }
    } else {
      // No padding, so the entire remaining part is the actual payload.
      return Packet(header: header, payload: payload);
    }
  }
}

// --- Example Usage (similar to main in previous response) ---
void main() {
  // Test case with a one-byte extension (from previous example)
  // V=2, P=0, X=1, CC=0, M=1, PT=96, Seq=1, TS=1000, SSRC=12345
  // Extension: 0xBEDE (one-byte profile), length 1 (1*4=4 bytes)
  // Extension data: 0x11 (ID 1, L=1), 0x22 (payload). Then 0x33, 0x00 (padding to align to 4-byte words)
  // Total Header Length: 12 (fixed) + 4 (ext header) + 4 (ext data) = 20 bytes
  // Add some dummy payload data after the header.
  final Uint8List rtpPacketWithOneByteExtensionAndPayload = Uint8List.fromList([
    // Header (20 bytes total)
    0x80, 0x60, 0x00,
    0x01, // V P X CC | M PT | Seq (0x80 means V=2, P=0, X=1, CC=0)
    0x00, 0x00, 0x03, 0xE8, // Timestamp (1000)
    0x00, 0x00, 0x30, 0x39, // SSRC (12345)
    0xBE, 0xDE, 0x00,
    0x01, // Extension Profile (0xBEDE), Length (1 word = 4 bytes)
    0x11, 0x22, 0x33,
    0x00, // Extension data (ID 1, L=1. Payload 0x22. Then 0x33, 0x00 padding)
    // Payload (5 bytes, example)
    0xDE, 0xAD, 0xBE, 0xEF, 0x01
  ]);

  print('--- Test Unmarshal Packet with One-Byte Extension and Payload ---');
  try {
    final Packet packet =
        Packet.unmarshal(rtpPacketWithOneByteExtensionAndPayload);
    print('Successfully unmarshalled RTP Packet:');
    print(packet);

    // Verify header details (inherited from previous tests)
    assert(packet.header.version == 2);
    assert(packet.header.padding == false); // Check padding flag for header
    assert(packet.header.extension == true);
    assert(packet.header.marker == false); // Marker is 0 in 0x60
    assert(packet.header.payloadType == 96); // PT is 0x60 (96 decimal)
    assert(packet.header.sequenceNumber == 1);
    assert(packet.header.timestamp == 1000);
    assert(packet.header.ssrc == 12345);
    assert(packet.header.csrc.isEmpty);
    assert(packet.header.extensionProfile == ExtensionProfile.OneByte);
    assert(packet.header.extensions.length == 1);
    assert(packet.header.extensions[0].id == 1); // ID from 0x11
    assert(packet.header.extensions[0].payload.length ==
        1); // Length from 0x11 (L+1)
    assert(packet.header.extensions[0].payload[0] == 0x22);
    assert(packet.header.extensionsPadding ==
        2); // 0x33, 0x00 are padding in ext data

    // Verify payload
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

  print('\n--- Test Unmarshal Packet with Two-Byte Extension ---');
  final Uint8List rtpPacketWithTwoByteExtension = Uint8List.fromList([
    0x80, 0x60, 0x00, 0x01, // V P X CC | M PT | Seq
    0x00, 0x00, 0x03, 0xE8, // Timestamp
    0x00, 0x00, 0x30, 0x39, // SSRC
    0x10, 0x00, 0x00,
    0x01, // Extension Profile (0x1000), Length (1 word = 4 bytes)
    0x01, 0x02, 0xAA, 0xBB, // Ext data (ID 1, Len 2. Payload 0xAA, 0xBB)
    0x11, 0x22, 0x33 // Some payload data
  ]);

  try {
    final (header, headerLen) = Header.unmarshal(rtpPacketWithTwoByteExtension);
    print('Successfully unmarshalled RTP Header:');
    print(header);
    print('Header Length: $headerLen bytes');

    assert(header.extensionProfile == ExtensionProfile.TwoByte);
    assert(header.extensions.length == 1);
    assert(header.extensions[0].id == 1);
    assert(header.extensions[0].payload.length == 2);
    assert(header.extensions[0].payload[0] == 0xAA);
    assert(header.extensions[0].payload[1] == 0xBB);
    assert(header.extensionsPadding == 0);
    assert(headerLen == 16);

    print('\nAssertions passed for two-byte extension example!');
  } on RtpError catch (e) {
    print('RTP Unmarshal Error: ${e.message}');
  } catch (e) {
    print('An unexpected error occurred: $e');
  }

  print('\n--- Test Unmarshal Packet with Padding Flag ---');
  // Example packet with padding flag set.
  // The last byte of the payload indicates padding length.
  // Total packet length: 12 (fixed header) + 5 (payload) = 17 bytes
  // Padding length is 3 (last byte of payload).
  // Actual payload will be 5 - 3 = 2 bytes.
  final Uint8List rtpPacketWithPadding = Uint8List.fromList([
    // Header (12 bytes) - V=2, P=1, X=0, CC=0, M=0, PT=97, Seq=2, TS=2000, SSRC=54321
    0xA0, 0x61, 0x00, 0x02, // V=2, P=1, X=0, CC=0 | M=0, PT=97 | Seq=2
    0x00, 0x00, 0x07, 0xD0, // Timestamp (2000)
    0x00, 0x00, 0xD4, 0x31, // SSRC (54321)
    // Payload (5 bytes) - 2 bytes actual data, 3 bytes padding (last byte indicates 3)
    0xAA, 0xBB, 0xCC, 0xDD,
    0x03 // Actual payload: 0xAA, 0xBB. Padding: 0xCC, 0xDD, 0x03
  ]);

  try {
    final Packet packetWithPadding = Packet.unmarshal(rtpPacketWithPadding);
    print('Successfully unmarshalled RTP Packet with Padding:');
    print(packetWithPadding);

    assert(packetWithPadding.header.padding == true);
    assert(packetWithPadding.payload.length ==
        2); // Expected actual payload length
    assert(packetWithPadding.payload[0] == 0xAA);
    assert(packetWithPadding.payload[1] == 0xBB);

    print('\nAssertions passed for Packet unmarshal (with padding flag)!');
  } on RtpError catch (e) {
    print('RTP Unmarshal Error: ${e.message}');
  } catch (e) {
    print('An unexpected error occurred: $e');
  }

  print('\n--- Test Unmarshal Packet with Short Padding ---');
  // Padding length (5) > payload length (4)
  final Uint8List rtpPacketShortPadding = Uint8List.fromList([
    0xA0, 0x61, 0x00, 0x02, // Header
    0x00, 0x00, 0x07, 0xD0,
    0x00, 0x00, 0xD4, 0x31,
    0xAA, 0xBB, 0xCC,
    0x05 // Payload: 0xAA, 0xBB, 0xCC. Padding length indicates 5, but only 4 bytes total
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
      '\n--- Test Unmarshal Packet with 0-length Payload and Padding Flag ---');
  final Uint8List rtpPacketZeroLenPayloadPadding = Uint8List.fromList([
    0xA0, 0x61, 0x00, 0x02, // Header
    0x00, 0x00, 0x07, 0xD0,
    0x00, 0x00, 0xD4, 0x31,
    // No payload bytes follow, but padding flag is set. This is an error.
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
}
