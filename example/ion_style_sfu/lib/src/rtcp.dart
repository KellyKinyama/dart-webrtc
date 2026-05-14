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
