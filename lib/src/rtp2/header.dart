import 'dart:typed_data';

enum PayloadType {
  PayloadTypeVP8(96),
  PayloadTypeOpus(109),

  PayloadALaw(0),
  PayloadTypeMuLaw(1),
  Unknown(3000);

  const PayloadType(this.value);
  final int value;

  factory PayloadType.fromInt(int key) {
    return values.firstWhere((element) => element.value == key,
        orElse: () => PayloadType.Unknown);
  }
}

/*
	0                   1                   2                   3
	0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
	+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
	|V=2|P|X|  CC   |M|     PT      |       Sequence Number         |
	+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
	|                           Timestamp                           |
	+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
	|           Synchronization Source (SSRC) identifier            |
	+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
	|            Contributing Source (CSRC) identifiers             |
	|                             ....                              |
	+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
	|                            Payload                            |
	+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
*/

class RtpHeader {
  int version; //         byte
  bool padding; //          bool
  bool extension; //       bool
  bool marker; //           bool
  // PayloadType payloadType;
  int payloadType;
  int sequenceNumber; //   uint16
  int timestamp; //       uint32
  int SSRC; //            uint32
  List<int> CSRC; //             []uint32
  late int extensionProfile; // uint16
  late List<RtpExtension> extensions;

  Uint8List rawData; //[]byte

  RtpHeader(
      {required this.version,
      required this.padding,
      required this.extension,
      required this.marker,
      required this.payloadType,
      required this.sequenceNumber,
      required this.timestamp,
      required this.SSRC,
      required this.CSRC,
      required this.rawData});

  static (RtpHeader, int) decodeHeader(Uint8List buf, int offset, int arrayLen)
  // (*Header, int, error)
  {
    // result := new(Header)
    final offsetBackup = offset;
    final firstByte = buf[offset];
    offset++;
    final version = firstByte & 192 >> 6;
    final padding = (firstByte & 32 >> 5) == 1;
    final extension = (firstByte & 16 >> 4) == 1;
    final csrcCount = firstByte & 15;

    final secondByte = buf[offset];
    offset++;
    final marker = (secondByte & 128 >> 7) == 1;
    // final payloadType = PayloadType.fromInt(secondByte & 127);
    final payloadType = secondByte;

    final sequenceNumber = ByteData.sublistView(buf).getUint16(offset);
    offset += 2;
    final timestamp = ByteData.sublistView(buf).getUint32(offset);
    offset += 4;
    final SSRC = ByteData.sublistView(buf).getUint32(offset);
    offset += 4;

    List<int> CSRC = List.filled(csrcCount, 0);
    for (int i = 0; i < csrcCount; i++) {
      CSRC[i] = ByteData.sublistView(buf).getUint32(offset);
      offset += 4;
    }
    final rawData = buf.sublist(offsetBackup, offset);
    return (
      RtpHeader(
          version: version, //         byte
          padding: padding, //          bool
          extension: extension, //       bool
          marker: marker, //           bool
          payloadType: payloadType,
          sequenceNumber: sequenceNumber, //   uint16
          timestamp: timestamp, //       uint32
          SSRC: SSRC, //            uint32
          CSRC: CSRC, //             []uint32
          // extensionProfile:,// uint16
          // extensions:,

          rawData: rawData //[]byte, offset)
          ),
      offset
    );
  }

  static bool isRtpPacket(Uint8List buf, int offset, int arrayLen) {
    // https://csperkins.org/standards/ietf-67/2006-11-07-IETF67-AVT-rtp-rtcp-mux.pdf
    // Initial segment of RTP header; 7 bit payload
    // type; values 0...35 and 96...127 usually used
    final payloadType = buf[offset + 1] & 127;
    return (payloadType <= 35) || (payloadType >= 96 && payloadType <= 127);
  }
}

class RtpExtension {
  int id; //      byte
  Uint8List payload; // []byte
  RtpExtension({required this.id, required this.payload});
}
