import 'dart:typed_data';
import 'package:collection/collection.dart';

enum PayloadType {
  vp8(96, "VP8/90000"),
  opus(109, "OPUS/48000/2"),
  unknown(-1, "Unknown");

  final int value;
  final String codecName;

  const PayloadType(this.value, this.codecName);

  factory PayloadType.fromValue(int value) {
    return PayloadType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => PayloadType.unknown,
    );
  }

  @override
  String toString() {
    return '$codecName ($value)';
  }

  String toCodecCodeNumber() {
    return value.toString();
  }
}

class Extension {
  final int id;
  final Uint8List payload;

  Extension({required this.id, required this.payload});
}

class Header {
  final int version;
  final bool padding;
  final bool extension;
  final bool marker;
  final PayloadType payloadType;
  final int sequenceNumber;
  final int timestamp;
  final int ssrc;
  final List<int> csrc;
  final int extensionProfile; // Not fully parsed in Go, but kept for completeness
  final List<Extension> extensions; // Not fully parsed in Go, but kept for completeness

  final Uint8List rawData;

  Header._({
    required this.version,
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
    required this.rawData,
  });

  static bool isRtpPacket(Uint8List buf, int offset, int arrayLen) {
    if (arrayLen - offset < 2) {
      return false; // Not enough bytes for basic header
    }
    final int payloadType = buf[offset + 1] & 0x7F;
    return (payloadType <= 35) || (payloadType >= 96 && payloadType <= 127);
  }

  static HeaderDecodeResult decodeHeader(
      Uint8List buf, int offset, int arrayLen) {
    final int offsetBackup = offset;
    if (arrayLen - offset < 12) {
      throw Exception("Buffer too small for RTP header");
    }

    final int firstByte = buf[offset++];
    final int version = (firstByte >> 6) & 0x03;
    final bool padding = ((firstByte >> 5) & 0x01) == 1;
    final bool extension = ((firstByte >> 4) & 0x01) == 1;
    final int csrcCount = firstByte & 0x0F;

    final int secondByte = buf[offset++];
    final bool marker = ((secondByte >> 7) & 0x01) == 1;
    final PayloadType payloadType = PayloadType.fromValue(secondByte & 0x7F);

    final int sequenceNumber = ByteData.view(buf.buffer, offset, 2).getUint16(0, Endian.big);
    offset += 2;
    final int timestamp = ByteData.view(buf.buffer, offset, 4).getUint32(0, Endian.big);
    offset += 4;
    final int ssrc = ByteData.view(buf.buffer, offset, 4).getUint32(0, Endian.big);
    offset += 4;

    final List<int> csrcList = [];
    for (int i = 0; i < csrcCount; i++) {
      if (arrayLen - offset < 4) {
        throw Exception("Buffer too small for CSRC identifiers");
      }
      csrcList.add(ByteData.view(buf.buffer, offset, 4).getUint32(0, Endian.big));
      offset += 4;
    }

    // Extension parsing is not fully implemented in the Go code,
    // so we'll just skip it for now and set defaults.
    int extensionProfile = 0;
    List<Extension> extensions = [];

    if (extension) {
      // In a real implementation, you'd parse RTP extensions here.
      // For now, we'll just advance the offset past the standard header.
      // The Go code provided does not parse the actual extension data.
    }

    final Uint8List rawData = Uint8List.fromList(buf.sublist(offsetBackup, offset));

    return HeaderDecodeResult(
      Header._(
        version: version,
        padding: padding,
        extension: extension,
        marker: marker,
        payloadType: payloadType,
        sequenceNumber: sequenceNumber,
        timestamp: timestamp,
        ssrc: ssrc,
        csrc: csrcList,
        extensionProfile: extensionProfile,
        extensions: extensions,
        rawData: rawData,
      ),
      offset,
    );
  }
}

class HeaderDecodeResult {
  final Header header;
  final int offset;

  HeaderDecodeResult(this.header, this.offset);
}
