// Phase 3b â€” minimal RTP header helpers for SN/TS/OSN rewriting.
//
// Only what DownTrack needs to compute the payload offset (so it can
// reach into the RFC 4588 RTX payload's `OSN` field) and to read/write
// the 16-bit sequence number and 32-bit timestamp.

import 'dart:typed_data';

/// Read the 16-bit sequence number at offset 2.
int rtpSeq(Uint8List rtp) => (rtp[2] << 8) | rtp[3];

/// Read the 32-bit timestamp at offset 4.
int rtpTimestamp(Uint8List rtp) =>
    (rtp[4] << 24) | (rtp[5] << 16) | (rtp[6] << 8) | rtp[7];

/// Overwrite the 16-bit sequence number at offset 2.
void writeRtpSeq(Uint8List rtp, int seq) {
  rtp[2] = (seq >> 8) & 0xff;
  rtp[3] = seq & 0xff;
}

/// Overwrite the 32-bit timestamp at offset 4.
void writeRtpTimestamp(Uint8List rtp, int ts) {
  rtp[4] = (ts >> 24) & 0xff;
  rtp[5] = (ts >> 16) & 0xff;
  rtp[6] = (ts >> 8) & 0xff;
  rtp[7] = ts & 0xff;
}

/// Compute the byte offset at which the RTP payload begins, accounting
/// for the CSRC list and the optional one-byte/two-byte header
/// extension. Returns `rtp.length` if the buffer is malformed.
int rtpPayloadOffset(Uint8List rtp) {
  if (rtp.length < 12) return rtp.length;
  final cc = rtp[0] & 0x0f;
  final x = (rtp[0] & 0x10) != 0;
  var off = 12 + cc * 4;
  if (x) {
    if (off + 4 > rtp.length) return rtp.length;
    final extLenWords = (rtp[off + 2] << 8) | rtp[off + 3];
    off += 4 + extLenWords * 4;
  }
  if (off > rtp.length) return rtp.length;
  return off;
}

/// Parse RFC 5285 RTP header extensions. Supports both the one-byte
/// form (profile `0xBEDE`) and the two-byte form (profile `0x100x`).
/// Returns an `extId â†’ payload-bytes` map. Returns an empty map when
/// the X bit is unset, the buffer is malformed, or the profile is
/// unknown.
///
/// IDs in the one-byte form are 4-bit (1..14). The reserved id 15
/// terminates parsing per RFC. IDs in the two-byte form are 8-bit
/// (1..255). Padding bytes (id 0) are skipped.
Map<int, Uint8List> readRtpExtensions(Uint8List rtp) {
  if (rtp.length < 12) return const {};
  final cc = rtp[0] & 0x0f;
  final x = (rtp[0] & 0x10) != 0;
  if (!x) return const {};
  final extStart = 12 + cc * 4;
  if (extStart + 4 > rtp.length) return const {};
  final profile = (rtp[extStart] << 8) | rtp[extStart + 1];
  final lengthWords = (rtp[extStart + 2] << 8) | rtp[extStart + 3];
  final dataStart = extStart + 4;
  final dataEnd = dataStart + lengthWords * 4;
  if (dataEnd > rtp.length) return const {};

  final out = <int, Uint8List>{};
  var p = dataStart;
  if (profile == 0xBEDE) {
    // One-byte header form.
    while (p < dataEnd) {
      final b = rtp[p++];
      if (b == 0) continue; // padding
      final id = (b >> 4) & 0x0f;
      final lenMinus1 = b & 0x0f;
      if (id == 15) break; // reserved terminator
      final len = lenMinus1 + 1;
      if (p + len > dataEnd) break;
      out[id] = Uint8List.sublistView(rtp, p, p + len);
      p += len;
    }
  } else if ((profile & 0xfff0) == 0x1000) {
    // Two-byte header form.
    while (p + 1 < dataEnd) {
      final id = rtp[p++];
      if (id == 0) continue; // padding (one byte)
      final len = rtp[p++];
      if (p + len > dataEnd) break;
      out[id] = Uint8List.sublistView(rtp, p, p + len);
      p += len;
    }
  }
  return out;
}

/// Decode a SDES rtp-stream-id (or repaired-rtp-stream-id) extension
/// payload into its UTF-8 string form (e.g. `"q"`, `"h"`, `"f"`).
/// Returns null when [bytes] is null or empty.
String? decodeRidString(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return null;
  // RIDs are restricted ASCII per draft-ietf-mmusic-rid; cheap path.
  final sb = StringBuffer();
  for (final b in bytes) {
    if (b == 0) break; // defensive: never seen in practice
    sb.writeCharCode(b);
  }
  return sb.toString();
}

/// One RFC 6464 audio-level reading.
///
/// `level` is the negated dBov of the source; 0 represents the loudest
/// possible level (0 dBov), 127 represents silence (or below). `voice`
/// reflects the V flag (true = the encoder believes the frame contains
/// voice activity).
class AudioLevel {
  final int level;
  final bool voice;
  const AudioLevel(this.level, this.voice);
}

