import 'dart:typed_data';

import 'header.dart';

class RtpPacket {
  RtpHeader header;
  int headerSize;
  Uint8List payload;
  Uint8List rawData;

  RtpPacket(
      {required this.header,
      required this.headerSize,
      required this.payload,
      required this.rawData});

  static (RtpPacket, int) decodePacket(
      Uint8List buf, int offset, int arrayLen) {
    // result := new(Packet)
    final rawData = buf.sublist(offset);

    final offsetBackup = offset;
    final (header, decodedOffset) =
        RtpHeader.decodeHeader(buf, offset, arrayLen);

    final headerSize = offset - offsetBackup;
    int lastPosition = arrayLen - 1;
    if (header.padding) {
      final paddingSize = buf[arrayLen - 1];
      lastPosition = arrayLen - 1 - paddingSize;
    }
    final payload = buf.sublist(offset, lastPosition);
    return (
      RtpPacket(
          header: header,
          headerSize: headerSize,
          payload: payload,
          rawData: rawData),
      offset
    );
  }
}
// func (p *Packet) String() string {
// 	return fmt.Sprintf("RTP Version: %d, SSRC: %d, Payload Type: %s, Seq Number: %d, CSRC Count: %d, Payload Length: %d Marker: %v",
// 		p.Header.Version, p.Header.SSRC, p.Header.PayloadType, p.Header.SequenceNumber, len(p.Header.CSRC), len(p.Payload), p.Header.Marker)
// }
