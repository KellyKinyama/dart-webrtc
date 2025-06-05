import 'dart:typed_data';

import 'rtp_header.dart';

class Packet {
  final Header header;
  final int headerSize;
  final Uint8List payload;
  final Uint8List rawData;

  Packet._({
    required this.header,
    required this.headerSize,
    required this.payload,
    required this.rawData,
  });

  static PacketDecodeResult decodePacket(
      Uint8List buf, int offset, int arrayLen) {
    final Uint8List fullRawData = Uint8List.fromList(buf.sublist(offset, offset + arrayLen));
    final int offsetBackup = offset;

    final HeaderDecodeResult headerResult =
        Header.decodeHeader(buf, offset, arrayLen);
    final Header header = headerResult.header;
    offset = headerResult.offset;
    final int headerSize = offset - offsetBackup;

    int lastPosition = arrayLen - 1;
    if (header.padding) {
      if (arrayLen == 0) {
        throw Exception("RTP packet with padding has 0 length");
      }
      final int paddingSize = buf[offset + arrayLen - 1 - (offset - offsetBackup)]; // Padding size is at the end of the packet
      lastPosition = arrayLen - 1 - paddingSize;
    }

    final Uint8List payload = Uint8List.fromList(buf.sublist(offset, offsetBackup + lastPosition));

    return PacketDecodeResult(
      Packet._(
        header: header,
        headerSize: headerSize,
        payload: payload,
        rawData: fullRawData,
      ),
      offset,
    );
  }

  @override
  String toString() {
    return 'RTP Version: ${header.version}, SSRC: ${header.ssrc}, Payload Type: ${header.payloadType}, Seq Number: ${header.sequenceNumber}, CSRC Count: ${header.csrc.length}, Payload Length: ${payload.length} Marker: ${header.marker}';
  }
}

class PacketDecodeResult {
  final Packet packet;
  final int offset;

  PacketDecodeResult(this.packet, this.offset);
}
