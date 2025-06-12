import 'dart:typed_data';
import 'rtcp_header.dart'; // For RtcpHeader, RtcpReportTypesEnum
import 'sender_report.dart'; // For RtcpSenderReport
import 'receiver_report.dart'; // For RtcpReceiverReport
import 'sdes_report.dart'; // For RtcpSdesReport
import 'bye.dart'; // For RtcpBye
import 'feedback.dart'; // For RtcpFeedback
import 'twcc_feedback.dart'; // For RtcpTwccFeedback

/// Represents an RTCP compound packet consisting of 1 or more
/// RTCP packets combined together in a single buffer.
class RtcpCompoundPacket {
  RtcpSenderReport? senderReport;
  RtcpReceiverReport? receiverReport;
  RtcpSdesReport? sDesReport;
  RtcpBye? bye;
  RtcpFeedback? feedback;
  RtcpTwccFeedback? twccFeedback;

  RtcpCompoundPacket();

  /// Creates a new RTCP Compound Packet from a byte array.
  factory RtcpCompoundPacket.parse(Uint8List buffer) {
    final compoundPacket = RtcpCompoundPacket();
    int offset = 0;

    while (offset < buffer.length) {
      if (buffer.length - offset < RtcpHeader.headerBytesLength) {
        // Not enough bytes for a header, break
        break;
      }
      final header = RtcpHeader.parse(Uint8List.fromList(
          buffer.sublist(offset, offset + RtcpHeader.headerBytesLength)));
      final int packetLengthBytes = (header.length + 1) * 4;

      if (offset + packetLengthBytes > buffer.length) {
        // Packet extends beyond buffer boundary, likely malformed or incomplete
        break;
      }

      final Uint8List packetBuffer = Uint8List.fromList(
          buffer.sublist(offset, offset + packetLengthBytes));

      switch (header.packetType) {
        case RtcpReportTypesEnum.sr:
          compoundPacket.senderReport = RtcpSenderReport.parse(packetBuffer);
          break;
        case RtcpReportTypesEnum.rr:
          compoundPacket.receiverReport =
              RtcpReceiverReport.parse(packetBuffer);
          break;
        case RtcpReportTypesEnum.sdes:
          compoundPacket.sDesReport = RtcpSdesReport.parse(packetBuffer);
          break;
        case RtcpReportTypesEnum.bye:
          compoundPacket.bye = RtcpBye.parse(packetBuffer);
          break;
        case RtcpReportTypesEnum.rtpfb:
          if (header.feedbackMessageType == RtcpFeedbackTypesEnum.twcc) {
            compoundPacket.twccFeedback = RtcpTwccFeedback.parse(packetBuffer);
          } else {
            compoundPacket.feedback = RtcpFeedback.parse(packetBuffer);
          }
          break;
        case RtcpReportTypesEnum.psfb:
          compoundPacket.feedback = RtcpFeedback.parse(packetBuffer);
          break;
        default:
          // Unrecognised packet type, log and skip or throw error
          print(
              'RTCPCompoundPacket did not recognise packet type ID ${header.packetType.value}');
          break;
      }
      offset += packetLengthBytes;
    }

    return compoundPacket;
  }

  /// Gets the serialised bytes for this RTCP Compound Packet.
  Uint8List getBytes() {
    final List<Uint8List> packetBytes = [];

    if (senderReport != null) packetBytes.add(senderReport!.getBytes());
    if (receiverReport != null) packetBytes.add(receiverReport!.getBytes());
    if (sDesReport != null) packetBytes.add(sDesReport!.getBytes());
    if (bye != null) packetBytes.add(bye!.getBytes());
    if (twccFeedback != null) packetBytes.add(twccFeedback!.getBytes());
    if (feedback != null && twccFeedback == null)
      packetBytes.add(feedback!.getBytes());

    int totalLength = packetBytes.fold(0, (sum, bytes) => sum + bytes.length);
    final Uint8List compoundBuffer = Uint8List(totalLength);
    int offset = 0;
    for (var bytes in packetBytes) {
      compoundBuffer.setRange(offset, offset + bytes.length, bytes);
      offset += bytes.length;
    }

    return compoundBuffer;
  }
}
