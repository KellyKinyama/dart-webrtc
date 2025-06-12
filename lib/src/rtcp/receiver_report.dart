import 'dart:typed_data';
import 'rtcp_header.dart'; // Assuming RtcpHeader is in rtcp_header.dart
import 'reception_report.dart'; // Assuming ReceptionReportSample is in reception_report.dart
import 'net_convert.dart'; // Assuming NetConvert is in net_convert.dart

/// Represents an RTCP Receiver Report Packet.
class RtcpReceiverReport {
  RtcpHeader header;
  int ssrc; // SSRC of packet sender
  List<ReceptionReportSample> receptionReports;

  /// Creates a new RTCP Receiver Report from a byte array.
  factory RtcpReceiverReport.parse(Uint8List buffer) {
    final header = RtcpHeader.parse(buffer);
    final data = ByteData.view(buffer.buffer, RtcpHeader.headerBytesLength);

    int ssrc = 0;
    if (Endian.host == Endian.little) {
      ssrc = NetConvert.doReverseEndian(data.getUint32(0));
    } else {
      ssrc = data.getUint32(0);
    }

    final List<ReceptionReportSample> receptionReports = [];
    int offset = RtcpHeader.headerBytesLength + 4; // 4 bytes for SSRC
    while (offset < buffer.length) {
      receptionReports.add(ReceptionReportSample.parse(buffer, offset));
      offset += ReceptionReportSample.payloadSize;
    }

    return RtcpReceiverReport(
      header: header,
      ssrc: ssrc,
      receptionReports: receptionReports,
    );
  }

  /// Creates a new RTCP Receiver Report.
  RtcpReceiverReport({
    required this.header,
    this.ssrc = 0,
    this.receptionReports = const [],
  }) {
    header.packetType = RtcpReportTypesEnum.rr;
    header.receptionReportCount = receptionReports.length;
    final int len = (4 + receptionReports.length * ReceptionReportSample.payloadSize) ~/ 4;
    header.setLength(len);
  }

  /// Gets the serialised bytes for this Receiver Report.
  Uint8List getBytes() {
    int rrCount = receptionReports.length;
    int bufferLength = RtcpHeader.headerBytesLength + 4 + // 4 bytes for SSRC
        rrCount * ReceptionReportSample.payloadSize;
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

    int bufferIndex = payloadIndex + 4;
    for (var rr in receptionReports) {
      Uint8List rrBytes = rr.getBytes();
      buffer.setRange(bufferIndex, bufferIndex + rrBytes.length, rrBytes);
      bufferIndex += rrBytes.length;
    }

    return buffer;
  }
}