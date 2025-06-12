import 'dart:typed_data';
import 'net_convert.dart'; // Ensure this file is available and correct

/// Enum for RTCP Report Types as defined in RFC3550.
enum RtcpReportTypesEnum {
  /// Sender Report.
  sr(200),

  /// Receiver Report.
  rr(201),

  /// Source Description.
  sdes(202),

  /// Goodbye.
  bye(203),

  /// Application-defined.
  app(204),

  /// Transport-Layer Feedback (RTPFB).
  rtpfb(205),

  /// Payload-Specific Feedback (PSFB).
  psfb(206);

  final int value;
  const RtcpReportTypesEnum(this.value);

  static RtcpReportTypesEnum? fromInt(int value) {
    for (var type in RtcpReportTypesEnum.values) {
      if (type.value == value) {
        return type;
      }
    }
    return null;
  }
}

/// The different types of RTCP Feedback Message Types. (RFC4585)
/// https://tools.ietf.org/html/rfc4585#page-35
enum RtcpFeedbackTypesEnum {
  unassigned(0),
  nack(1), // Generic NACK Generic negative acknowledgment [RFC4585]
  tmmbr(3), // Temporary Maximum Media Stream Bit Rate Request [RFC5104]
  tmmbn(4), // Temporary Maximum Media Stream Bit Rate Notification [RFC5104]
  rtcpSrReq(5), // RTCP Rapid Resynchronisation Request [RFC6051]
  rams(6), // Rapid Acquisition of Multicast Sessions [RFC6285]
  tllei(7), // Transport-Layer Third-Party Loss Early Indication [RFC6642]
  rtcpEcnFb(8), // RTCP ECN Feedback [RFC6679]
  pauseResume(9), // Media Pause/Resume [RFC7728]
  dbi(10), // Delay Budget Information (DBI) [3GPP TS 26.114 v16.3.0][Ozgur_Oyman]
  twcc(15); // Transport-Wide Congestion Control [RFC8888]

  final int value;
  const RtcpFeedbackTypesEnum(this.value);

  static RtcpFeedbackTypesEnum? fromInt(int value) {
    for (var type in RtcpFeedbackTypesEnum.values) {
      if (type.value == value) {
        return type;
      }
    }
    return null;
  }
}

/// The different types of Payload Specific Feedback Message Types. (RFC4585)
/// https://tools.ietf.org/html/rfc4585#page-35
enum PsfbFeedbackTypesEnum {
  unassigned(0),
  pli(1), // Picture Loss Indication [RFC4585]
  sli(2), // Slice Loss Indication [RFC4585]
  rpsi(3), // Reference Picture Selection Indication [RFC4585]
  fir(4), // Full Intra Request Command [RFC5104]
  tstr(5), // Temporal-Spatial Trade-off Request [RFC5104]
  tstn(6), // Temporal-Spatial Trade-off Notification [RFC5104]
  vbcm(7), // Video Back Channel Message [RFC5104]
  pslei(8), // Payload-Specific Third-Party Loss Early Indication [RFC6642]
  roi(9), // Video region-of-interest (ROI) [3GPP TS 26.114 v16.3.0][Ozgur_Oyman]
  lrr(10), // Layer Refresh Request Command [RFC-ietf-avtext-lrr-07]
  afb(15); // Application Layer Feedback [RFC4585]

  final int value;
  const PsfbFeedbackTypesEnum(this.value);

  static PsfbFeedbackTypesEnum? fromInt(int value) {
    for (var type in PsfbFeedbackTypesEnum.values) {
      if (type.value == value) {
        return type;
      }
    }
    return null;
  }
}

/// Represents an RTCP Header as defined in RFC3550.
class RtcpHeader {
  static const int headerBytesLength = 4;

  int version;
  bool paddingFlag;
  int receptionReportCount; // or FeedbackMessageType/PayloadFeedbackMessageType
  RtcpReportTypesEnum packetType;
  int length; // In 32-bit words minus one
  RtcpFeedbackTypesEnum? feedbackMessageType;
  PsfbFeedbackTypesEnum? payloadFeedbackMessageType;

