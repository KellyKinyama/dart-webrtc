// Phase 2 — minimal RTCP helpers shared across feedback paths.
//
// Covers only the packet types this Phase needs:
//   * RTPFB FMT=1   PT=205  Generic NACK   (RFC 4585)
//   * PSFB FMT=1    PT=206  PLI            (RFC 4585)
//
// Future phases extend with TWCC (RTPFB FMT=15), REMB (PSFB FMT=15),
// SR (PT=200), RR (PT=201).

import 'dart:typed_data';

/// One NACK FCI: a 16-bit base sequence number plus a 16-bit bitmap of
/// the next 16 missing seqs after [pid].
class NackFci {
  final int pid;
  final int blp;
  const NackFci(this.pid, this.blp);

  /// Expand into the full set of missing sequence numbers covered.
  List<int> expand() {
    final out = <int>[pid & 0xFFFF];
    for (var b = 0; b < 16; b++) {
      if ((blp & (1 << b)) != 0) out.add((pid + 1 + b) & 0xFFFF);
    }
    return out;
  }
}

/// One parsed RTCP feedback sub-packet.
sealed class RtcpFeedback {
  const RtcpFeedback({required this.senderSsrc, required this.mediaSsrc});
  final int senderSsrc;
  final int mediaSsrc;
}

class NackFeedback extends RtcpFeedback {
  final List<NackFci> fcis;
  const NackFeedback({
    required super.senderSsrc,
    required super.mediaSsrc,
    required this.fcis,
  });

  /// Flatten to the full set of missing seqs across all FCIs.
  List<int> allMissing() => [for (final f in fcis) ...f.expand()];
}

class PliFeedback extends RtcpFeedback {
  const PliFeedback({required super.senderSsrc, required super.mediaSsrc});
}

/// RFC draft-alvestrand-rmcat-remb — Receiver Estimated Maximum
/// Bitrate. Carried as PSFB FMT=15 with a fixed 'REMB' magic.
class RembFeedback extends RtcpFeedback {
  /// Estimated bitrate, bits-per-second.
  final int bps;

  /// SSRCs the estimate applies to.
  final List<int> ssrcs;

  const RembFeedback({
    required super.senderSsrc,
    required super.mediaSsrc,
    required this.bps,
    required this.ssrcs,
  });
}

/// Decoded RFC `transport-wide-cc-extensions-01` feedback packet (RTPFB
/// FMT=15). One [TwccFeedback] corresponds to one feedback message:
/// it advertises arrival/loss status for a contiguous run of transport-
/// wide sequence numbers starting at [baseSeq], plus the receive-time
/// delta of each present packet (microseconds, signed).
class TwccFeedback extends RtcpFeedback {
  /// First transport-wide sequence number described.
  final int baseSeq;

  /// Number of packet statuses encoded.
  final int packetCount;

  /// 24-bit reference time in 64-millisecond units (i.e.
  /// `referenceTime * 64ms` is the wall clock of [baseSeq]).
  final int referenceTime;

  /// Monotonically increasing feedback message counter.
  final int fbPacketCount;

  /// Per-packet status (0 = not received, 1 = received small delta,
  /// 2 = received large/negative delta). Length == [packetCount].
  final List<int> statuses;

  /// Per-packet receive-time delta in microseconds, relative to the
  /// previous reported packet. Empty entries for not-received packets.
  /// Length == [packetCount], with null at "not received" slots.
  final List<int?> deltaUs;

  const TwccFeedback({
    required super.senderSsrc,
    required super.mediaSsrc,
    required this.baseSeq,
    required this.packetCount,
    required this.referenceTime,
    required this.fbPacketCount,
    required this.statuses,
    required this.deltaUs,
  });
}

