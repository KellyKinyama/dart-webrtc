import 'dart:typed_data';
import 'dart:math';

import 'net_convert.dart'; // Ensure this file is available and correct

/// <summary>
/// NTP timestamp in sender report packet, in 32bit.
/// </summary>
class ReceivedSRTimestamp {
  /// NTP timestamp in sender report packet, in 32bit.
  int ntp;

  /// RTP timestamp in sender report packet.
  int rtp;

  ReceivedSRTimestamp({this.ntp = 0, this.rtp = 0});
}

/// Represents a point in time sample for a reception report.
class ReceptionReportSample {
  static const int payloadSize = 24;
  static const int rtpSeqMod = 1 << 16;
  static const int maxMisorder = 100;
  static const int minSequential = 2;

  /// Data source being reported.
  int ssrc;

  /// Fraction lost since last SR/RR.
  int fractionLost;

  /// Cumulative number of packets lost (signed!).
  int packetsLost;

  /// Extended last sequence number received.
  int extendedHighestSequenceNumber;

  /// Interarrival jitter.
  int interarrivalJitter;

  /// Last SR (LSR): NTP timestamp of the last sender report received from SSRC.
  int lastSr;

  /// Delay since last SR (DLSR): Delay in units of 1/65536 seconds between receiving the last SR from SSRC and sending this report.
  int delaySinceLastSr;

  int _cycles = 0;
  int _maxSeq = 0;
  int _badSeq = 0;
  int _received = 0;
  int _expectedPrior = 0;
  int _receivedPrior = 0;
  int _jitter = 0;

  ReceptionReportSample(
      {this.ssrc = 0,
      this.fractionLost = 0,
      this.packetsLost = 0,
      this.extendedHighestSequenceNumber = 0,
      this.interarrivalJitter = 0,
      this.lastSr = 0,
      this.delaySinceLastSr = 0});

  /// Creates a new ReceptionReportSample from a byte array.
  factory ReceptionReportSample.parse(Uint8List buffer, int offset) {
    final data = ByteData.view(buffer.buffer, offset, payloadSize);

    int ssrc = 0;
    int fractionLost = 0;
    int packetsLost = 0;
    int extendedHighestSequenceNumber = 0;
    int interarrivalJitter = 0;
    int lastSr = 0;
    int delaySinceLastSr = 0;

    if (Endian.host == Endian.little) {
      ssrc = NetConvert.doReverseEndian(data.getUint32(0));
      fractionLost = data.getUint8(4);
      packetsLost = (data.getUint8(5) << 16) |
          (data.getUint8(6) << 8) |
          data.getUint8(7); // 24-bit signed
      if ((packetsLost & 0x800000) != 0) {
        // If negative
        packetsLost = packetsLost | ~0xFFFFFF; // Sign extend
      }
      extendedHighestSequenceNumber =
          NetConvert.doReverseEndian(data.getUint32(8));
      interarrivalJitter = NetConvert.doReverseEndian(data.getUint32(12));
      lastSr = NetConvert.doReverseEndian(data.getUint32(16));
      delaySinceLastSr = NetConvert.doReverseEndian(data.getUint32(20));
    } else {
      ssrc = data.getUint32(0);
      fractionLost = data.getUint8(4);
      packetsLost =
          (data.getUint8(5) << 16) | (data.getUint8(6) << 8) | data.getUint8(7);
      if ((packetsLost & 0x800000) != 0) {
        packetsLost = packetsLost | ~0xFFFFFF;
      }
      extendedHighestSequenceNumber = data.getUint32(8);
      interarrivalJitter = data.getUint32(12);
      lastSr = data.getUint32(16);
      delaySinceLastSr = data.getUint32(20);
    }

    return ReceptionReportSample(
      ssrc: ssrc,
      fractionLost: fractionLost,
      packetsLost: packetsLost,
      extendedHighestSequenceNumber: extendedHighestSequenceNumber,
      interarrivalJitter: interarrivalJitter,
      lastSr: lastSr,
      delaySinceLastSr: delaySinceLastSr,
    );
  }

