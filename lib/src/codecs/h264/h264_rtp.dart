// H.264 RTP packetization (RFC 6184).
//
// Supports the three packet shapes that show up in 99% of real streams:
//
//   * Single NAL unit packet     (NAL type 1..23)
//   * STAP-A aggregation packet  (NAL type 24)        — depack only here
//   * FU-A fragmentation         (NAL type 28)
//
// Two helpers are exposed:
//
//   - [packetizeH264AccessUnit] turns a list of NALUs (one Access Unit)
//     into a sequence of RTP packets whose last packet has marker=1.
//   - [H264RtpDepacketizer] consumes inbound RTP payloads (from a camera)
//     and emits whole NALUs, transparently reassembling FU-A and
//     splitting STAP-A. Callers group emitted NALUs by the matching
//     RTP timestamp / marker bit to recover Access Units.

import 'dart:typed_data';

import '../../srtp/rtp2.dart';

const int _nalTypeStapA = 24;
const int _nalTypeFuA = 28;

/// Build RTP packets for ONE Access Unit (one or more NALUs sharing a
/// presentation timestamp). The marker bit is set on the last packet so
/// receivers can detect AU boundaries.
///
/// NALUs MUST NOT contain Annex-B start codes (`00 00 00 01`); pass raw
/// RBSP/EBSP bytes only. Use [splitAnnexB] if your source is Annex-B.
List<Packet> packetizeH264AccessUnit({
  required List<Uint8List> nalus,
  required int ssrc,
  required int timestamp,
  required int startSeq,
  int payloadType = 102,
  int maxPayloadSize = 1200,
}) {
  if (nalus.isEmpty) return const [];
  final out = <Packet>[];
  int seq = startSeq & 0xffff;

  // Pre-pack each NALU into its own series of payloads, then mark the
  // very last RTP packet of the AU.
  for (var i = 0; i < nalus.length; i++) {
    final nal = nalus[i];
    if (nal.isEmpty) continue;
    final payloads = _packetizeOneNalu(nal, maxPayloadSize);
    for (var j = 0; j < payloads.length; j++) {
      final isLastOfAu = (i == nalus.length - 1) && (j == payloads.length - 1);
      out.add(_buildRtp(
        payload: payloads[j],
        ssrc: ssrc,
        timestamp: timestamp,
        sequenceNumber: seq,
        marker: isLastOfAu,
        payloadType: payloadType,
      ));
      seq = (seq + 1) & 0xffff;
    }
  }
  return out;
}

/// Split a single NALU into one Single-NAL-unit payload or several FU-A
/// fragments. STAP-A aggregation isn't emitted on the send path — it's a
/// modest bandwidth win that costs interop oddities with some SFUs.
List<Uint8List> _packetizeOneNalu(Uint8List nal, int maxPayloadSize) {
  if (nal.length <= maxPayloadSize) {
    return [Uint8List.fromList(nal)];
  }
  // FU-A: header is 2 bytes
  //   FU indicator: F|NRI|28
  //   FU header  : S|E|R|Type
  final nri = nal[0] & 0x60;
  final fbit = nal[0] & 0x80;
  final type = nal[0] & 0x1f;
  final fuIndicator = fbit | nri | _nalTypeFuA;

  final body = Uint8List.sublistView(nal, 1); // strip 1-byte NAL header
  final perPacket = maxPayloadSize - 2;
  if (perPacket <= 0) {
    throw StateError('maxPayloadSize too small for FU-A');
  }
  final out = <Uint8List>[];
  for (var off = 0; off < body.length; off += perPacket) {
    final isFirst = off == 0;
    final isLast = off + perPacket >= body.length;
    final end = isLast ? body.length : off + perPacket;
    final fuHeader = (isFirst ? 0x80 : 0) | (isLast ? 0x40 : 0) | (type & 0x1f);
    final pkt = Uint8List(2 + (end - off))
      ..[0] = fuIndicator
      ..[1] = fuHeader
      ..setRange(2, 2 + (end - off), body, off);
    out.add(pkt);
  }
  return out;
}

