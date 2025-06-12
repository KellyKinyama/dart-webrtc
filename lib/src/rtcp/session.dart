import 'dart:typed_data';
import 'dart:async';
import 'dart:math';

import 'package:fixnum/fixnum.dart';

import 'bye.dart';
import 'net_convert.dart'; // For NetConvert.dateTimeToNtpTimestamp
import 'compound_packet.dart'; // For RtcpCompoundPacket
import 'rtcp_header.dart'; // For RtcpReportTypesEnum
import 'receiver_report.dart'; // For RtcpReceiverReport
import 'sdes_report.dart';
import 'sender_report.dart'; // For RtcpSenderReport
import 'reception_report.dart'; // For ReceptionReportSample, ReceivedSRTimestamp

/// Represents an RTCP session intended to be used in conjunction with an
/// RTP session. This class needs to get notified of all RTP sends and receives
/// and will take care of RTCP reporting.
class RtcpSession {
  // RTCP Design Decisions (from C# comments, RFC3550 Section 6.2):
  static const int minReportPeriodMs = 5000; // 5 seconds
  static const int initialReportDelayMs =
      2500; // 2.5 seconds (0.5 * minReportPeriod)
  static const double randomizationFactor =
      0.5; // [0.5 * interval, 1.5 * interval]
  static const int participantTimeoutMultiplier = 5; // 5 x minReportPeriod

  int ssrc;
  Function(Uint8List packet)? onSendRtcp; // Callback to send RTCP packet
  // A map to store reception reports for each SSRC
  final Map<int, ReceptionReportSample> _receptionReports = {};
  // A map to store the last received SR NTP timestamp for each SSRC
  final Map<int, ReceivedSRTimestamp> _receivedSrTimestamps = {};

  Timer? _reportTimer;
  DateTime _lastRtcpSentAt = DateTime.now().toUtc();
  DateTime _lastRtpReceivedAt = DateTime.now().toUtc();
  int _senderPacketCount = 0;
  Int64 _senderOctetCount = Int64(0); // Using Int64 for potential larger values
  int _senderRtpTimestamp = 0;

  RtcpSession({required this.ssrc, this.onSendRtcp}) {
    _startReportTimer();
  }

  /// Notifies the RTCP session of an outgoing RTP packet.
  void notifyRtpSend(
      int ssrc, int sequenceNumber, int rtpTimestamp, int packetLength) {
    _senderPacketCount++;
    _senderOctetCount += Int64(packetLength);
    _senderRtpTimestamp = rtpTimestamp;

    // Update own sender report
    // In a real scenario, you would manage your own sender report
    // and potentially send it immediately if conditions are met.
  }

  /// Notifies the RTCP session of an incoming RTP packet.
  void notifyRtpReceive(
      int ssrc, int sequenceNumber, int rtpTimestamp, DateTime arrivalTime) {
    if (!_receptionReports.containsKey(ssrc)) {
      _receptionReports[ssrc] = ReceptionReportSample(ssrc: ssrc);
    }
    _receptionReports[ssrc]!.update(sequenceNumber, arrivalTime, rtpTimestamp);
    _lastRtpReceivedAt = arrivalTime;
  }

  /// Notifies the RTCP session of an incoming SR (Sender Report) packet.
  void notifySrReceive(int ssrc, Int64 ntpTimestamp, int rtpTimestamp) {
    // Corrected: Use bitwise AND to get the lower 32 bits from Int64.
    // The C# ReceivedSRTimestamp.NTP was a uint (32-bit).
    _receivedSrTimestamps[ssrc] = ReceivedSRTimestamp(
        ntp: (ntpTimestamp & Int64(0xFFFFFFFF)).toInt(), rtp: rtpTimestamp);
    if (_receptionReports.containsKey(ssrc)) {
      _receptionReports[ssrc]!
          .updateReceivedSRTimestamp(_receivedSrTimestamps[ssrc]!);
    }
  }

  void _startReportTimer() {
    _reportTimer?.cancel();
    _reportTimer = Timer.periodic(
      Duration(milliseconds: _calculateNextReportInterval()),
      (timer) {
        _sendRtcpReport();
      },
    );
  }

  int _calculateNextReportInterval() {
    // RFC3550: 6.2 RTCP Transmission Interval
    // Randomization factor applied to report intervals to prevent synchronization
    final Random random = Random();
    final double randomFactor =
        randomizationFactor + random.nextDouble() * (1.0 - randomizationFactor);
    return (minReportPeriodMs * randomFactor).toInt();
  }

  void _sendRtcpReport() {
    // Create a compound RTCP packet
    final compoundPacket = RtcpCompoundPacket();
    final now = DateTime.now().toUtc();

    // Determine if a Sender Report or Receiver Report should be sent
    if (_senderPacketCount > 0) {
      // Send Sender Report
      compoundPacket.senderReport = RtcpSenderReport(
        header: RtcpHeader(packetType: RtcpReportTypesEnum.sr),
        ssrc: ssrc,
        ntpTimestamp: NetConvert.dateTimeToNtpTimestamp(now),
        rtpTimestamp: _senderRtpTimestamp,
        packetCount: _senderPacketCount,
        octetCount: _senderOctetCount,
        receptionReports: _receptionReports.values.toList(),
      );
    } else {
      // Send Receiver Report
      compoundPacket.receiverReport = RtcpReceiverReport(
        header: RtcpHeader(packetType: RtcpReportTypesEnum.rr),
        ssrc: ssrc,
        receptionReports: _receptionReports.values.toList(),
      );
    }

    // Always include an SDES report with CNAME (mandatory for initial and periodic reports)
    compoundPacket.sDesReport = RtcpSdesReport(
      header: RtcpHeader(packetType: RtcpReportTypesEnum.sdes),
      ssrc: ssrc,
      cname: 'sipsorcery-dart-rtcp@example.com', // Replace with actual CNAME
    );

    final Uint8List packet = compoundPacket.getBytes();
    onSendRtcp?.call(packet);
    _lastRtcpSentAt = now;
  }

  /// Sends an RTCP BYE packet.
  void sendBye({String? reason}) {
    final byePacket = RtcpBye(
      header: RtcpHeader(packetType: RtcpReportTypesEnum.bye),
      ssrc: ssrc,
      reason: reason,
    );
    final compoundPacket = RtcpCompoundPacket()
      ..bye = byePacket
      ..sDesReport = RtcpSdesReport(
        // BYE must be combined with SDES
        header: RtcpHeader(packetType: RtcpReportTypesEnum.sdes),
        ssrc: ssrc,
        cname: 'sipsorcery-dart-rtcp@example.com',
      );
    onSendRtcp?.call(compoundPacket.getBytes());
    _reportTimer?.cancel();
  }

  /// Disposes the RTCP session.
  void dispose() {
    _reportTimer?.cancel();
  }
}