/// Decode an `urn:ietf:params:rtp-hdrext:ssrc-audio-level` (RFC 6464)
/// extension payload. The payload is a single byte: 1-bit V flag in
/// the MSB followed by 7-bit level (-dBov, 0..127). Returns null when
/// [bytes] is null or empty.
AudioLevel? decodeAudioLevel(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return null;
  final b = bytes[0];
  return AudioLevel(b & 0x7f, (b & 0x80) != 0);
}

/// Zero out the audio-level byte for the extension whose id is
/// [extId] inside [rtp], in place. Preserves the V flag (so VAD is
/// still signalled) but blanks the loudness reading. Cheap fallback
/// when the SFU wants to suppress loudness leakage to subscribers
/// without renegotiating the extmap.
///
/// Silently no-ops when the X bit is unset, the profile is unknown,
/// or the extension isn't present.
void stripAudioLevel(Uint8List rtp, int extId) {
  if (rtp.length < 12) return;
  final cc = rtp[0] & 0x0f;
  final x = (rtp[0] & 0x10) != 0;
  if (!x) return;
  final extStart = 12 + cc * 4;
  if (extStart + 4 > rtp.length) return;
  final profile = (rtp[extStart] << 8) | rtp[extStart + 1];
  final lengthWords = (rtp[extStart + 2] << 8) | rtp[extStart + 3];
  final dataStart = extStart + 4;
  final dataEnd = dataStart + lengthWords * 4;
  if (dataEnd > rtp.length) return;

  var p = dataStart;
  if (profile == 0xBEDE) {
    while (p < dataEnd) {
      final b = rtp[p++];
      if (b == 0) continue;
      final id = (b >> 4) & 0x0f;
      final lenMinus1 = b & 0x0f;
      if (id == 15) break;
      final len = lenMinus1 + 1;
      if (p + len > dataEnd) break;
      if (id == extId && len >= 1) {
        // Keep V (bit 7), zero the level.
        rtp[p] = rtp[p] & 0x80;
        return;
      }
      p += len;
    }
  } else if ((profile & 0xfff0) == 0x1000) {
    while (p + 1 < dataEnd) {
      final id = rtp[p++];
      if (id == 0) continue;
      final len = rtp[p++];
      if (p + len > dataEnd) break;
      if (id == extId && len >= 1) {
        rtp[p] = rtp[p] & 0x80;
        return;
      }
      p += len;
    }
  }
}


/// Phase B13 — Chrome / WebRTC `playout-delay` RTP header extension
/// (`http://www.webrtc.org/experiments/rtp-hdrext/playout-delay`).
///
/// The payload is exactly 3 bytes carrying two 12-bit unsigned values
/// expressed in units of 10 ms:
///
/// ```
///  0                   1                   2
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |        MIN delay      |        MAX delay      |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// ```
///
/// Both values are clamped to [0, 40_950] ms (12 bits × 10 ms each).
/// Any negative input is clamped to 0; any input above the cap is
/// clamped to the cap. Caller is responsible for ensuring `min <= max`
/// — this helper does NOT swap them.
class PlayoutDelay {
  /// Minimum tolerable playout delay in milliseconds.
  final int minMs;

  /// Maximum tolerable playout delay in milliseconds.
  final int maxMs;

  const PlayoutDelay(this.minMs, this.maxMs);

  /// Maximum representable value (12 bits × 10 ms).
  static const int maxRepresentableMs = 4095 * 10;

  @override
  bool operator ==(Object other) =>
      other is PlayoutDelay && other.minMs == minMs && other.maxMs == maxMs;

  @override
  int get hashCode => Object.hash(minMs, maxMs);

  @override
  String toString() => 'PlayoutDelay(min=${minMs}ms, max=${maxMs}ms)';
}

int _clampPlayoutMs(int ms) {
  if (ms < 0) return 0;
  if (ms > PlayoutDelay.maxRepresentableMs) {
    return PlayoutDelay.maxRepresentableMs;
  }
  return ms;
}

/// Encode [pd] into a freshly-allocated 3-byte extension payload
/// suitable for inclusion in the RFC 5285 extension area.
Uint8List encodePlayoutDelay(PlayoutDelay pd) {
  final minUnits = _clampPlayoutMs(pd.minMs) ~/ 10;
  final maxUnits = _clampPlayoutMs(pd.maxMs) ~/ 10;
  final out = Uint8List(3);
  out[0] = (minUnits >> 4) & 0xff;
  out[1] = ((minUnits & 0x0f) << 4) | ((maxUnits >> 8) & 0x0f);
  out[2] = maxUnits & 0xff;
  return out;
}

/// Decode a 3-byte playout-delay extension payload. Returns null when
/// [bytes] is null or shorter than 3 bytes.
PlayoutDelay? decodePlayoutDelay(Uint8List? bytes) {
  if (bytes == null || bytes.length < 3) return null;
  final minUnits = (bytes[0] << 4) | ((bytes[1] >> 4) & 0x0f);
  final maxUnits = ((bytes[1] & 0x0f) << 8) | bytes[2];
  return PlayoutDelay(minUnits * 10, maxUnits * 10);
}