  /// Gets the serialised bytes for this Reception Report Sample.
  Uint8List getBytes() {
    final buffer = Uint8List(payloadSize);
    final data = ByteData.view(buffer.buffer);

    if (Endian.host == Endian.little) {
      data.setUint32(0, NetConvert.doReverseEndian(ssrc));
      data.setUint8(4, fractionLost);
      data.setUint8(5, (packetsLost >> 16) & 0xFF);
      data.setUint8(6, (packetsLost >> 8) & 0xFF);
      data.setUint8(7, packetsLost & 0xFF);
      data.setUint32(
          8, NetConvert.doReverseEndian(extendedHighestSequenceNumber));
      data.setUint32(12, NetConvert.doReverseEndian(interarrivalJitter));
      data.setUint32(16, NetConvert.doReverseEndian(lastSr));
      data.setUint32(20, NetConvert.doReverseEndian(delaySinceLastSr));
    } else {
      data.setUint32(0, ssrc);
      data.setUint8(4, fractionLost);
      data.setUint8(5, (packetsLost >> 16) & 0xFF);
      data.setUint8(6, (packetsLost >> 8) & 0xFF);
      data.setUint8(7, packetsLost & 0xFF);
      data.setUint32(8, extendedHighestSequenceNumber);
      data.setUint32(12, interarrivalJitter);
      data.setUint32(16, lastSr);
      data.setUint32(20, delaySinceLastSr);
    }

    return buffer;
  }

  /// Updates the reception report metrics based on a new RTP sequence number and arrival time.
  /// This method is a translation of the `process_rtp_packet` function often found in RTCP implementations.
  bool update(int seq, DateTime arrivalTime, int rtpTimestamp) {
    int extendedSeq = 0;
    if (_received == 0) {
      initSeq(seq);
    }

    int udelta = seq - _maxSeq;
    if (udelta < 0) {
      // Sequence number wrapped around
      if (-udelta >= rtpSeqMod ~/ 2) {
        // Sequence number wrapped - count another 64K cycle.
        _cycles += rtpSeqMod;
      }
    } else if (udelta > maxMisorder) {
      // The sequence number made a very large jump
      if (seq == _badSeq) {
        // Two sequential packets -- assume that the other side
        // restarted without telling us so just re-sync
        // (i.e., pretend this was the first packet).
        initSeq(seq);
      } else {
        _badSeq = (seq + 1) & (rtpSeqMod - 1);
        return true;
      }
    } else {
      // Duplicate or reordered packet
    }

    _maxSeq = seq;
    _received++;
    extendedSeq = _cycles + seq;
    extendedHighestSequenceNumber = extendedSeq;

    // Jitter calculation as per RFC3550 A.8.
    // D(i,j) = (Rj - Ri) - (Sj - Si) = (Rj - Sj) - (Ri - Si)
    // J = J + (|D(i,j)| - J) / 16
    if (_received > 1) {
      final double transit =
          arrivalTime.microsecondsSinceEpoch / 1000.0 - rtpTimestamp;
      final double d = transit -
          ((_receivedSRTimestamp?.ntp ?? 0) / 65536.0 -
              (_receivedSRTimestamp?.rtp ?? 0));
      _jitter += (d.abs().toInt() - _jitter) ~/ 16;
      interarrivalJitter = _jitter;
    }

    int expected = extendedSeq - _expectedPrior;
    int lost = expected - _received;
    packetsLost = lost;

    int expectedInterval = expected - _expectedPrior;
    int receivedInterval = _received - _receivedPrior;
    int lostInterval = expectedInterval - receivedInterval;
    double fraction = 0;
    if (expectedInterval == 0 || lostInterval <= 0) {
      fraction = 0;
    } else {
      fraction = lostInterval / expectedInterval.toDouble();
    }
    fractionLost = (fraction * 256).toInt();

    _expectedPrior = expected;
    _receivedPrior = _received;

    return false;
  }

  void initSeq(int seq) {
    _maxSeq = seq;
    _cycles = 0;
    _badSeq = rtpSeqMod + 1; // Corrected to use rtpSeqMod
    _received = 0;
    _expectedPrior = 0;
    _receivedPrior = 0;
    _jitter = 0;
  }

  ReceivedSRTimestamp? _receivedSRTimestamp;

  void updateReceivedSRTimestamp(ReceivedSRTimestamp timestamp) {
    _receivedSRTimestamp = timestamp;
  }
}
