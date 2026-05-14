// Phase 3b — minimal RTP header helpers for SN/TS/OSN rewriting.
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
/// Returns an `extId → payload-bytes` map. Returns an empty map when
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