/// Walk a compound RTCP buffer and yield each NACK/PLI sub-packet found.
/// Other packet types are skipped silently.
Iterable<RtcpFeedback> parseFeedback(Uint8List rtcp) sync* {
  var off = 0;
  while (off + 4 <= rtcp.length) {
    final first = rtcp[off];
    final pt = rtcp[off + 1];
    final lengthWords = (rtcp[off + 2] << 8) | rtcp[off + 3];
    final pktLen = (lengthWords + 1) * 4;
    if (off + pktLen > rtcp.length) break;
    final fmt = first & 0x1F;

    if (pktLen >= 12) {
      final senderSsrc = _u32(rtcp, off + 4);
      final mediaSsrc = _u32(rtcp, off + 8);
      if (pt == 205 && fmt == 1) {
        // Generic NACK.
        final fcis = <NackFci>[];
        var p = off + 12;
        while (p + 4 <= off + pktLen) {
          final pid = (rtcp[p] << 8) | rtcp[p + 1];
          final blp = (rtcp[p + 2] << 8) | rtcp[p + 3];
          fcis.add(NackFci(pid, blp));
          p += 4;
        }
        yield NackFeedback(
          senderSsrc: senderSsrc,
          mediaSsrc: mediaSsrc,
          fcis: fcis,
        );
      } else if (pt == 206 && fmt == 1) {
        // PLI.
        yield PliFeedback(senderSsrc: senderSsrc, mediaSsrc: mediaSsrc);
      } else if (pt == 206 && fmt == 15 && pktLen >= 24) {
        // REMB. FCI layout starting at off+12:
        //   4B magic 'R'|'E'|'M'|'B'
        //   1B numSsrcs
        //   1B exp(6) | mantissa(2 hi)
        //   2B mantissa(16 lo)
        //   numSsrcs * 4B SSRCs
        final p = off + 12;
        if (rtcp[p] == 0x52 &&
            rtcp[p + 1] == 0x45 &&
            rtcp[p + 2] == 0x4D &&
            rtcp[p + 3] == 0x42) {
          final n = rtcp[p + 4];
          final exp = (rtcp[p + 5] >> 2) & 0x3F;
          final mantissa =
              ((rtcp[p + 5] & 0x03) << 16) | (rtcp[p + 6] << 8) | rtcp[p + 7];
          final bps = mantissa << exp;
          final ssrcs = <int>[];
          for (var k = 0; k < n; k++) {
            final so = p + 8 + k * 4;
            if (so + 4 > off + pktLen) break;
            ssrcs.add(_u32(rtcp, so));
          }
          yield RembFeedback(
            senderSsrc: senderSsrc,
            mediaSsrc: mediaSsrc,
            bps: bps,
            ssrcs: ssrcs,
          );
        }
      } else if (pt == 205 && fmt == 15 && pktLen >= 20) {
        // TWCC. FCI layout starting at off+12:
        //   2B base seq
        //   2B packet status count
        //   3B reference time (signed)
        //   1B fb pkt count
        //   N packet status chunks (16-bit each)
        //   M receive deltas (1 or 2 bytes each)
        final p = off + 12;
        final baseSeq = (rtcp[p] << 8) | rtcp[p + 1];
        final pktCount = (rtcp[p + 2] << 8) | rtcp[p + 3];
        final refTime =
            (rtcp[p + 4] << 16) | (rtcp[p + 5] << 8) | rtcp[p + 6];
        final fbPktCount = rtcp[p + 7];

        final statuses = <int>[];
        var ci = p + 8;
        while (statuses.length < pktCount &&
            ci + 2 <= off + pktLen) {
          final chunk = (rtcp[ci] << 8) | rtcp[ci + 1];
          ci += 2;
          if ((chunk & 0x8000) == 0) {
            // Run-length: T=0, S(2), L(13).
            final status = (chunk >> 13) & 0x03;
            final runLen = chunk & 0x1FFF;
            for (var k = 0;
                k < runLen && statuses.length < pktCount;
                k++) {
              statuses.add(status);
            }
          } else {
            // Status vector: T=1, S(1), 14 symbols.
            final sym1 = (chunk >> 14) & 0x01;
            if (sym1 == 0) {
              // 14 × 1-bit symbols (0 = not recv, 1 = recv small).
              for (var k = 13; k >= 0 && statuses.length < pktCount; k--) {
                statuses.add(((chunk >> k) & 0x01) == 1 ? 1 : 0);
              }
            } else {
              // 7 × 2-bit symbols.
              for (var k = 6; k >= 0 && statuses.length < pktCount; k--) {
                statuses.add((chunk >> (k * 2)) & 0x03);
              }
            }
          }
        }

        final deltaUs = <int?>[];
        for (final s in statuses) {
          if (s == 1) {
            if (ci + 1 > off + pktLen) {
              deltaUs.add(null);
              continue;
            }
            // 8-bit unsigned in 250µs units.
            deltaUs.add(rtcp[ci] * 250);
            ci += 1;
          } else if (s == 2) {
            if (ci + 2 > off + pktLen) {
              deltaUs.add(null);
              continue;
            }
            // 16-bit signed, 250µs units.
            var d = (rtcp[ci] << 8) | rtcp[ci + 1];
            if ((d & 0x8000) != 0) d -= 0x10000;
            deltaUs.add(d * 250);
            ci += 2;
          } else {
            deltaUs.add(null);
          }
        }

        yield TwccFeedback(
          senderSsrc: senderSsrc,
          mediaSsrc: mediaSsrc,
          baseSeq: baseSeq,
          packetCount: pktCount,
          referenceTime: refTime,
          fbPacketCount: fbPktCount,
          statuses: statuses,
          deltaUs: deltaUs,
        );
      }
    }
    off += pktLen;
  }
}

