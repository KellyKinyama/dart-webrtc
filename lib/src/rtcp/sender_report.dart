import 'dart:typed_data';
import 'rtcp_header.dart'; // Assuming RtcpHeader is in rtcp_header.dart
import 'reception_report.dart'; // Assuming ReceptionReportSample is in reception_report.dart
import 'net_convert.dart'; // Assuming NetConvert is in net_convert.dart
import 'package:fixnum/fixnum.dart';

/// Represents an RTCP Sender Report Packet.
class RtcpSenderReport {
  static const int senderReportSize = 24; // Size of sender info block

  RtcpHeader header;
  int ssrc; // SSRC of sender
  Int64 ntpTimestamp; // NTP timestamp
  int rtpTimestamp; // RTP timestamp
  int packetCount; // Sender's packet count
  Int64 octetCount; // Sender's octet count
  List<ReceptionReportSample> receptionReports;

  /// Creates a new RTCP Sender Report from a byte array.
  factory RtcpSenderReport.parse(Uint8List buffer) {
    final header = RtcpHeader.parse(buffer);
    final data = ByteData.view(buffer.buffer, RtcpHeader.headerBytesLength);

    int ssrc = 0;
    Int64 ntpTimestamp = Int64(0);
    int rtpTimestamp = 0;
    int packetCount = 0;
    Int64 octetCount = Int64(0);

    // Read the two 32-bit words for NTP timestamp
    int ntpHigh = 0;
    int ntpLow = 0;
    int rtpTs = 0;
    int pktCount = 0;
    int octCount = 0;

    if (Endian.host == Endian.little) {
      ssrc = NetConvert.doReverseEndian(data.getUint32(0));
      ntpHigh = NetConvert.doReverseEndian(data.getUint32(4));
      ntpLow = NetConvert.doReverseEndian(data.getUint32(8));
      rtpTs = NetConvert.doReverseEndian(data.getUint32(12));
      pktCount = NetConvert.doReverseEndian(data.getUint32(16));
      octCount = NetConvert.doReverseEndian(data.getUint32(20));
    } else {
      ssrc = data.getUint32(0);
      ntpHigh = data.getUint32(4);
      ntpLow = data.getUint32(8);
      rtpTs = data.getUint32(12);
      pktCount = data.getUint32(16);
      octCount = data.getUint32(20);
    }

    ntpTimestamp = (Int64(ntpHigh) << 32) | Int64(ntpLow);
    octetCount = Int64(octCount);

    final List<ReceptionReportSample> receptionReports = [];
    int offset = RtcpHeader.headerBytesLength + senderReportSize;
    while (offset < buffer.length) {
      receptionReports.add(ReceptionReportSample.parse(buffer, offset));
      offset += ReceptionReportSample.payloadSize;
    }

    return RtcpSenderReport(
      header: header,
      ssrc: ssrc,
      ntpTimestamp: ntpTimestamp,
      rtpTimestamp: rtpTs,
      packetCount: pktCount,
      octetCount: octetCount,
      receptionReports: receptionReports,
    );
  }

  /// Creates a new RTCP Sender Report.
  RtcpSenderReport({
    required this.header,
    this.ssrc = 0,
    required this.ntpTimestamp,
    this.rtpTimestamp = 0,
    this.packetCount = 0,
    required this.octetCount,
    this.receptionReports = const [],
  }) {
    header.packetType = RtcpReportTypesEnum.sr;
    header.receptionReportCount = receptionReports.length;
    final int len = (senderReportSize +
            receptionReports.length * ReceptionReportSample.payloadSize) ~/
        4;
    header.setLength(len);
  }

  /// Gets the serialised bytes for this Sender Report.
  Uint8List getBytes() {
    int rrCount = receptionReports.length;
    int bufferLength = RtcpHeader.headerBytesLength +
        senderReportSize +
        rrCount * ReceptionReportSample.payloadSize;
    final buffer = Uint8List(bufferLength);
    final data = ByteData.view(buffer.buffer);

    Uint8List headerBytes = header.getBytes();
    buffer.setRange(0, headerBytes.length, headerBytes);

    int payloadIndex = RtcpHeader.headerBytesLength;

    // Extract high and low 32-bit words from Int64 using bitwise operators
    final int ntpHigh = (ntpTimestamp >> 32).toInt();
    final int ntpLow = (ntpTimestamp & Int64(0xFFFFFFFF)).toInt();

    final int octetCountInt = octetCount
        .toInt(); // Assuming octetCount fits in 32-bit int for serialization

    if (Endian.host == Endian.little) {
      data.setUint32(payloadIndex, NetConvert.doReverseEndian(ssrc));
      data.setUint32(payloadIndex + 4, NetConvert.doReverseEndian(ntpHigh));
      data.setUint32(payloadIndex + 8, NetConvert.doReverseEndian(ntpLow));
      data.setUint32(
          payloadIndex + 12, NetConvert.doReverseEndian(rtpTimestamp));
      data.setUint32(
          payloadIndex + 16, NetConvert.doReverseEndian(packetCount));
      data.setUint32(
          payloadIndex + 20, NetConvert.doReverseEndian(octetCountInt));
    } else {
      data.setUint32(payloadIndex, ssrc);
      data.setUint32(payloadIndex + 4, ntpHigh);
      data.setUint32(payloadIndex + 8, ntpLow);
      data.setUint32(payloadIndex + 12, rtpTimestamp);
      data.setUint32(payloadIndex + 16, packetCount);
      data.setUint32(payloadIndex + 20, octetCountInt);
    }

    int bufferIndex = payloadIndex + senderReportSize;
    for (var rr in receptionReports) {
      Uint8List rrBytes = rr.getBytes();
      buffer.setRange(bufferIndex, bufferIndex + rrBytes.length, rrBytes);
      bufferIndex += rrBytes.length;
    }

    return buffer;
  }
}
