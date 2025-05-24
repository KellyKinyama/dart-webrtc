import 'dart:typed_data';

enum PayloadType {
  VP8(96),
  Opus(109),
  Unknown(-1);

  final int value;
  const PayloadType(this.value);

  static PayloadType fromInt(int value) {
    return PayloadType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => PayloadType.Unknown,
    );
  }

  String get codecName {
    switch (this) {
      case PayloadType.VP8:
        return 'VP8/90000';
      case PayloadType.Opus:
        return 'OPUS/48000/2';
      default:
        return 'Unknown';
    }
  }

  @override
  String toString() => '$codecName ($value)';
}

class Extension {
  final int id;
  final Uint8List payload;

  Extension(this.id, this.payload);
}

class RtpHeader {
  final int version;
  final bool padding;
  final bool extension;
  final bool marker;
  final PayloadType payloadType;
  final int sequenceNumber;
  final int timestamp;
  final int ssrc;
  final List<int> csrc;
  final Uint8List rawData;

  RtpHeader(
    this.version,
    this.padding,
    this.extension,
    this.marker,
    this.payloadType,
    this.sequenceNumber,
    this.timestamp,
    this.ssrc,
    this.csrc,
    this.rawData,
  );

  static bool isRtpPacket(Uint8List buf, int offset) {
    if (buf.length < offset + 2) return false;
    int payloadType = buf[offset + 1] & 0x7F;
    return (payloadType <= 35) || (payloadType >= 96 && payloadType <= 127);
  }

  static (RtpHeader, int) decodeHeader(
      Uint8List buf, int offset, int arrayLen) {
    if (buf.length < offset + 12)
      throw ArgumentError("wrong length: ${buf.length}");

    int initialOffset = offset;
    int firstByte = buf[offset++];
    int version = (firstByte >> 6) & 0x03;
    bool padding = ((firstByte >> 5) & 0x01) == 1;
    bool extension = ((firstByte >> 4) & 0x01) == 1;
    int csrcCount = firstByte & 0x0F;

    int secondByte = buf[offset++];
    bool marker = ((secondByte >> 7) & 0x01) == 1;
    PayloadType payloadType = PayloadType.fromInt(secondByte & 0x7F);

    int sequenceNumber = (buf[offset] << 8) | buf[offset + 1];
    offset += 2;
    int timestamp = (buf[offset] << 24) |
        (buf[offset + 1] << 16) |
        (buf[offset + 2] << 8) |
        buf[offset + 3];
    offset += 4;
    int ssrc = (buf[offset] << 24) |
        (buf[offset + 1] << 16) |
        (buf[offset + 2] << 8) |
        buf[offset + 3];
    offset += 4;

    List<int> csrc = [];
    for (int i = 0; i < csrcCount; i++) {
      if (offset + 4 > buf.length)
        throw ArgumentError("wrong length: ${buf.length}");
      int value = (buf[offset] << 24) |
          (buf[offset + 1] << 16) |
          (buf[offset + 2] << 8) |
          buf[offset + 3];
      csrc.add(value);
      offset += 4;
    }

    return (
      RtpHeader(
          version,
          padding,
          extension,
          marker,
          payloadType,
          sequenceNumber,
          timestamp,
          ssrc,
          csrc,
          buf.sublist(initialOffset, offset)),
      offset
    );
  }

  @override
  String toString() {
    // TODO: implement toString
    return """
    RTP header{
      version: $version,
      padding: $padding,
      extension: $extension,
      marker: $marker,
      payload type: $payloadType,
      Sequence number: $sequenceNumber,
      time stamp: $timestamp,
      ssrc: $ssrc,
      csrc: $csrc
    }""";
  }
}
