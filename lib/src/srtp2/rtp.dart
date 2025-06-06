import 'dart:typed_data';

const HEADER_LENGTH = 4;
const VERSION_SHIFT = 6;
const VERSION_MASK = 0x3;
const PADDING_SHIFT = 5;
const PADDING_MASK = 0x1;
const EXTENSION_SHIFT = 4;
const EXTENSION_MASK = 0x1;
const EXTENSION_PROFILE_ONE_BYTE = 0xBEDE;
const EXTENSION_PROFILE_TWO_BYTE = 0x1000;
const EXTENSION_ID_RESERVED = 0xF;
const CC_MASK = 0xF;
const MARKER_SHIFT = 7;
const MARKER_MASK = 0x1;
const PT_MASK = 0x7F;
const SEQ_NUM_OFFSET = 2;
const SEQ_NUM_LENGTH = 2;
const TIMESTAMP_OFFSET = 4;
const TIMESTAMP_LENGTH = 4;
const SSRC_OFFSET = 8;
const SSRC_LENGTH = 4;
const CSRC_OFFSET = 12;
const CSRC_LENGTH = 4;

enum ExtensionProfile {
  OneByte(1), // 48862
  TwoByte(0x1000); // 4096

  const ExtensionProfile(this.value);
  final int value;

  factory ExtensionProfile.fromInt(int key) {
    return values.firstWhere((element) => element.value == key);
  }
}

class Extension {
  int id;
  Uint8List payload;

  Extension({required this.id, required this.payload});
}

/// Header represents an RTP packet header
/// NOTE: PayloadOffset is populated by Marshal/Unmarshal and should not be modified

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
  int extensionsPadding;

  Header(
      {required this.version,
      required this.padding,
      required this.extension,
      required this.marker,
      required this.payloadType,
      required this.sequenceNumber,
      required this.timestamp,
      required this.ssrc,
      required this.csrc,
      required this.extensionProfile,
      required this.extensions,
      required this.extensionsPadding});

  /// Unmarshal parses the passed byte slice and stores the result in the Header this method is called upon
  static (Header, int) unmarshal(
      Uint8List rawPacket, int offset, int arrayLen) {
    // let raw_packet_len = raw_packet.remaining();
    if (arrayLen < HEADER_LENGTH) {
      throw Exception("ErrHeaderSizeInsufficient");
    }
    /*
         *  0                   1                   2                   3
         *  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
         * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
         * |V=2|P|X|  CC   |M|     PT      |       sequence number         |
         * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
         * |                           timestamp                           |
         * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
         * |           synchronization source (SSRC) identifier            |
         * +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
         * |            contributing source (CSRC) identifiers             |
         * |                             ....                              |
         * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
         */
    final reader = ByteData.sublistView(rawPacket);
    final b0 = reader.getUint8(offset++);
    final version = b0 >> VERSION_SHIFT & VERSION_MASK;
    final padding = (b0 >> PADDING_SHIFT & PADDING_MASK) > 0;
    final extension = (b0 >> EXTENSION_SHIFT & EXTENSION_MASK) > 0;
    final cc = (b0 & CC_MASK);

    print("Version: $version");
    print("Padding: $padding");
    print("Extension: $extension");
    // print("Version: $version");

    // int curr_offset = CSRC_OFFSET + (cc * CSRC_LENGTH);
    if (arrayLen < offset) {
      throw Exception("ErrHeaderSizeInsufficient");
    }

    final b1 = reader.getUint8(offset++);
    final marker = (b1 >> MARKER_SHIFT & MARKER_MASK) > 0;
    final payloadType = b1 & PT_MASK;

    print("Marker: $marker");

    final sequenceNumber = reader.getUint16(offset);
    offset += 2;
    final timestamp = reader.getUint32(offset);
    offset += 4;
    final ssrc = reader.getUint32(offset);
    offset += 4;

    print("Sequence number: $sequenceNumber");
    print("Time stamp: $timestamp");
    print("SSRC: $ssrc");

    // List<int> csrc =[];// Vec::with_capacity(cc);
    List<int> csrc = List.generate(cc, (index) {
      int val = reader.getUint32(offset);
      offset++;
      return val;
    });

    int extensions_padding = 0;

    List<Extension> extensions = [];

    late ExtensionProfile extensionProfile;
    if (extension) {
      final intExtprofile = reader.getUint16(offset);
      print("Extension profile: 0x${intExtprofile.toRadixString(16)}");
      extensionProfile = ExtensionProfile.fromInt(intExtprofile);
      offset += 2;
      final extensionLength = reader.getUint16(offset) * 4;
      // h.extensionLength = extensionLength;
      offset += 2;

      print("Extension profile: $extensionProfile");
      print("Extension length: $extensionLength");

      switch (extensionProfile) {
        // RFC 8285 RTP One Byte Header Extension
        case ExtensionProfile.OneByte:
          {
            final end = offset + extensionLength;
            while (offset < end) {
              // if (rawPacket[offset] == 0x00) {
              //   offset++;
              //   print("Skipping");
              //   continue;
              // }

              // final extId = rawPacket[offset] >> 4;
              // final len = (rawPacket[offset] & (rawPacket[offset] ^ 0xf0)) +
              //     1; // and not &^
              // offset++;
              // if (extId == 0xf) {
              //   print("breaking");
              //   break;
              // }

              final b = reader.getUint8(offset);
              if (b == 0x00) {
                // padding
                print("Skipping");
                offset += 1;
                extensions_padding += 1;
                continue;
              }

              final extId = b >> 4;
              final len = ((b & (0xFF ^ 0xF0)) + 1);
              offset += 1;

              if (extId != EXTENSION_ID_RESERVED) {
                print("Extension Id is reserved");
                break;
              }
              final extension = Extension(
                id: extId,
                payload: rawPacket.sublist(offset, offset + len),
              );
              extensions.add(extension);
              offset += len;
            }
          }
          break;
        // RFC 8285 RTP Two Byte Header Extension
        case ExtensionProfile.TwoByte:
          {
            final end = offset + extensionLength;
            while (offset < end) {
              if (rawPacket[offset] == 0x00) {
                offset++;
                continue;
              }
              final extId = rawPacket[offset];
              offset++;
              final len = rawPacket[offset];
              offset++;

              final extension = Extension(
                id: extId,
                payload: rawPacket.sublist(offset, offset + len),
              );
              extensions.add(extension);
              offset += len;
            }
          }
          break;
        default:
          {
            final extension = Extension(
              id: 0,
              payload: rawPacket.sublist(
                offset,
                offset + extensionLength,
              ),
            );
            extensions.add(extension);
            offset += extensions[0].payload.length;
          }
          break;
      }
    }
    print("Extensions: $extensions");
    return (
      Header(
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
        extensionsPadding: extensions_padding,
      ),
      0
    );
  }
}

void main() {}
