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

  @override
  String toString() {
    return 'RTP Version: ${header.version}, SSRC: ${header.SSRC}, Payload Type: ${header.payloadType}, '
        'Seq Number: ${header.sequenceNumber}, CSRC Count: ${header.CSRC.length}, '
        'Payload Length: ${payload.length}, Marker: ${header.marker}';
  }
}

// func (p *Packet) String() string {
// 	return fmt.Sprintf("RTP Version: %d, SSRC: %d, Payload Type: %s, Seq Number: %d, CSRC Count: %d, Payload Length: %d Marker: %v",
// 		p.Header.Version, p.Header.SSRC, p.Header.PayloadType, p.Header.SequenceNumber, len(p.Header.CSRC), len(p.Payload), p.Header.Marker)
// }

void main() {
  final (packet, _) =
      RtpPacket.decodePacket(rawRtpPacket, 0, rawRtpPacket.length);
  print("RTP Packet: ${packet}");
  print("Payload Length: ${packet.payload.length}");
  print("Raw Data Length: ${packet.rawData.length}");
}

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
