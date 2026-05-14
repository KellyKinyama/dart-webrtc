// Phase 8 — RTCP Sender/Receiver Report rewriting.
//
// Subscribers receive RTP on per-subscriber rewritten SSRCs (and
// often shifted SN/TS via the SimulcastRewriter). The publisher's
// raw SR (PT=200) and RR (PT=201) reference the *publisher* SSRC and
// the *publisher* RTP timestamp space, so forwarding them verbatim
// would confuse browsers (their SSRC table doesn't know about the
// upstream SSRC and the wallclock↔RTP-ts mapping would jump on
// every layer switch).
//
// This module rewrites a compound RTCP buffer in-place style (returns
// a fresh Uint8List) translating:
//
//   * SR header SSRC: publisher → rewritten primary
//   * SR RTP timestamp: + tsOffset of the currently forwarded layer
//   * SR/RR report blocks' source-SSRC: publisher → rewritten
//
// Any other RTCP packet types (SDES, BYE, APP, FIR, PLI, NACK, REMB,
// TWCC) are forwarded unchanged.

import 'dart:typed_data';

/// Per-track translation table for RTCP rewriting. One per DownTrack.
class RtcpSsrcMap {
  /// publisher primary SSRC → subscriber-rewritten primary SSRC.
  final Map<int, int> primary = {};

  /// publisher RTX SSRC → subscriber-rewritten RTX SSRC.
  final Map<int, int> rtx = {};

  /// Translate any known SSRC (primary or RTX), or null when unknown.
  int? translate(int ssrc) => primary[ssrc] ?? rtx[ssrc];
}

/// Rewrite [rtcp] (a compound RTCP buffer received from the
/// publisher) so it makes sense in the subscriber's rewritten SSRC
/// space.
///
/// [tsOffsetFor] is consulted per-SR to translate the RTP timestamp
/// from the publisher's space into the rewritten space. The argument
/// is the *publisher* SSRC; the return is the offset added to the
/// publisher's RTP ts to produce the rewritten ts (modulo 2^32). When
/// `null`, the SR's RTP ts field is left untouched.
///
/// Packets describing SSRCs that the map doesn't know about are
/// passed through unchanged so cascaded RTCP keeps flowing.
Uint8List rewriteRtcpForSubscriber(
  Uint8List rtcp,
  RtcpSsrcMap map, {
  int? Function(int publisherSsrc)? tsOffsetFor,
}) {
  if (rtcp.isEmpty) return rtcp;
  final out = Uint8List.fromList(rtcp);
  var off = 0;
  while (off + 4 <= out.length) {
    final pt = out[off + 1];
    final lengthWords = (out[off + 2] << 8) | out[off + 3];
    final pktLen = (lengthWords + 1) * 4;
    if (off + pktLen > out.length) break;

    if (pt == 200 && pktLen >= 28) {
      _rewriteSr(out, off, pktLen, map, tsOffsetFor);
    } else if (pt == 201 && pktLen >= 8) {
      _rewriteRr(out, off, pktLen, map);
    }
    off += pktLen;
  }
  return out;
}

void _rewriteSr(
  Uint8List buf,
  int off,
  int pktLen,
  RtcpSsrcMap map,
  int? Function(int publisherSsrc)? tsOffsetFor,
) {
  // Layout:
  //   0..3  V/P/RC + PT + length
  //   4..7  SSRC of sender (publisher)
  //   8..15 NTP timestamp (64-bit, leave alone — wallclock)
  //  16..19 RTP timestamp (32-bit, shift by tsOffset)
  //  20..23 sender packet count
  //  24..27 sender octet count
  //  28..   per-RC report blocks (24 bytes each, source SSRC at offset 0)
  final senderSsrc = _u32(buf, off + 4);
  final mapped = map.translate(senderSsrc);
  if (mapped != null) {
    _writeU32(buf, off + 4, mapped);
    final shift = tsOffsetFor?.call(senderSsrc);
    if (shift != null) {
      final rtpTs = _u32(buf, off + 16);
      _writeU32(buf, off + 16, (rtpTs + shift) & 0xffffffff);
    }
  }
  final rc = buf[off] & 0x1F;
  for (var i = 0; i < rc; i++) {
    final blkOff = off + 28 + i * 24;
    if (blkOff + 24 > off + pktLen) break;
    final reportedSsrc = _u32(buf, blkOff);
    final mappedReport = map.translate(reportedSsrc);
    if (mappedReport != null) _writeU32(buf, blkOff, mappedReport);
  }
}

void _rewriteRr(Uint8List buf, int off, int pktLen, RtcpSsrcMap map) {
  // RR layout:
  //   0..3  V/P/RC + PT + length
  //   4..7  SSRC of packet sender (the receiver — leave alone)
  //   8..   per-RC report blocks (24 bytes each, source SSRC at offset 0)
  final rc = buf[off] & 0x1F;
  for (var i = 0; i < rc; i++) {
    final blkOff = off + 8 + i * 24;
    if (blkOff + 24 > off + pktLen) break;
    final reportedSsrc = _u32(buf, blkOff);
    final mapped = map.translate(reportedSsrc);
    if (mapped != null) _writeU32(buf, blkOff, mapped);
  }
}

int _u32(Uint8List b, int o) =>
    ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]) & 0xffffffff;

void _writeU32(Uint8List b, int o, int v) {
  b[o] = (v >> 24) & 0xff;
  b[o + 1] = (v >> 16) & 0xff;
  b[o + 2] = (v >> 8) & 0xff;
  b[o + 3] = v & 0xff;
}
