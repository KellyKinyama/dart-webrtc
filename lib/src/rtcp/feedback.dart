import 'dart:typed_data';
import 'rtcp_header.dart'; // For RtcpHeader, RtcpFeedbackTypesEnum, PsfbFeedbackTypesEnum
import 'net_convert.dart'; // For NetConvert

/// Represents an RTCP Feedback Packet.
class RtcpFeedback {
  RtcpHeader header;
  int senderSsrc; // SSRC of packet sender
  int mediaSsrc; // SSRC of media source

  // --- NACK Fields (example for NACK, other feedback types have different FCI) ---
  int? pid; // Packet ID (PID): 16 bits to specify a lost packet, the RTP sequence number of the lost packet.
  int? blp; // Bitmask of following lost packets (BLP): 16 bits

  // --- REMB Fields (example for REMB) ---
  int? uniqueId; // REMB unique identifier
  int? numSsrcs;
  int? bitrateExp; // Bitrate Exponent
  int? bitrateMantissa; // Bits per Second
  List<int>? feedbackSsrcs; // SSRCs for REMB

  /// Creates a new RTCP Feedback Packet from a byte array.
  factory RtcpFeedback.parse(Uint8List buffer) {
    final header = RtcpHeader.parse(buffer);
    final data = ByteData.view(buffer.buffer, RtcpHeader.headerBytesLength);

    int senderSsrc = 0;
    int mediaSsrc = 0;

    if (Endian.host == Endian.little) {
      senderSsrc = NetConvert.doReverseEndian(data.getUint32(0));
      mediaSsrc = NetConvert.doReverseEndian(data.getUint32(4));
    } else {
      senderSsrc = data.getUint32(0);
      mediaSsrc = data.getUint32(4);
    }

    final feedback = RtcpFeedback(
      header: header,
      senderSsrc: senderSsrc,
      mediaSsrc: mediaSsrc,
    );

    // Parse FCI based on feedback message type
    final fciOffset = RtcpHeader.headerBytesLength + 8; // 8 bytes for senderSsrc + mediaSsrc

    if (header.packetType == RtcpReportTypesEnum.rtpfb) {
      if (header.feedbackMessageType == RtcpFeedbackTypesEnum.nack) {
        // Generic NACK (RFC4585)
        // PID and BLP fields
        if (buffer.length >= fciOffset + 4) {
          final fciData = ByteData.view(buffer.buffer, fciOffset);
          if (Endian.host == Endian.little) {
            feedback.pid = NetConvert.doReverseEndian16(fciData.getUint16(0));
            feedback.blp = NetConvert.doReverseEndian16(fciData.getUint16(2));
          } else {
            feedback.pid = fciData.getUint16(0);
            feedback.blp = fciData.getUint16(2);
          }
        }
      } else if (header.feedbackMessageType == RtcpFeedbackTypesEnum.twcc) {
        // This is handled by RTCPTWCCFeedback, which is a specific type of RTCPFeedback
        // For general RTCPFeedback, we might just store raw FCI bytes if we don't parse it fully.
      }
      // Add other RTCPFB types as needed
    } else if (header.packetType == RtcpReportTypesEnum.psfb) {
      if (header.payloadFeedbackMessageType == PsfbFeedbackTypesEnum.pli) {
        // PLI has no FCI
      } else if (header.payloadFeedbackMessageType == PsfbFeedbackTypesEnum.fir) {
        // FIR (Full Intra Request)
        // FCI is a list of pairs (SSRC, Command Sequence Number)
        // Not implemented here, but would follow the pattern
      }
      // Add other PSFB types as needed
    }

    return feedback;
  }

  /// Creates a new RTCP Feedback Packet.
  RtcpFeedback({
    required this.header,
    this.senderSsrc = 0,
    this.mediaSsrc = 0,
    this.pid,
    this.blp,
    this.uniqueId,
    this.numSsrcs,
    this.bitrateExp,
    this.bitrateMantissa,
    this.feedbackSsrcs,
  }) {
    // Set length based on content
    int fciLength = 0;
    if (header.packetType == RtcpReportTypesEnum.rtpfb) {
      if (header.feedbackMessageType == RtcpFeedbackTypesEnum.nack) {
        fciLength = 4; // PID + BLP
      } else if (header.feedbackMessageType == RtcpFeedbackTypesEnum.twcc) {
        // Handled by RTCPTWCCFeedback
        fciLength = 0; // Default for now, specific length determined by TWCC
      }
      // Add other RTCPFB types
    } else if (header.packetType == RtcpReportTypesEnum.psfb) {
      if (header.payloadFeedbackMessageType == PsfbFeedbackTypesEnum.pli) {
        fciLength = 0;
      }
      // Add other PSFB types
    }

    header.setLength(((8 + fciLength) ~/ 4)); // 8 bytes for sender and media SSRC, + FCI
  }

  /// Gets the serialised bytes for this Feedback packet.
  Uint8List getBytes() {
    int fciLength = 0;
    if (header.packetType == RtcpReportTypesEnum.rtpfb) {
      if (header.feedbackMessageType == RtcpFeedbackTypesEnum.nack) {
        fciLength = 4;
      } else if (header.feedbackMessageType == RtcpFeedbackTypesEnum.twcc) {
        // Handled by RTCPTWCCFeedback. This generic method won't create a full TWCC packet.
        throw UnsupportedError("Use RTCPTWCCFeedback.getBytes() for TWCC packets.");
      }
    } else if (header.packetType == RtcpReportTypesEnum.psfb) {
      if (header.payloadFeedbackMessageType == PsfbFeedbackTypesEnum.pli) {
        fciLength = 0;
      }
    }

    final buffer = Uint8List(RtcpHeader.headerBytesLength + 8 + fciLength);
    final data = ByteData.view(buffer.buffer);

    Uint8List headerBytes = header.getBytes();
    buffer.setRange(0, headerBytes.length, headerBytes);

    int payloadIndex = RtcpHeader.headerBytesLength;

    if (Endian.host == Endian.little) {
      data.setUint32(payloadIndex, NetConvert.doReverseEndian(senderSsrc));
      data.setUint32(payloadIndex + 4, NetConvert.doReverseEndian(mediaSsrc));
    } else {
      data.setUint32(payloadIndex, senderSsrc);
      data.setUint32(payloadIndex + 4, mediaSsrc);
    }

    // Write FCI based on type
    final fciOffset = payloadIndex + 8;
    if (header.packetType == RtcpReportTypesEnum.rtpfb) {
      if (header.feedbackMessageType == RtcpFeedbackTypesEnum.nack) {
        if (pid != null && blp != null) {
          if (Endian.host == Endian.little) {
            data.setUint16(fciOffset, NetConvert.doReverseEndian16(pid!));
            data.setUint16(fciOffset + 2, NetConvert.doReverseEndian16(blp!));
          } else {
            data.setUint16(fciOffset, pid!);
            data.setUint16(fciOffset + 2, blp!);
          }
        }
      }
    }
    return buffer;
  }
}