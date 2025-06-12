import 'dart:typed_data';
import 'dart:convert'; // For utf8 encoding
import 'rtcp_header.dart'; // Assuming RtcpHeader is in rtcp_header.dart
import 'net_convert.dart'; // Assuming NetConvert is in net_convert.dart

/// Represents an RTCP Source Description (SDES) report as defined in RFC3550.
/// Only the mandatory CNAME item is supported.
class RtcpSdesReport {
  static const int cnameId = 1; // SDES item type for CNAME
  static const int packetSizeWithoutCname = 4 + 2; // SSRC + item type + length

  RtcpHeader header;
  int ssrc;
  String cname;

  /// Creates a new RTCP SDES Report from a byte array.
  factory RtcpSdesReport.parse(Uint8List buffer) {
    final header = RtcpHeader.parse(buffer);
    final data = ByteData.view(buffer.buffer, RtcpHeader.headerBytesLength);

    int ssrc = 0;
    if (Endian.host == Endian.little) {
      ssrc = NetConvert.doReverseEndian(data.getUint32(0));
    } else {
      ssrc = data.getUint32(0);
    }

    int cnameLength = data.getUint8(5);
    String cname = utf8.decode(buffer.sublist(
        RtcpHeader.headerBytesLength + 6,
        RtcpHeader.headerBytesLength + 6 + cnameLength));

    return RtcpSdesReport(
      header: header,
      ssrc: ssrc,
      cname: cname,
    );
  }

  /// Creates a new RTCP SDES Report.
  RtcpSdesReport({
    required this.header,
    this.ssrc = 0,
    this.cname = '',
  }) {
    header.packetType = RtcpReportTypesEnum.sdes;
    header.receptionReportCount = 1; // Always 1 for mandatory CNAME item
    header.setLength((getPaddedLength(utf8.encode(cname).length) ~/ 4));
  }

  /// Gets the serialised bytes for this SDES Report.
  Uint8List getBytes() {
    final cnameBytes = utf8.encode(cname);
    int bufferLength = RtcpHeader.headerBytesLength + getPaddedLength(cnameBytes.length);
    final buffer = Uint8List(bufferLength);
    final data = ByteData.view(buffer.buffer);

    Uint8List headerBytes = header.getBytes();
    buffer.setRange(0, headerBytes.length, headerBytes);

    int payloadIndex = RtcpHeader.headerBytesLength;

    if (Endian.host == Endian.little) {
      data.setUint32(payloadIndex, NetConvert.doReverseEndian(ssrc));
    } else {
      data.setUint32(payloadIndex, ssrc);
    }

    buffer[payloadIndex + 4] = cnameId;
    buffer[payloadIndex + 5] = cnameBytes.length;
    buffer.setRange(payloadIndex + 6, payloadIndex + 6 + cnameBytes.length, cnameBytes);

    // Add padding if necessary
    int currentLength = payloadIndex + 6 + cnameBytes.length;
    while (currentLength % 4 != 0) {
      buffer[currentLength++] = 0;
    }

    return buffer;
  }

  /// Calculates the minimum packet length for the SDES fields to fit within a 4 byte boundary.
  int getPaddedLength(int cnameLength) {
    // Plus one is for the 0x00 items termination byte.
    int nonPaddedSize = cnameLength + packetSizeWithoutCname + 1;

    if (nonPaddedSize % 4 == 0) {
      return nonPaddedSize;
    } else {
      return nonPaddedSize + (4 - (nonPaddedSize % 4));
    }
  }
}