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

  // @override
  // String toString() {
  //   return 'RTP Version: ${header.version}, SSRC: ${header.ssrc}, Payload Type: ${header.payloadType}, '
  //       'Seq Number: ${header.sequenceNumber}, CSRC Count: ${header.csrc.length}, '
  //       'Payload Length: ${payload.length}, Marker: ${header.marker}';
  // }

  @override
  String toString() {
    return 'RTP Packet { header $header, payload: $payload }';
  }
}

void main() {
  final rtpPacket = RtpPacket.decodePacket(raw_pkt, 0, raw_pkt.length);
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