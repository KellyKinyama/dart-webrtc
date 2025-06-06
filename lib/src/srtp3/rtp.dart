// lib/rtp.dart
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
const int SEQ_NUM_OFFSET = 2;
const int SEQ_NUM_LENGTH = 2;
const int TIMESTAMP_OFFSET = 4;
const int TIMESTAMP_LENGTH = 4;
const int SSRC_OFFSET = 8;
const int SSRC_LENGTH = 4;
const int CSRC_OFFSET = 12;
const int CSRC_LENGTH = 4;

// Custom Error class
class RtpError implements Exception {
  final String message;
  const RtpError(this.message);

  @override
  String toString() => 'RtpError: $message';

  static const RtpError headerSizeInsufficient = RtpError('Header size insufficient');
  static const RtpError headerSizeInsufficientForExtension = RtpError('Header size insufficient for extension');
  static const RtpError malformedExtension = RtpError('Malformed RTP extension');
  static const RtpError shortPacket = RtpError('Short packet');
  static const RtpError bufferTooSmall = RtpError('Buffer too small'); // Equivalent to ErrBufferTooSmall
  static const RtpError headerExtensionPayloadNot32BitWords = RtpError('Header extension payload not 32-bit words');
  static const RtpError rfc3550headerIdrange = RtpError('RFC3550 header ID range error (must be 0)');
  static const RtpError rfc8285oneByteHeaderIdrange = RtpError('RFC8285 one-byte header ID range (1-14)');
  static const RtpError rfc8285oneByteHeaderSize = RtpError('RFC8285 one-byte header payload size (>16 bytes)');
  static const RtpError rfc8285twoByteHeaderIdrange = RtpError('RFC8285 two-byte header ID range (>0)');
  static const RtpError rfc8285twoByteHeaderSize = RtpError('RFC8285 two-byte header payload size (>255 bytes)');
  static const RtpError headerExtensionNotFound = RtpError('Header extension not found');
  static const RtpError headerExtensionsNotEnabled = RtpError('Header extensions not enabled');
}

enum ExtensionProfile {
  OneByte(EXTENSION_PROFILE_ONE_BYTE),
  TwoByte(EXTENSION_PROFILE_TWO_BYTE),
  unknown(-1);

  const ExtensionProfile(this.value);
  final int value;

  factory ExtensionProfile.fromInt(int key) {
    return values.firstWhere((element) => element.value == key, orElse: () => ExtensionProfile.unknown);
  }
}

class Extension {
  int id;
  Uint8List payload;

  Extension({required this.id, required this.payload});

