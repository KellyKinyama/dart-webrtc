import 'dart:typed_data';

/// PacketType specifies the type of an RTCP packet
/// RTCP packet types registered with IANA. See: https://www.iana.org/assignments/rtp-parameters/rtp-parameters.xhtml#rtp-parameters-4
enum PacketType {
  Unsupported(0),
  SenderReport(200), // RFC 3550, 6.4.1
  ReceiverReport(201), // RFC 3550, 6.4.2
  SourceDescription(202), // RFC 3550, 6.5
  Goodbye(203), // RFC 3550, 6.6
  ApplicationDefined(204), // RFC 3550, 6.7 (unimplemented)
  TransportSpecificFeedback(205), // RFC 4585, 6051
  PayloadSpecificFeedback(206), // RFC 4585, 6.3
  ExtendedReport(207); // RFC 3611

  const PacketType(this.value);
  final int value;

  factory PacketType.fromInt(int key) {
    return values.firstWhere((element) => element.value == key);
  }
}

/// Transport and Payload specific feedback messages overload the count field to act as a message type. those are listed here
const FORMAT_SLI = 2;

/// Transport and Payload specific feedback messages overload the count field to act as a message type. those are listed here
const FORMAT_PLI = 1;

/// Transport and Payload specific feedback messages overload the count field to act as a message type. those are listed here
const FORMAT_FIR = 4;

/// Transport and Payload specific feedback messages overload the count field to act as a message type. those are listed here
const FORMAT_TLN = 1;

/// Transport and Payload specific feedback messages overload the count field to act as a message type. those are listed here
const FORMAT_RRR = 5;

/// Transport and Payload specific feedback messages overload the count field to act as a message type. those are listed here
const FORMAT_REMB = 15;

/// Transport and Payload specific feedback messages overload the count field to act as a message type. those are listed here.
/// https://tools.ietf.org/html/draft-holmer-rmcat-transport-wide-cc-extensions-01#page-5
const FORMAT_TCC = 15;

const RTP_VERSION = 2;
const VERSION_SHIFT = 6;
const VERSION_MASK = 0x3;
const PADDING_SHIFT = 5;
const PADDING_MASK = 0x1;
const COUNT_SHIFT = 0;
const COUNT_MASK = 0x1f;
const HEADER_LENGTH = 4;
const COUNT_MAX = (1 << 5) - 1;
const SSRC_LENGTH = 4;
const SDES_MAX_OCTET_COUNT = (1 << 8) - 1;

/// A Header is the common header shared by all RTCP packets

class RtcpHeader {
  /// If the padding bit is set, this individual RTCP packet contains
  /// some additional padding octets at the end which are not part of
  /// the control information but are included in the length field.
  bool padding;

  /// The number of reception reports, sources contained or FMT in this packet (depending on the Type)
  int count;

  /// The RTCP packet type for this packet
  PacketType packet_type;

  /// The length of this RTCP packet in 32-bit words minus one,
  /// including the header and any padding.
  int length;

  RtcpHeader(this.padding, this.count, this.packet_type, this.length);

  int marshal_size() {
    return HEADER_LENGTH;
  }

  int marshal_to(Uint8List buf, int offset) {
    if (count > 31) {
      throw Exception("InvalidHeader");
    }
    if (offset < HEADER_LENGTH) {
      throw Exception("BufferTooShort");
    }

    /*
         *  0                   1                   2                   3
         *  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
         * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
         * |V=2|P|    RC   |   PT=SR=200   |             length            |
         * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
         */

    int intPadding = padding ? 1 : 0;
    final b0 = (RTP_VERSION << VERSION_SHIFT) |
        ((intPadding) << PADDING_SHIFT) |
        (count << COUNT_SHIFT);

    final bd = ByteData.sublistView(buf);

    bd.setUint8(offset, b0);
    offset++;
    bd.setUint8(offset, packet_type.value);
    offset++;
    bd.setUint16(offset, length);
    offset += 2;

    return HEADER_LENGTH;
  }

  factory RtcpHeader.unmarshal(Uint8List raw_packet, int offset) {
    if (offset < HEADER_LENGTH) {
      throw Exception("PacketTooShort");
    }

    /*
         *  0                   1                   2                   3
         *  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
         * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
         * |V=2|P|    RC   |      PT       |             length            |
         * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
         */
    final b0 = raw_packet[offset];
    offset++;
    final version = (b0 >> VERSION_SHIFT) & VERSION_MASK;
    if (version != RTP_VERSION) {
      throw Exception("BadVersion");
    }

    final padding = ((b0 >> PADDING_SHIFT) & PADDING_MASK) > 0;
    final count = (b0 >> COUNT_SHIFT) & COUNT_MASK;
    final packet_type = PacketType.fromInt(raw_packet[offset]);
    final length = ByteData.sublistView(raw_packet).getUint16(offset);

    return RtcpHeader(
      padding,
      count,
      packet_type,
      length,
    );
  }
}
