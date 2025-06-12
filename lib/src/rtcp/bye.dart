import 'dart:typed_data';
import 'dart:convert'; // For utf8 encoding
import 'rtcp_header.dart'; // Assuming RtcpHeader is in rtcp_header.dart
import 'net_convert.dart'; // Assuming NetConvert is in net_convert.dart

/// Represents an RTCP Goodbye packet as defined in RFC3550.
class RtcpBye {
  static const int ssrcSize = 4;

  RtcpHeader header;
  int ssrc; // SSRC of the leaving participant
  String? reason; // Optional reason for leaving

  /// Creates a new RTCP Goodbye packet from a byte array.
  factory RtcpBye.parse(Uint8List buffer) {
    final header = RtcpHeader.parse(buffer);
    final data = ByteData.view(buffer.buffer, RtcpHeader.headerBytesLength);

    int ssrc = 0;
    if (Endian.host == Endian.little) {
      ssrc = NetConvert.doReverseEndian(data.getUint32(0));
    } else {
      ssrc = data.getUint32(0);
    }

    String? reason;
    if (buffer.length > RtcpHeader.headerBytesLength + ssrcSize) {
      int reasonLength = data.getUint8(ssrcSize);
      reason = utf8.decode(buffer.sublist(
          RtcpHeader.headerBytesLength + ssrcSize + 1,
          RtcpHeader.headerBytesLength + ssrcSize + 1 + reasonLength));
    }

    return RtcpBye(
      header: header,
      ssrc: ssrc,
      reason: reason,
    );
  }

  /// Creates a new RTCP Goodbye packet.
  RtcpBye({
    required this.header,
    this.ssrc = 0,
    this.reason,
  }) {
    header.packetType = RtcpReportTypesEnum.bye;
    final int reasonLength = reason != null ? utf8.encode(reason!).length : 0;
    header.setLength((getPaddedLength(reasonLength) ~/ 4));
  }

  /// Gets the serialised bytes for this Goodbye packet.
  Uint8List getBytes() {
    final reasonBytes = reason != null ? utf8.encode(reason!) : Uint8List(0);
    int reasonLength = reasonBytes.length;

    int bufferLength = RtcpHeader.headerBytesLength + getPaddedLength(reasonLength);
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

    if (reasonLength > 0) {
      buffer[payloadIndex + ssrcSize] = reasonLength;
      buffer.setRange(payloadIndex + ssrcSize + 1, payloadIndex + ssrcSize + 1 + reasonLength, reasonBytes);
    }

    // Add padding if necessary
    int currentLength = payloadIndex + ssrcSize + (reasonLength > 0 ? (1 + reasonLength) : 0);
    while (currentLength % 4 != 0) {
      buffer[currentLength++] = 0;
    }

    return buffer;
  }

  /// The packet has to finish on a 4 byte boundary. This method calculates the minimum
  /// packet length for the Goodbye fields to fit within a 4 byte boundary.
  int getPaddedLength(int reasonLength) {
    // Plus one is for the reason length field.
    if (reasonLength > 0) {
      reasonLength += 1;
    }

    int nonPaddedSize = reasonLength + ssrcSize;

    if (nonPaddedSize % 4 == 0) {
      return nonPaddedSize;
    } else {
      return nonPaddedSize + (4 - (nonPaddedSize % 4));
    }
  }
}