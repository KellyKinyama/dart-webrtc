import 'dart:typed_data';
import 'rtcp_header.dart'; // For RtcpHeader, RtcpFeedbackTypesEnum
import 'net_convert.dart'; // For NetConvert

/// Enum for TWCC Packet Status Type.
enum TwccPacketStatusType {
  notReceived(0),
  receivedSmallDelta(1),
  receivedLargeDelta(2),
  reserved(3);

  final int value;
  const TwccPacketStatusType(this.value);
}

/// Represents the status of a single RTP packet in a TWCC feedback message.
class TwccPacketStatus {
  /// The RTP sequence number for this packet.
  int sequenceNumber;

  /// The reception status.
  TwccPacketStatusType status;

  /// The receive delta for the packet if received (in microseconds).
  int? receiveDelta;

  TwccPacketStatus({
    required this.sequenceNumber,
    required this.status,
    this.receiveDelta,
  });
}

/// Transport Wide Congestion Control (TWCC) Feedback Packet.
class RtcpTwccFeedback {
  RtcpHeader header;
  int senderSsrc; // SSRC of packet sender
  int mediaSsrc; // SSRC of media source
  int baseSequenceNumber;
  int packetStatusCount;
  int referenceTime; // 24 bits, multiplied by 64ms
  int feedbackPacketCount; // 8 bits
  List<TwccPacketStatus> packetStatuses;

  /// Creates a new RTCP TWCC Feedback Packet from a byte array.
  factory RtcpTwccFeedback.parse(Uint8List buffer) {
    final header = RtcpHeader.parse(buffer);
    if (header.packetType != RtcpReportTypesEnum.rtpfb ||
        header.feedbackMessageType != RtcpFeedbackTypesEnum.twcc) {
      throw ArgumentError('Invalid packet type for TWCC Feedback.');
    }

    final data = ByteData.view(buffer.buffer, RtcpHeader.headerBytesLength);

    int senderSsrc = 0;
    int mediaSsrc = 0;
    int baseSequenceNumber = 0;
    int packetStatusCount = 0;
    int referenceTime = 0;
    int feedbackPacketCount = 0;

    if (Endian.host == Endian.little) {
      senderSsrc = NetConvert.doReverseEndian(data.getUint32(0));
      mediaSsrc = NetConvert.doReverseEndian(data.getUint32(4));
      baseSequenceNumber = NetConvert.doReverseEndian16(data.getUint16(8));
      packetStatusCount = NetConvert.doReverseEndian16(data.getUint16(10));
      referenceTime = NetConvert.doReverseEndian((data.getUint32(12) >> 8) & 0xFFFFFF); // 24 bits
      feedbackPacketCount = data.getUint8(15); // 8 bits
    } else {
      senderSsrc = data.getUint32(0);
      mediaSsrc = data.getUint32(4);
      baseSequenceNumber = data.getUint16(8);
      packetStatusCount = data.getUint16(10);
      referenceTime = (data.getUint32(12) >> 8) & 0xFFFFFF;
      feedbackPacketCount = data.getUint8(15);
    }

    final List<TwccPacketStatus> packetStatuses = [];
    int offset = RtcpHeader.headerBytesLength + 16; // Header + common TWCC fields

    // Parse packet status chunks and receive deltas
    // This is a complex part of TWCC feedback (RFC8888 Section 4.2).
    // The C# code's parsing for TWCC looks like it's doing a simplified parsing
    // or relies on external logic for full chunk interpretation.
    // For a complete implementation, this section would need careful parsing
    // of the different chunk formats (Type 1, Type 2, Run Length, Status Vector).
    // The provided C# snippets only show basic ReadUInt32/ReadUInt16.

    // A placeholder for now, actual implementation would require detailed RFC8888 parsing.
    // The parsing logic in the C# file implies iterating through the chunks and deltas.
    // This will depend on the exact chunk types and their encoding.

    return RtcpTwccFeedback(
      header: header,
      senderSsrc: senderSsrc,
      mediaSsrc: mediaSsrc,
      baseSequenceNumber: baseSequenceNumber,
      packetStatusCount: packetStatusCount,
      referenceTime: referenceTime,
      feedbackPacketCount: feedbackPacketCount,
      packetStatuses: packetStatuses, // This list would be populated by parsing chunks
    );
  }