Packet _buildRtp({
  required Uint8List payload,
  required int ssrc,
  required int timestamp,
  required int sequenceNumber,
  required bool marker,
  required int payloadType,
}) {
  final header = Uint8List(12);
  header[0] = 0x80;
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

// ---------------------------------------------------------------------------
// Depacketizer
// ---------------------------------------------------------------------------

/// Reassembles whole H.264 NALUs from the payloads of inbound RTP
/// packets. Stateful for FU-A reassembly across packets.
class H264RtpDepacketizer {
  final _fuBuf = BytesBuilder(copy: false);
  int _fuStartHeader = 0;

  /// Push the **payload** (after the 12-byte RTP header) of one inbound
  /// RTP packet. Returns zero or more whole NALUs (1-byte NAL header +
  /// EBSP) extracted from this payload. Callers can group consecutive
  /// returned NALUs by the matching RTP timestamp to assemble AUs.
  List<Uint8List> push(Uint8List payload) {
    if (payload.isEmpty) return const [];
    final nalType = payload[0] & 0x1f;

    // Single NALU (types 1..23).
    if (nalType >= 1 && nalType <= 23) {
      return [Uint8List.fromList(payload)];
    }

    // STAP-A: skip the 1-byte NAL header, then series of (size:2 BE | NAL).
    if (nalType == _nalTypeStapA) {
      final out = <Uint8List>[];
      var i = 1;
      while (i + 2 <= payload.length) {
        final size = (payload[i] << 8) | payload[i + 1];
        i += 2;
        if (size == 0 || i + size > payload.length) break;
        out.add(Uint8List.fromList(payload.sublist(i, i + size)));
        i += size;
      }
      return out;
    }

    // FU-A: indicator + FU header + fragment.
    if (nalType == _nalTypeFuA) {
      if (payload.length < 2) return const [];
      final fuHeader = payload[1];
      final start = (fuHeader & 0x80) != 0;
      final end = (fuHeader & 0x40) != 0;
      final fragType = fuHeader & 0x1f;

      if (start) {
        _fuBuf.clear();
        // Reconstruct NAL header from FU indicator's F|NRI + FU header's type.
        _fuStartHeader = (payload[0] & 0xe0) | (fragType & 0x1f);
        _fuBuf.addByte(_fuStartHeader);
      }
      _fuBuf.add(Uint8List.sublistView(payload, 2));
      if (end) {
        final out = _fuBuf.toBytes();
        _fuBuf.clear();
        return [out];
      }
      return const [];
    }

    // Unknown / unsupported (MTAP, FU-B, ...): drop silently.
    return const [];
  }

  /// Drop any in-progress FU-A buffer (e.g. on RTP discontinuity).
  void reset() => _fuBuf.clear();
}

// ---------------------------------------------------------------------------
// Annex-B helpers
// ---------------------------------------------------------------------------

/// Split an Annex-B byte stream (`00 00 00 01` or `00 00 01` start codes)
/// into a list of NALUs (each *without* its leading start code).
List<Uint8List> splitAnnexB(Uint8List bytes) {
  final out = <Uint8List>[];
  int i = 0;
  int? naluStart;
  while (i < bytes.length) {
    final sc = _matchStartCode(bytes, i);
    if (sc > 0) {
      if (naluStart != null && naluStart < i) {
        out.add(Uint8List.sublistView(bytes, naluStart, i));
      }
      i += sc;
      naluStart = i;
      continue;
    }
    i++;
  }
  if (naluStart != null && naluStart < bytes.length) {
    out.add(Uint8List.sublistView(bytes, naluStart));
  }
  return out;
}

int _matchStartCode(Uint8List b, int i) {
  if (i + 3 < b.length &&
      b[i] == 0 &&
      b[i + 1] == 0 &&
      b[i + 2] == 0 &&
      b[i + 3] == 1) {
    return 4;
  }
  if (i + 2 < b.length && b[i] == 0 && b[i + 1] == 0 && b[i + 2] == 1) {
    return 3;
  }
  return 0;
}

/// Decode the `sprop-parameter-sets` fmtp value (comma-separated base64
/// SPS / PPS pairs) into raw NALUs.
List<Uint8List> decodeSpropParameterSets(String spropValue) {
  final out = <Uint8List>[];
  for (final part in spropValue.split(',')) {
    final s = part.trim();
    if (s.isEmpty) continue;
    try {
      // Use dart:convert base64 via a delayed import-shim — we only need
      // it here, so the H.264 module stays free of imports otherwise.
      final bytes = _base64Decode(s);
      if (bytes.isNotEmpty) out.add(bytes);
    } catch (_) {
      // Bad fmtp — skip.
    }
  }
  return out;
}

Uint8List _base64Decode(String s) {
  // Tiny inline base64 decoder to avoid pulling dart:convert into the
  // codec layer's surface.
  const tbl =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final lookup = Uint8List(256);
  for (var i = 0; i < tbl.length; i++) {
    lookup[tbl.codeUnitAt(i)] = i;
  }
  // Strip padding.
  var input = s.replaceAll('=', '').replaceAll(RegExp(r'\s+'), '');
  final out = BytesBuilder(copy: false);
  for (var i = 0; i + 3 < input.length; i += 4) {
    final b0 = lookup[input.codeUnitAt(i)];
    final b1 = lookup[input.codeUnitAt(i + 1)];
    final b2 = lookup[input.codeUnitAt(i + 2)];
    final b3 = lookup[input.codeUnitAt(i + 3)];
    out.addByte((b0 << 2) | (b1 >> 4));
    out.addByte(((b1 & 0x0f) << 4) | (b2 >> 2));
    out.addByte(((b2 & 0x03) << 6) | b3);
  }
  final tail = input.length % 4;
  if (tail == 2) {
    final b0 = lookup[input.codeUnitAt(input.length - 2)];
    final b1 = lookup[input.codeUnitAt(input.length - 1)];
    out.addByte((b0 << 2) | (b1 >> 4));
  } else if (tail == 3) {
    final b0 = lookup[input.codeUnitAt(input.length - 3)];
    final b1 = lookup[input.codeUnitAt(input.length - 2)];
    final b2 = lookup[input.codeUnitAt(input.length - 1)];
    out.addByte((b0 << 2) | (b1 >> 4));
    out.addByte(((b1 & 0x0f) << 4) | (b2 >> 2));
  }
  return out.toBytes();
}
