import 'dart:typed_data'; // For Uint8List, ByteData, Endian

// Constants (from Rust)
const int HEADER_LENGTH = 4;
const int VERSION_SHIFT = 6;
const int VERSION_MASK = 0x3;
const int PADDING_SHIFT = 5;
const int PADDING_MASK = 0x1;
const int EXTENSION_SHIFT = 4;
const int EXTENSION_MASK = 0x1;
const int EXTENSION_PROFILE_ONE_BYTE = 0xBEDE;
const int EXTENSION_PROFILE_TWO_BYTE = 0x1000;
const int EXTENSION_ID_RESERVED = 0xF;
const int CC_MASK = 0xF;
const int MARKER_SHIFT = 7;
const int MARKER_MASK = 0x1;
const int PT_MASK = 0x7F;
const int SEQ_NUM_OFFSET =
    2; // Not strictly needed in Dart with ByteData for reads
const int SEQ_NUM_LENGTH = 2;
const int TIMESTAMP_OFFSET = 4;
const int TIMESTAMP_LENGTH = 4;
const int SSRC_OFFSET = 8;
const int SSRC_LENGTH = 4;
const int CSRC_OFFSET = 12;
const int CSRC_LENGTH = 4;

// Custom Error class in Dart (equivalent to Rust's `Error`)
class RtpError implements Exception {
  final String message;
  const RtpError(this.message);

  @override
  String toString() => 'RtpError: $message';

  static const RtpError ErrHeaderSizeInsufficient =
      RtpError('Header size insufficient');
  static const RtpError ErrHeaderSizeInsufficientForExtension =
      RtpError('Header size insufficient for extension');
}

class Extension {
  int id;
  Uint8List payload;

  Extension({required this.id, required this.payload});

