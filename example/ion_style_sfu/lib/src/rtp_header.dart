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
