// Tiny VP8 RTP payloader (RFC 7741, simple mode).
//
// For each compressed VP8 frame, splits it into one or more RTP packets that
// carry the mandatory 1-byte VP8 payload descriptor:
//
//   0 1 2 3 4 5 6 7
//   +-+-+-+-+-+-+-+-+
//   |X|R|N|S|R| PID |
//   +-+-+-+-+-+-+-+-+
//
// We always emit the simplest descriptor: X=0, R=0, N=0, PartID=0. The
// `S` (start of partition) bit is set on the first packet of each frame and
// cleared on subsequent fragments, per RFC 7741 §4.4. The marker bit on the
// RTP header is set on the *last* packet of each frame.

import 'dart:typed_data';

import '../../srtp/rtp2.dart';

/// RFC 7741 §4.2 — minimal VP8 payload descriptor (1 byte).
///
/// `S=1` for the first packet of a frame, `S=0` for subsequent fragments.
int _vp8Descriptor({required bool startOfPartition}) =>
    startOfPartition ? 0x10 : 0x00;

/// Build one or more RTP [Packet]s for a single compressed VP8 frame.
///
/// * [frame]      compressed VP8 bitstream (one access unit).
/// * [ssrc]       RTP SSRC.
/// * [payloadType] RTP PT (96 by default; matches the SDP default).
/// * [timestamp]  90 kHz timestamp for this frame.
/// * [startSeq]   sequence number of the first packet; the function returns
///                the next free sequence number.
/// * [maxPayloadSize] maximum bytes (after the VP8 descriptor) to put in
///                each packet; default 1200 leaves headroom for IP/UDP/SRTP.
List<Packet> packetizeVp8Frame({
  required Uint8List frame,
  required int ssrc,
  required int timestamp,
  required int startSeq,
  int payloadType = 96,
  int maxPayloadSize = 1200,
}) {
  if (frame.isEmpty) return const [];
  final out = <Packet>[];
  int offset = 0;
  int seq = startSeq & 0xffff;
  while (offset < frame.length) {
    final remaining = frame.length - offset;
    final chunk = remaining > maxPayloadSize ? maxPayloadSize : remaining;
    final isFirst = offset == 0;
    final isLast = offset + chunk >= frame.length;

    final payload = Uint8List(1 + chunk)
      ..[0] = _vp8Descriptor(startOfPartition: isFirst)
      ..setRange(1, 1 + chunk, frame, offset);

    out.add(_makePacket(
      payloadType: payloadType,
      ssrc: ssrc,
      timestamp: timestamp,
      sequenceNumber: seq,
      marker: isLast,
      payload: payload,
    ));

    offset += chunk;
    seq = (seq + 1) & 0xffff;
  }
  return out;
}

/// Build a [Packet] with `rawData` and `headerSize` correctly populated
/// (required by the SRTP GCM encrypt path which reads `packet.rawData`).
Packet _makePacket({
  required int payloadType,
  required int ssrc,
  required int timestamp,
  required int sequenceNumber,
  required bool marker,
  required Uint8List payload,
}) {
  // Minimal 12-byte RTP header (no CSRCs, no extensions).
  final header = Uint8List(12);
  header[0] = 0x80; // V=2, P=0, X=0, CC=0
  header[1] = (marker ? 0x80 : 0x00) | (payloadType & 0x7f);
  final bd = ByteData.sublistView(header);
  bd.setUint16(2, sequenceNumber & 0xffff, Endian.big);
  bd.setUint32(4, timestamp & 0xffffffff, Endian.big);
  bd.setUint32(8, ssrc & 0xffffffff, Endian.big);

  final raw = Uint8List(header.length + payload.length)
    ..setRange(0, header.length, header)
    ..setRange(header.length, header.length + payload.length, payload);

  return Packet.unmarshal(raw);
}