  @override
  String toString() {
    // You can customize the payload representation.
    // For example, showing a snippet of bytes, or just its length.
    // Here, we'll show the ID and the length of the payload.
    return 'Extension(id: $id, payload: $payload bytes)';
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
  List<int> csrc; // Corresponds to Vec<u32>
  int extensionProfile;
  List<Extension> extensions; // Corresponds to Vec<Extension>
  int extensionsPadding;

  Header({
    this.version = 0,
    this.padding = false,
    this.extension = false,
    this.marker = false,
    this.payloadType = 0,
    this.sequenceNumber = 0,
    this.timestamp = 0,
    this.ssrc = 0,
    List<int>? csrc,
    this.extensionProfile = 0,
    List<Extension>? extensions,
    this.extensionsPadding = 0,
  })  : csrc = csrc ?? [],
        extensions = extensions ?? [];

  @override
  String toString() {
    return 'Header(version: $version, padding: $padding, extension: $extension, '
        'marker: $marker, payloadType: $payloadType, sequenceNumber: $sequenceNumber, '
        'timestamp: $timestamp, ssrc: $ssrc, csrc: $csrc, '
        'extensionProfile: $extensionProfile, extensions: $extensions, '
        'extensionsPadding: $extensionsPadding)';
  }

  /// Unmarshal parses the passed byte slice and stores the result in the Header this method is called upon
  /// Returns the unmarshalled Header or throws an RtpError.
  static Header unmarshal(Uint8List rawPacket) {
    int rawPacketLen = rawPacket.lengthInBytes;
    int offset = 0; // Keep track of current read offset

    if (rawPacketLen < HEADER_LENGTH) {
      throw RtpError.ErrHeaderSizeInsufficient;
    }

    // Use ByteData for reading multi-byte values with specified endianness
    // RTP uses network byte order (Big Endian)
    final ByteData byteData = ByteData.view(rawPacket.buffer);

    // Read first byte (b0)
    int b0 = byteData.getUint8(offset);
    offset += 1;

    int version = (b0 >> VERSION_SHIFT) & VERSION_MASK;
    bool padding = ((b0 >> PADDING_SHIFT) & PADDING_MASK) > 0;
    bool extension = ((b0 >> EXTENSION_SHIFT) & EXTENSION_MASK) > 0;
    int cc = b0 & CC_MASK; // cc is an int in Dart

    int currOffset = CSRC_OFFSET + (cc * CSRC_LENGTH);
    if (rawPacketLen < currOffset) {
      throw RtpError.ErrHeaderSizeInsufficient;
    }

    // Read second byte (b1)
    int b1 = byteData.getUint8(offset);
    offset += 1;

    bool marker = ((b1 >> MARKER_SHIFT) & MARKER_MASK) > 0;
    int payloadType = b1 & PT_MASK;

    int sequenceNumber = byteData.getUint16(offset, Endian.big);
    offset += 2;
    int timestamp = byteData.getUint32(offset, Endian.big);
    offset += 4;
    int ssrc = byteData.getUint32(offset, Endian.big);
    offset += 4;

    List<int> csrc = [];
    for (int i = 0; i < cc; i++) {
      csrc.add(byteData.getUint32(offset, Endian.big));
      offset += 4;
    }

    int extensionsPadding = 0;
    int extensionProfile = 0;
    List<Extension> extensions = [];

    if (extension) {
      int expected = offset + 4; // For extension profile and length
      if (rawPacketLen < expected) {
        throw RtpError.ErrHeaderSizeInsufficientForExtension;
      }

      extensionProfile = byteData.getUint16(offset, Endian.big);
      offset += 2;
      int extensionLength = byteData.getUint16(offset, Endian.big) *
          4; // Rust multiplies by 4 here
      offset += 2;

      expected = offset + extensionLength;
      if (rawPacketLen < expected) {
        throw RtpError.ErrHeaderSizeInsufficientForExtension;
      }

      switch (extensionProfile) {
        case EXTENSION_PROFILE_ONE_BYTE:
          int end = offset + extensionLength;
          while (offset < end) {
            int b = byteData.getUint8(offset);
            offset += 1;

            if (b == 0x00) {
              // padding
              extensionsPadding += 1;
              continue;
            }

            int extId = b >> 4;
            int len = (b & (0xFF ^ 0xF0)) +
                1; // Rust: ((b & (0xFF ^ 0xF0)) + 1) as usize;

            if (extId == EXTENSION_ID_RESERVED) {
              // This means the rest of the extension data is padding or invalid
              // The Rust code uses `break` here.
              // We need to consume the remaining bytes of this extension block
              // before we can properly exit.
              extensionsPadding += (end - offset); // Count remaining as padding
              offset = end; // Move offset to the end
              break;
            }

            if (offset + len > end) {
              // This indicates an invalid extension length, or malformed packet
              throw RtpError(
                  'RTP one-byte extension payload goes beyond declared length');
            }
            Uint8List payload = Uint8List.view(
                rawPacket.buffer, rawPacket.offsetInBytes + offset, len);
            offset += len;

            extensions.add(Extension(id: extId, payload: payload));
          }
          break;

        case EXTENSION_PROFILE_TWO_BYTE:
          int end = offset + extensionLength;
          while (offset < end) {
            int b = byteData.getUint8(offset);
            offset += 1;

            if (b == 0x00) {
              // padding
              extensionsPadding += 1;
              continue;
            }

            int extId = b;
            // Rust code reads another byte for length, Dart needs to read it too.
            int len = byteData.getUint8(offset);
            offset += 1;

            if (offset + len > end) {
              // Invalid extension length
              throw RtpError(
                  'RTP two-byte extension payload goes beyond declared length');
            }
            Uint8List payload = Uint8List.view(
                rawPacket.buffer, rawPacket.offsetInBytes + offset, len);
            offset += len;

            extensions.add(Extension(id: extId, payload: payload));
          }
          break;

        default:
          // RFC3550 Extension (single extension blob)
          // The Rust code effectively treats the entire remaining extension_length
          // as a single payload for ID 0.
          if (offset + extensionLength > rawPacketLen) {
            throw RtpError.ErrHeaderSizeInsufficientForExtension;
          }
          Uint8List payload = Uint8List.view(rawPacket.buffer,
              rawPacket.offsetInBytes + offset, extensionLength);
          offset += extensionLength;
          extensions.add(Extension(id: 0, payload: payload));
          break;
      }
    }

    return Header(
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
  }
}

void main() {
  Header header = Header.unmarshal(raw);
  print(header);
  // You can add more tests or functionality here
}

final raw = Uint8List.fromList([
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
