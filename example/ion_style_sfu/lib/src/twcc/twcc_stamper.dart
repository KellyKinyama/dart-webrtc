// Phase 7 — TWCC sender-side sequence stamper.
//
// Transport-Wide Congestion Control (draft-holmer-rmcat-transport-wide-cc-
// extensions-01) demands that every outbound primary RTP packet carry a
// transport-level 16-bit sequence number in an RFC 5285 header
// extension. The remote endpoint reports the arrival timeline of those
// numbered packets back via TWCC feedback (RTCP PT=205 FMT=15), which
// the sender feeds into its bandwidth estimator.
//
// The stamper is *per-subscriber-PC* because the seq numbers are tied
// to the egress transport, not to any individual track: a single
// counter spans every DownTrack on the same subscriber.
//
// We only rewrite an *existing* one-byte (BEDE) extension entry whose
// id matches [twccExtId]. If the publisher upstream already negotiated
// transport-cc (every recent Chrome does), the extension is always
// present and this is a cheap two-byte poke. Inserting a fresh
// extension block when the upstream didn't carry one is out of scope
// for Phase 7 (would require rewriting CSRC/X bits + extension headers
// + re-encoding into SRTP, all of which the upstream already did).

import 'dart:typed_data';

/// One stamper per subscriber PeerConnection. Holds the rolling 16-bit
/// transport-wide seq counter and a small ring buffer of (seq → send
/// time, byte size) tuples that lets the BWE map TWCC feedback
/// statuses back to wallclock send times.
class TwccStamper {
  /// Monotonic transport-wide sequence counter, modulo 2^16.
  int _next = 0;

  /// Total packets stamped (diagnostic; not modular).
  int totalStamped = 0;

  /// Packets whose existing extension was missing (could not stamp).
  int missingExtensionDrops = 0;

  /// Per-seq send-time + size, keyed by the stamped 16-bit number.
  /// Bounded; oldest entries are evicted by [_evictOlderThan].
  final Map<int, _StampedSample> _history = {};
  final int historyCapacity;

  TwccStamper({this.historyCapacity = 1024});

  /// Snapshot of the most recently assigned 16-bit sequence number,
  /// or null if nothing has been stamped yet.
  int? get lastSeq => totalStamped == 0 ? null : (_next - 1) & 0xffff;

  /// Lookup the send time recorded for [seq]. Null when [seq] has
  /// already been evicted.
  int? sendTimeMicrosFor(int seq) => _history[seq]?.sendTimeMicros;

  /// Snapshot of the byte size recorded for [seq], or null.
  int? sizeBytesFor(int seq) => _history[seq]?.sizeBytes;

  /// Stamp the next sequence number into [rtp]'s transport-cc
  /// extension. Returns the seq number written, or null when the
  /// packet doesn't carry the extension (in which case the caller
  /// should forward the packet unmodified — the remote will not
  /// generate a TWCC entry for it, but media still flows).
  ///
  /// [twccExtId] must be the 4-bit one-byte extmap id agreed with the
  /// remote endpoint (typically 3 in WebRTC).
  int? stamp(Uint8List rtp, int twccExtId, {int? sendTimeMicros}) {
    if (rtp.length < 12) return null;
    final loc = _findOneByteExtSlot(rtp, twccExtId);
    if (loc == null) {
      missingExtensionDrops++;
      return null;
    }
    final seq = _next & 0xffff;
    _next = (_next + 1) & 0xffff;
    totalStamped++;
    rtp[loc] = (seq >> 8) & 0xff;
    rtp[loc + 1] = seq & 0xff;
    _record(
      seq,
      _StampedSample(
        sendTimeMicros: sendTimeMicros ?? DateTime.now().microsecondsSinceEpoch,
        sizeBytes: rtp.length,
      ),
    );
    return seq;
  }

  /// Stub-stamp without writing: used when the caller already knows
  /// the packet doesn't have the extension but still wants a per-egress
  /// seq to feed into stats. Exposed for tests.
  int reserve({int sizeBytes = 0, int? sendTimeMicros}) {
    final seq = _next & 0xffff;
    _next = (_next + 1) & 0xffff;
    totalStamped++;
    _record(
      seq,
      _StampedSample(
        sendTimeMicros: sendTimeMicros ?? DateTime.now().microsecondsSinceEpoch,
        sizeBytes: sizeBytes,
      ),
    );
    return seq;
  }

  void _record(int seq, _StampedSample s) {
    _history[seq] = s;
    if (_history.length > historyCapacity) {
      // Evict the oldest entry. With Dart's insertion-ordered Map this
      // is O(1).
      _history.remove(_history.keys.first);
    }
  }

  /// Forget every sample older than [olderThanMicros] (compared to the
  /// most-recent stamp). Useful when TWCC feedback for old packets is
  /// no longer expected.
  void evictOlderThan(int olderThanMicros) {
    if (_history.isEmpty) return;
    final latest = _history.values.last.sendTimeMicros;
    _history
        .removeWhere((_, s) => (latest - s.sendTimeMicros) > olderThanMicros);
  }

  /// Find the 2-byte payload slot of a one-byte RFC 5285 extension
  /// whose id equals [extId]. Returns the absolute byte offset of the
  /// first payload byte, or null if not present / not a 2-byte ext.
  int? _findOneByteExtSlot(Uint8List rtp, int extId) {
    if (rtp.length < 12) return null;
    final cc = rtp[0] & 0x0f;
    final x = (rtp[0] & 0x10) != 0;
    if (!x) return null;
    final extStart = 12 + cc * 4;
    if (extStart + 4 > rtp.length) return null;
    final profile = (rtp[extStart] << 8) | rtp[extStart + 1];
    if (profile != 0xBEDE) return null;
    final lengthWords = (rtp[extStart + 2] << 8) | rtp[extStart + 3];
    final dataStart = extStart + 4;
    final dataEnd = dataStart + lengthWords * 4;
    if (dataEnd > rtp.length) return null;
    var p = dataStart;
    while (p < dataEnd) {
      final b = rtp[p++];
      if (b == 0) continue;
      final id = (b >> 4) & 0x0f;
      final lenMinus1 = b & 0x0f;
      if (id == 15) break;
      final len = lenMinus1 + 1;
      if (p + len > dataEnd) break;
      if (id == extId) {
        // Transport-cc payload is 2 bytes.
        if (len != 2) return null;
        return p;
      }
      p += len;
    }
    return null;
  }
}

class _StampedSample {
  final int sendTimeMicros;
  final int sizeBytes;
  const _StampedSample({required this.sendTimeMicros, required this.sizeBytes});
}
