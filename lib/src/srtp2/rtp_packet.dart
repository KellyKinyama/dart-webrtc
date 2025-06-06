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
    final Uint8List fullRawData =
        Uint8List.fromList(buf.sublist(offset, offset + arrayLen));
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
      final int paddingSize = buf[offset +
          arrayLen -
          1 -
          (offset - offsetBackup)]; // Padding size is at the end of the packet
      lastPosition = arrayLen - 1 - paddingSize;
    }

    final Uint8List payload =
        Uint8List.fromList(buf.sublist(offset, offsetBackup + lastPosition));

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
    return 'RTP Version: ${header.version}, SSRC: ${header.ssrc}, Payload Type: ${header.payloadType}, Seq Number: ${header.sequenceNumber}, CSRC Count: ${header.csrc.length}, Payload Length: ${payload.length} Marker: ${header.marker}, Extension: ${header.extensions}';
  }
}

class PacketDecodeResult {
  final Packet packet;
  final int offset;

  PacketDecodeResult(this.packet, this.offset);
}

void main() {
  final decodedPacket =
      Packet.decodePacket(rawRtpPacket, 0, rawRtpPacket.length);
  print("Decoded packet: ${decodedPacket.packet}");

  //  expect(parsed.header.version).toBe(2);
  //   expect(parsed.header.padding).toBe(false);
  //   expect(parsed.header.extension).toBe(true);
  //   expect(parsed.header.csrc.length).toBe(0);
  //   expect(parsed.header.marker).toBe(true);
  //   expect(parsed.header.sequenceNumber).toBe(27023);
  //   expect(parsed.header.timestamp).toBe(3653407706);
  //   expect(parsed.header.ssrc).toBe(476325762);
  //   expect(parsed.header.extensionProfile).toBe(1);
  //   expect(parsed.header.extensionLength).toBe(4);
  //   expect(parsed.header.extensions).toEqual([
  //     { id: 0, payload: Buffer.from([0xff, 0xff, 0xff, 0xff]) },
  //   ]);
  //   expect(parsed.header.payloadOffset).toBe(20);
  //   expect(parsed.header.payloadType).toBe(96);

  //   expect(parsed.header.serializeSize).toBe(20);
  //   expect(parsed.serializeSize).toBe(raw.length);
  //   const serialized = parsed.serialize();
  //   expect(serialized).toEqual(raw);
}

// final rawRtpPacket = Uint8List.fromList([
//   0x90,
//   0xe0,
//   0x69,
//   0x8f,
//   0xd9,
//   0xc2,
//   0x93,
//   0xda,
//   0x1c,
//   0x64,
//   0x27,
//   0x82,
//   0xbe,
//   0xde,
//   0x00,
//   0x01,
//   0x10,
//   0xaa,
//   0x20,
//   0xbb,
//   0x98,
//   0x36,
//   0xbe,
//   0x88,
//   0x9e,
// ]);

// final rawRtpPacket = Uint8List.fromList([
//   0x90,
//   0xe0,
//   0x69,
//   0x8f,
//   0xd9,
//   0xc2,
//   0x93,
//   0xda,
//   0x1c,
//   0x64,
//   0x27,
//   0x82,
//   0xbe,
//   0xde,
//   0x00,
//   0x01,
//   0x50,
//   0xaa,
//   0x00,
//   0x00,
//   0x98,
//   0x36,
//   0xbe,
//   0x88,
//   0x9e,
// ]);

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
