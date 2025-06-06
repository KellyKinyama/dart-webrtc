import 'dart:typed_data';
import 'header.dart';

class RtpPacket {
  final RtpHeader header;
  final int headerSize;
  final Uint8List payload;
  final Uint8List rawData;

  RtpPacket({
    required this.header,
    required this.headerSize,
    required this.payload,
    required this.rawData,
  });

  static RtpPacket? decodePacket(Uint8List buf, int offset, int arrayLen) {
    try {
      Uint8List rawData =
          Uint8List.fromList(buf.sublist(offset, offset + arrayLen));
      int offsetBackup = offset;
      var (header, decodedOffset) =
          RtpHeader.decodeHeader(buf, offset, arrayLen);
      if (header == null) return null;

      int headerSize = offset - offsetBackup;
      offset += headerSize;

      int lastPosition = arrayLen;
      if (header.padding) {
        int paddingSize = buf[arrayLen - 1];
        lastPosition = arrayLen - paddingSize;
      }
      Uint8List payload = buf.sublist(offset, lastPosition);

      return RtpPacket(
        header: header,
        headerSize: offset - offsetBackup,
        payload: payload,
        rawData: rawData,
      );
    } catch (e) {
      return null;
    }
  }

  @override
  String toString() {
    return 'RTP Version: ${header.version}, SSRC: ${header.ssrc}, Payload Type: ${header.payloadType}, '
        'Seq Number: ${header.sequenceNumber}, CSRC Count: ${header.csrc.length}, '
        'Payload Length: ${payload.length}, Marker: ${header.marker}';
  }

  // @override
  // String toString() {
  //   return 'RTP Packet { header $header, payload: $payload }';
  // }
}

void main() {
  final rtpPacket =
      RtpPacket.decodePacket(rawRtpPacket, 0, rawRtpPacket.length);
  print("RTP packet: $rtpPacket");
}

final raw_pkt = Uint8List.fromList([
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
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0x98,
  0x36,
  0xbe,
  0x88,
  0x9e,
]);
// let parsed_packet = Packet {
//     header: Header {
//         version: 2,
//         padding: false,
//         extension: true,
//         marker: true,
//         payload_type: 96,
//         sequence_number: 27023,
//         timestamp: 3653407706,
//         ssrc: 476325762,
//         csrc: vec![],
//         extension_profile: 1,
//         extensions: vec![Extension {
//             id: 0,
//             payload: Bytes::from_static(&[0xFF, 0xFF, 0xFF, 0xFF]),
//         }],
//         ..Default::default()
//     },
//     payload: Bytes::from_static(&[0x98, 0x36, 0xbe, 0x88, 0x9e]),
// };

final rawRtpPacket = Uint8List.fromList([
  248,
  245,
  252,
  126,
  156,
  117,
  248,
  251,
  186,
  250,
  120,
  251,
  247,
  182,
  246,
  123,
  250,
  223,
  157,
  247,
  246,
  93,
  244,
  159,
  249,
  251,
  251,
  111,
  154,
  243,
  124,
  187,
  158,
  117,
  248,
  223,
  248,
  222,
  181,
  248,
  111,
  222,
  219,
  245,
  248,
  181,
  244,
  247,
  250,
  222,
  158,
  247,
  244,
  243,
  246,
  94,
  188,
  190,
  124,
  155,
  112,
  183,
  252,
  122,
  92,
  183,
  248,
  252,
  248,
  251,
  246,
  122,
  182,
  222,
  246,
  251,
  156,
  245,
  120,
  122,
  250,
  187,
  222,
  249,
  247,
  183,
  95,
  223,
  221,
  246,
  251,
  93,
  183,
  183,
  88,
  159,
  247,
  121,
  246,
  221,
  244,
  218,
  246,
  251,
  184,
  244,
  248,
  220,
  95,
  244,
  187,
  251,
  159,
  241,
  157,
  123,
  246,
  218,
  246,
  222,
  154,
  223,
  223,
  244,
  115,
  156,
  243,
  156,
  223,
  251,
  251,
  251,
  123,
  217,
  243,
  158,
  95,
  184,
  250,
  251,
  152,
  248,
  187,
  93,
  221,
  95,
  251,
  247,
  187,
  157,
  117,
  221,
  247,
  95,
  117,
  179,
  221,
  247,
  218,
  187
]);