int _u32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

/// Build a generic-NACK packet (RFC 4585 RTPFB FMT=1) covering [missing].
/// Adjacent missing seqs are folded into one (PID, BLP) FCI when possible.
Uint8List buildNack(int senderSsrc, int mediaSsrc, List<int> missing) {
  final fcis = <int>[]; // packed 32-bit words
  final sorted = [...missing.map((s) => s & 0xFFFF)]..sort();
  var i = 0;
  while (i < sorted.length) {
    final pid = sorted[i] & 0xFFFF;
    var blp = 0;
    var j = i + 1;
    while (j < sorted.length) {
      final delta = (sorted[j] - pid) & 0xFFFF;
      if (delta < 1 || delta > 16) break;
      blp |= 1 << (delta - 1);
      j++;
    }
    fcis.add((pid << 16) | (blp & 0xFFFF));
    i = j;
  }

  final length = 12 + fcis.length * 4;
  final out = Uint8List(length);
  final bd = ByteData.sublistView(out);
  out[0] = 0x80 | 1; // V=2, P=0, FMT=1
  out[1] = 205;
  bd.setUint16(2, (length ~/ 4) - 1, Endian.big);
  bd.setUint32(4, senderSsrc, Endian.big);
  bd.setUint32(8, mediaSsrc, Endian.big);
  for (var k = 0; k < fcis.length; k++) {
    bd.setUint32(12 + k * 4, fcis[k], Endian.big);
  }
  return out;
}

/// Build a PLI packet (RFC 4585 PSFB FMT=1).
Uint8List buildPli(int senderSsrc, int mediaSsrc) {
  final out = Uint8List(12);
  final bd = ByteData.sublistView(out);
  out[0] = 0x80 | 1; // V=2, P=0, FMT=1
  out[1] = 206;
  bd.setUint16(2, 2, Endian.big);
  bd.setUint32(4, senderSsrc, Endian.big);
  bd.setUint32(8, mediaSsrc, Endian.big);
  return out;
}

/// Build a REMB packet (PSFB FMT=15) advertising [bps] for [ssrcs].
Uint8List buildRemb(int senderSsrc, int bps, List<int> ssrcs) {
  // Pack bps into 6-bit exponent + 18-bit mantissa.
  var exp = 0;
  var mantissa = bps;
  while (mantissa >= (1 << 18)) {
    mantissa >>= 1;
    exp++;
  }
  final n = ssrcs.length;
  final length = 12 + 8 + n * 4;
  final out = Uint8List(length);
  final bd = ByteData.sublistView(out);
  out[0] = 0x80 | 15; // V=2, P=0, FMT=15
  out[1] = 206;
  bd.setUint16(2, (length ~/ 4) - 1, Endian.big);
  bd.setUint32(4, senderSsrc, Endian.big);
  bd.setUint32(8, 0, Endian.big); // media SSRC unused for REMB
  out[12] = 0x52; // 'R'
  out[13] = 0x45; // 'E'
  out[14] = 0x4D; // 'M'
  out[15] = 0x42; // 'B'
  out[16] = n & 0xFF;
  out[17] = ((exp & 0x3F) << 2) | ((mantissa >> 16) & 0x03);
  out[18] = (mantissa >> 8) & 0xFF;
  out[19] = mantissa & 0xFF;
  for (var k = 0; k < n; k++) {
    bd.setUint32(20 + k * 4, ssrcs[k], Endian.big);
  }
  return out;
}