  /// Creates a new RTCP TWCC Feedback Packet.
  RtcpTwccFeedback({
    required this.header,
    this.senderSsrc = 0,
    this.mediaSsrc = 0,
    this.baseSequenceNumber = 0,
    this.packetStatusCount = 0,
    this.referenceTime = 0,
    this.feedbackPacketCount = 0,
    this.packetStatuses = const [],
  }) {
    header.packetType = RtcpReportTypesEnum.rtpfb;
    header.feedbackMessageType = RtcpFeedbackTypesEnum.twcc;
    // Calculate length based on actual packet statuses and deltas
    // This is highly dependent on the encoding of packet statuses and deltas,
    // which can be run length or status vector chunks.
    // For simplicity, I'll calculate a minimal length here, but a real implementation
    // would need to iterate through packetStatuses and determine the chunk encoding.
    int estimatedFciLength = 12; // Base TWCC fields
    // Add length for packet status chunks and receive deltas
    // This part is complex and needs a dedicated encoder for TWCC chunks.
    // For now, leaving it as a placeholder.
    // Each packet status chunk can be 2 bytes (short delta) or 3 bytes (long delta) or run length
    // Each delta can be 1 or 2 bytes.

    // A more accurate length calculation would involve iterating through packetStatuses
    // and determining the encoded size of chunks and deltas.
    // For a basic example, if each status is a "ReceivedSmallDelta" with a 1-byte delta,
    // it would be `packetStatusCount` * (chunk_overhead + delta_size).
    // RFC 8888 Section 6.2 "Transmission Format" describes this.
    // Since the C# code didn't explicitly show this encoding, I'll make a simplifying assumption
    // for the length calculation, which might not be entirely accurate without the full encoding logic.
    estimatedFciLength += (packetStatuses.length * 2); // Very rough estimate for chunks/deltas

    header.setLength(((8 + estimatedFciLength) ~/ 4)); // 8 bytes for sender and media SSRC
  }

  /// Gets the serialised bytes for this TWCC Feedback packet.
  Uint8List getBytes() {
    // This method is significantly more complex due to TWCC chunk encoding.
    // It requires implementing the logic for encoding packet status chunks (run length or status vector)
    // and receive deltas (1-byte or 2-byte).
    // The provided C# file's GetBytes() method for RTCPTWCCFeedback was not available in the snippets,
    // so I will provide a basic structure, but the chunk encoding logic will be a placeholder.

    // RFC 8888, Section 4.2 defines the format.
    // The packet statuses need to be grouped into chunks.

    final buffer = Uint8List(RtcpHeader.headerBytesLength + header.length * 4);
    final data = ByteData.view(buffer.buffer);

    Uint8List headerBytes = header.getBytes();
    buffer.setRange(0, headerBytes.length, headerBytes);

    int payloadIndex = RtcpHeader.headerBytesLength;

    if (Endian.host == Endian.little) {
      data.setUint32(payloadIndex, NetConvert.doReverseEndian(senderSsrc));
      data.setUint32(payloadIndex + 4, NetConvert.doReverseEndian(mediaSsrc));
      data.setUint16(payloadIndex + 8, NetConvert.doReverseEndian16(baseSequenceNumber));
      data.setUint16(payloadIndex + 10, NetConvert.doReverseEndian16(packetStatusCount));
      data.setUint32(payloadIndex + 12, (NetConvert.doReverseEndian(referenceTime << 8)) | (feedbackPacketCount & 0xFF));
    } else {
      data.setUint32(payloadIndex, senderSsrc);
      data.setUint32(payloadIndex + 4, mediaSsrc);
      data.setUint16(payloadIndex + 8, baseSequenceNumber);
      data.setUint16(payloadIndex + 10, packetStatusCount);
      data.setUint32(payloadIndex + 12, (referenceTime << 8) | (feedbackPacketCount & 0xFF));
    }

    int currentOffset = payloadIndex + 16;

    // --- Placeholder for Packet Status Chunks and Receive Deltas Encoding ---
    // This section would involve complex logic to encode the List<TwccPacketStatus>
    // into appropriate TWCC chunks (e.g., Type 1, Type 2, Run Length, Status Vector)
    // and then append the receive deltas.
    // Example:
    // for (var status in packetStatuses) {
    //   // Encode status and delta into buffer
    //   // This would involve choosing the right chunk type based on consecutive statuses
    //   // and then writing the delta.
    // }
    // -----------------------------------------------------------------------

    return buffer;
  }
}