  @override
  String toString() {
    return 'Extension(id: $id, payloadLength: ${payload.length} bytes, payload: [${payload.join(',')}])';
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
  ExtensionProfile extensionProfile;
  List<Extension> extensions;
  int extensionsPadding; // This field tracks *added* padding for extensions, not total

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

  /// Unmarshal parses the passed byte slice and stores the result in the Header this method is called upon
  /// Returns a tuple of (Header, bytes_read_for_header).
  static (Header, int) unmarshal(Uint8List rawPacket, {int initialOffset = 0}) {
    int currentOffset = initialOffset;
    final int rawPacketLen = rawPacket.lengthInBytes;

    final ByteData reader = ByteData.view(rawPacket.buffer, rawPacket.offsetInBytes + initialOffset);

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

    final int sequenceNumber = reader.getUint16(currentOffset - initialOffset, Endian.big);
    currentOffset += 2;
    final int timestamp = reader.getUint32(currentOffset - initialOffset, Endian.big);
    currentOffset += 4;
    final int ssrc = reader.getUint32(currentOffset - initialOffset, Endian.big);
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

      final int intExtProfile = reader.getUint16(currentOffset - initialOffset, Endian.big);
      extensionProfile = ExtensionProfile.fromInt(intExtProfile);
      currentOffset += 2;

      final int extensionLengthWords = reader.getUint16(currentOffset - initialOffset, Endian.big);
      final int extensionLengthBytes = extensionLengthWords * 4;
      currentOffset += 2;

      if (remainingLength < (currentOffset - initialOffset) + extensionLengthBytes) {
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

              final Uint8List payload = Uint8List.view(
                  rawPacket.buffer, rawPacket.offsetInBytes + currentOffset, len);
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

              final Uint8List payload = Uint8List.view(
                  rawPacket.buffer, rawPacket.offsetInBytes + currentOffset, len);
              extensions.add(Extension(id: extId, payload: payload));
              currentOffset += len;
            }
          }
          break;

        default: // RFC3550 Extension or unknown profile
          final Uint8List payload = Uint8List.view(
              rawPacket.buffer, rawPacket.offsetInBytes + currentOffset, extensionLengthBytes);
          extensions.add(Extension(id: 0, payload: payload)); // ID 0 for generic RFC3550
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

  /// Calculates the total size of the header when marshaled.
  int getMarshalSize() {
    int size = 12 + (csrc.length * CSRC_LENGTH); // Fixed header + CSRC

    if (extension) {
      size += 4; // Extension header (profile + length)
      int extensionPayloadLen = getExtensionPayloadLen();
      int extensionPayloadSizeWords = (extensionPayloadLen + 3) ~/ 4; // Round up to nearest 4-byte word
      size += extensionPayloadSizeWords * 4; // Actual bytes written for extension data including padding
    }
    return size;
  }

  /// Calculates the raw byte length of the extension payloads (excluding header and padding).
  int getExtensionPayloadLen() {
    int payloadLen = 0;
    for (final ext in extensions) {
      payloadLen += ext.payload.length;
    }

    int profileHeaderLen = 0;
    for (final ext in extensions) {
      profileHeaderLen += switch (extensionProfile) {
        ExtensionProfile.OneByte => 1, // 1 byte for ID/len field
        ExtensionProfile.TwoByte => 2, // 2 bytes for ID and length fields
        _ => 0, // RFC3550 or unknown, header handled in outer loop
      };
    }
    return payloadLen + profileHeaderLen;
  }

  /// MarshalTo serializes the header and writes it to the provided buffer.
  /// Returns the number of bytes written or throws an RtpError if the buffer is too small or malformed.
  int marshalTo(Uint8List buf) {
    final int requiredSize = getMarshalSize();
    if (buf.lengthInBytes < requiredSize) {
      throw RtpError.bufferTooSmall;
    }

    final ByteData writer = ByteData.view(buf.buffer, buf.offsetInBytes);
    int offset = 0;

    // Byte 0 (V, P, X, CC)
    int b0 = (version << VERSION_SHIFT) | csrc.length;
    if (padding) {
      b0 |= (1 << PADDING_SHIFT);
    }
    if (extension) {
      b0 |= (1 << EXTENSION_SHIFT);
    }
    writer.setUint8(offset, b0);
    offset += 1;

    // Byte 1 (M, PT)
    int b1 = payloadType;
    if (marker) {
      b1 |= (1 << MARKER_SHIFT);
    }
    writer.setUint8(offset, b1);
    offset += 1;

    // Sequence Number
    writer.setUint16(offset, sequenceNumber, Endian.big);
    offset += 2;

    // Timestamp
    writer.setUint32(offset, timestamp, Endian.big);
    offset += 4;

    // SSRC
    writer.setUint32(offset, ssrc, Endian.big);
    offset += 4;

    // CSRC Identifiers
    for (final csrcId in csrc) {
      writer.setUint32(offset, csrcId, Endian.big);
      offset += 4;
    }

    // Extension Header
    if (extension) {
      writer.setUint16(offset, extensionProfile.value, Endian.big);
      offset += 2;

      int extensionPayloadLen = getExtensionPayloadLen();
      int extensionLengthWords = (extensionPayloadLen + 3) ~/ 4; // Round up to nearest 4-byte word
      writer.setUint16(offset, extensionLengthWords, Endian.big);
      offset += 2;

      // Validate for RFC3550 if not one-byte/two-byte profile
      if (extensionProfile != ExtensionProfile.OneByte &&
          extensionProfile != ExtensionProfile.TwoByte) {
        if (extensionPayloadLen % 4 != 0) {
          throw RtpError.headerExtensionPayloadNot32BitWords;
        }
        if (extensions.length != 1) {
          throw RtpError.rfc3550headerIdrange; // Or a more specific error for multiple extensions
        }
      }

      // Write Extension Payloads
      switch (extensionProfile) {
        case ExtensionProfile.OneByte:
          for (final ext in extensions) {
            // ID (4 bits) | Length (4 bits, L=len-1)
            writer.setUint8(offset, (ext.id << 4) | (ext.payload.length - 1));
            offset += 1;
            buf.setRange(offset, offset + ext.payload.length, ext.payload);
            offset += ext.payload.length;
          }
          break;

        case ExtensionProfile.TwoByte:
          for (final ext in extensions) {
            writer.setUint8(offset, ext.id);
            offset += 1;
            writer.setUint8(offset, ext.payload.length);
            offset += 1;
            buf.setRange(offset, offset + ext.payload.length, ext.payload);
            offset += ext.payload.length;
          }
          break;

        default: // RFC3550 or unknown
          // Already validated to have 1 extension and 32-bit aligned payload for non-RFC8285 profiles
          if (extensions.isNotEmpty) {
            buf.setRange(offset, offset + extensions.first.payload.length, extensions.first.payload);
            offset += extensions.first.payload.length;
          }
          break;
      }

      // Add padding bytes for extensions
      // This loop is explicitly for adding 0-padding to reach the 4-byte word boundary
      // after writing the actual extension data.
      final int actualExtensionDataWritten = offset - (requiredSize - (extensionLengthWords * 4));
      final int paddingNeeded = (extensionLengthWords * 4) - actualExtensionDataWritten;

      for (int i = 0; i < paddingNeeded; i++) {
        writer.setUint8(offset, 0);
        offset += 1;
      }
    }

    return offset;
  }
}

/// Represents an RTP Packet
class Packet {
  Header header;
  Uint8List payload;
  Uint8List rawData; // Store the original raw data for encryption/decryption
  int headerSize; // Store the size of the header in rawData