/// Build a minimal TWCC feedback (RTPFB FMT=15). [arrivals] is a list of
/// `(transportSeq, arrivalEpochUs)` ordered by sequence. Builds a
/// single status-vector chunk encoding (only suitable for small batches
/// — for production cadence ion-sfu emits feedback every 100ms, but the
/// status-vector path keeps us under a 1500-byte MTU for ≤ ~200 packets
/// per batch which is well within real-world ranges).
///
/// Returns null when [arrivals] is empty.
Uint8List? buildTwcc({
  required int senderSsrc,
  required int mediaSsrc,
  required int fbPktCount,
  required List<(int seq, int arrivalUs)> arrivals,
}) {
  if (arrivals.isEmpty) return null;
  arrivals = [...arrivals]..sort((a, b) {
      // 16-bit modular comparison: treat (a-b) as a signed 16-bit
      // delta so wraparound around 65535/0 still orders correctly.
      final d = (a.$1 - b.$1) & 0xFFFF;
      if (d == 0) return 0;
      return d < 0x8000 ? 1 : -1;
    });
  final baseSeq = arrivals.first.$1 & 0xFFFF;
  // Reference time in 64ms units (24-bit), anchored on first arrival.
  final baseArrivalUs = arrivals.first.$2;
  final refTime = (baseArrivalUs ~/ 64000) & 0xFFFFFF;
  final anchorUs = refTime * 64000;

  // Build dense status list across the seq range.
  final lastSeq = arrivals.last.$1 & 0xFFFF;
  final pktCount = ((lastSeq - baseSeq) & 0xFFFF) + 1;
  final byIdx = <int, int>{};
  for (final a in arrivals) {
    final idx = (a.$1 - baseSeq) & 0xFFFF;
    if (idx < pktCount) byIdx[idx] = a.$2;
  }

  final statuses = List<int>.filled(pktCount, 0);
  final deltas = <int>[]; // raw quarter-ms values
  final deltaSizes = <int>[]; // 1 or 2 bytes
  var prevUs = anchorUs;
  for (var i = 0; i < pktCount; i++) {
    final us = byIdx[i];
    if (us == null) continue;
    final deltaQms = (us - prevUs) ~/ 250;
    prevUs = us;
    if (deltaQms >= 0 && deltaQms <= 0xFF) {
      statuses[i] = 1;
      deltas.add(deltaQms);
      deltaSizes.add(1);
    } else {
      var d = deltaQms;
      if (d < -32768) d = -32768;
      if (d > 32767) d = 32767;
      statuses[i] = 2;
      deltas.add(d & 0xFFFF);
      deltaSizes.add(2);
    }
  }

  // Encode statuses as 2-bit symbols, 7 per status-vector chunk.
  final chunks = <int>[];
  for (var i = 0; i < pktCount; i += 7) {
    var chunk = 0xC000; // T=1, S=1 (2-bit symbols)
    for (var k = 0; k < 7; k++) {
      final idx = i + k;
      final s = idx < pktCount ? statuses[idx] : 0;
      chunk |= (s & 0x03) << ((6 - k) * 2);
    }
    chunks.add(chunk);
  }

  // Total length: 12 header + 8 base + 2*chunks + sum(deltaSizes). Pad
  // to 4-byte multiple.
  var bodyLen = 8 + chunks.length * 2;
  for (final s in deltaSizes) {
    bodyLen += s;
  }
  final padded = (bodyLen + 3) & ~3;
  final total = 12 + padded;
  final out = Uint8List(total);
  final bd = ByteData.sublistView(out);
  out[0] = 0x80 | 15; // V=2, FMT=15
  out[1] = 205;
  bd.setUint16(2, (total ~/ 4) - 1, Endian.big);
  bd.setUint32(4, senderSsrc, Endian.big);
  bd.setUint32(8, mediaSsrc, Endian.big);
  bd.setUint16(12, baseSeq, Endian.big);
  bd.setUint16(14, pktCount, Endian.big);
  out[16] = (refTime >> 16) & 0xFF;
  out[17] = (refTime >> 8) & 0xFF;
  out[18] = refTime & 0xFF;
  out[19] = fbPktCount & 0xFF;

  var p = 20;
  for (final c in chunks) {
    out[p++] = (c >> 8) & 0xFF;
    out[p++] = c & 0xFF;
  }
  for (var i = 0; i < deltas.length; i++) {
    final size = deltaSizes[i];
    if (size == 1) {
      out[p++] = deltas[i] & 0xFF;
    } else {
      out[p++] = (deltas[i] >> 8) & 0xFF;
      out[p++] = deltas[i] & 0xFF;
    }
  }
  return out;
}

/// Tracks the last RTP sequence number observed on a stream and reports
/// any gaps so the caller can request retransmission. Mirrors
/// `SeqGapDetector` from `example/sfu`.
class SeqGapDetector {
  final int maxGap;
  int? _lastSeq;

  SeqGapDetector({this.maxGap = 16});

  int? get lastSeq => _lastSeq;

  List<int> feed(int seq) {
    seq &= 0xFFFF;
    final last = _lastSeq;
    if (last == null) {
      _lastSeq = seq;
      return const [];
    }
    final diff = (seq - last) & 0xFFFF;
    if (diff == 0) return const [];
    if (diff > 0x8000) return const []; // re-order / late
    if (diff > maxGap) {
      _lastSeq = seq;
      return const [];
    }
    _lastSeq = seq;
    if (diff == 1) return const [];
    final missing = <int>[];
    for (var i = 1; i < diff; i++) {
      missing.add((last + i) & 0xFFFF);
    }
    return missing;
  }
}