  /// Creates a new RTCP Header from a byte array.
  factory RtcpHeader.parse(Uint8List buffer) {
    if (buffer.length < headerBytesLength) {
      throw ArgumentError('Buffer too short for RTCP header.');
    }

    final data = ByteData.view(buffer.buffer);
    int firstWord = 0;

    if (Endian.host == Endian.little) {
      firstWord = NetConvert.doReverseEndian(data.getUint32(0));
    } else {
      firstWord = data.getUint32(0);
    }

    int version = (firstWord >> 30) & 0x03;
    bool paddingFlag = ((firstWord >> 29) & 0x01) == 1;
    int rcOrFmt = (firstWord >> 24) & 0x1F; // RC for SR/RR, or FMT for FB
    RtcpReportTypesEnum packetType =
        RtcpReportTypesEnum.fromInt((firstWord >> 16) & 0xFF)!;
    int length = firstWord & 0xFFFF;

    int receptionReportCount = 0;
    RtcpFeedbackTypesEnum? feedbackMessageType;
    PsfbFeedbackTypesEnum? payloadFeedbackMessageType;

    if (_isFeedbackReportType(packetType)) {
      if (packetType == RtcpReportTypesEnum.rtpfb) {
        feedbackMessageType = RtcpFeedbackTypesEnum.fromInt(rcOrFmt);
      } else {
        payloadFeedbackMessageType = PsfbFeedbackTypesEnum.fromInt(rcOrFmt);
      }
    } else {
      receptionReportCount = rcOrFmt;
    }

    return RtcpHeader._(
      version: version,
      paddingFlag: paddingFlag,
      receptionReportCount: receptionReportCount,
      packetType: packetType,
      length: length,
      feedbackMessageType: feedbackMessageType,
      payloadFeedbackMessageType: payloadFeedbackMessageType,
    );
  }

  // Private constructor for internal use by the factory.
  RtcpHeader._({
    this.version = 2,
    this.paddingFlag = false,
    this.receptionReportCount = 0,
    required this.packetType,
    this.length = 0,
    this.feedbackMessageType,
    this.payloadFeedbackMessageType,
  });

  /// Creates a new RTCP Header.
  // This public constructor still exists for creating new headers, not parsing.
  RtcpHeader({
    this.version = 2,
    this.paddingFlag = false,
    this.receptionReportCount = 0,
    required this.packetType,
    this.length = 0,
    this.feedbackMessageType,
    this.payloadFeedbackMessageType,
  });

  static bool _isFeedbackReportType(RtcpReportTypesEnum packetType) {
    return packetType == RtcpReportTypesEnum.rtpfb ||
        packetType == RtcpReportTypesEnum.psfb;
  }

  /// Gets the serialised bytes for this RTCP Header.
  Uint8List getBytes() {
    final buffer = Uint8List(headerBytesLength);
    final data = ByteData.view(buffer.buffer);

    int firstWord = 0;
    firstWord |= (version & 0x03) << 30;
    if (paddingFlag) {
      firstWord |= 1 << 29;
    }
    firstWord |= (packetType.value & 0xFF) << 16;
    firstWord |= (length & 0xFFFF);

    if (_isFeedbackReportType(packetType)) {
      if (packetType == RtcpReportTypesEnum.rtpfb) {
        firstWord |= (feedbackMessageType?.value ?? 0) << 24;
      } else {
        firstWord |= (payloadFeedbackMessageType?.value ?? 0) << 24;
      }
    } else {
      firstWord |= (receptionReportCount & 0x1F) << 24;
    }

    if (Endian.host == Endian.little) {
      data.setUint32(0, NetConvert.doReverseEndian(firstWord));
    } else {
      data.setUint32(0, firstWord);
    }

    return buffer;
  }

  void setLength(int length) {
    this.length = length;
  }
}