  Packet({
    required this.header,
    required this.payload,
    required this.rawData,
    required this.headerSize,
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
      payload: Uint8List(0),
      rawData: Uint8List(0), // Initialize rawData as empty for an empty packet
      headerSize: 0, // Initialize headerSize as 0 for an empty packet
    );
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
            rawData: rawPacket,
            headerSize: headerLen,
          );
        } else {
          throw RtpError.shortPacket;
        }
      } else {
        throw RtpError.shortPacket;
      }
    } else {
      return Packet(
          header: header,
          payload: payload,
          rawData: rawPacket,
          headerSize: headerLen,
      );
    }
  }

  /// Calculates the total size of the Packet when marshaled.
  int getMarshalSize() {
    int size = header.getMarshalSize();
    size += payload.length;
    // If padding is enabled, add the padding size to the total.
    // The actual padding value is in the last byte of the payload (before padding).
    // This is typically handled during marshal of the *full packet*, not just the header.
    // For now, this is just payload data length.
    return size;
  }

  /// MarshalTo serializes the packet and writes it to the provided buffer.
  /// Returns the number of bytes written or throws an RtpError.
  int marshalTo(Uint8List buf) {
    final int requiredSize = getMarshalSize();
    if (buf.lengthInBytes < requiredSize) {
      throw RtpError.bufferTooSmall;
    }

    int offset = 0;
    // Marshal the header first
    offset += header.marshalTo(Uint8List.view(buf.buffer, buf.offsetInBytes + offset));

    // Then write the payload
    if (payload.isNotEmpty) {
      buf.setRange(offset, offset + payload.length, payload);
      offset += payload.length;
    }

    // Handle padding for the *entire packet* if header.padding is true
    // This part is more complex as it involves modifying the last byte of the payload
    // and adding padding bytes. For a simple marshal, we just write the payload as is.
    // The Rust `packet.marshal_to` would handle this. For now, assume payload is already correct.
    // If you need the *full* `Packet.marshal_to` with padding logic, that's a separate step.
    return offset;
  }

  /// Marshal serializes the packet and returns a new Uint8List.
  Uint8List serialize() {
    final int size = getMarshalSize();
    final Uint8List buf = Uint8List(size);
    marshalTo(buf); // Use marshalTo to write to the new buffer
    return buf;
  }
}