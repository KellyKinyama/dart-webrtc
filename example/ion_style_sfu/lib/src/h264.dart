// H.264 RTP helpers used by the SFU.
//
// The SFU forwards RTP packets opaquely, but simulcast layer switches
// require us to gate the new layer until the next keyframe so the
// decoder isn't asked to apply delta frames against a missing
// reference. For H.264 (RFC 6184), a "keyframe" boundary is any
// packet that delivers — in whole or in part — an IDR slice
// (NALU type 5). Parameter-set NALUs (SPS=7, PPS=8) and SEI (6)
// commonly precede the IDR in the same Access Unit and are also
// considered part of the keyframe boundary so the gate opens on the
// first packet that signals "decoder may resync here".
//
// We handle the three RFC 6184 packet shapes:
//
//   * Single NAL unit  (NAL type  1..23)        → inspect first byte
//   * STAP-A           (NAL type 24)            → walk aggregated NALUs
//   * FU-A             (NAL type 28)            → only the START fragment
//                                                 reveals the original
//                                                 NAL type, so non-start
//                                                 fragments return false
//
// FU-B (29), MTAP16 (26) and MTAP24 (27) are uncommon in practice; we
// treat them as "not a keyframe" rather than mis-detecting.

import 'dart:typed_data';

import 'rtp_header.dart';

const int _nalTypeStapA = 24;
const int _nalTypeFuA = 28;

/// True iff [rtp] carries any NALU that begins (or whose start
/// fragment begins) an H.264 keyframe. Recognises IDR (5) and the
/// adjacent parameter sets (SPS=7, PPS=8) plus SEI (6) so the gate
/// opens on the first packet of a recoverable Access Unit.
bool isH264Keyframe(Uint8List rtp) {
  final off = rtpPayloadOffset(rtp);
  if (off >= rtp.length) return false;
  final hdr = rtp[off];
  final nalType = hdr & 0x1f;

  if (nalType >= 1 && nalType <= 23) {
    return _isKeyframeNalType(nalType);
  }

  if (nalType == _nalTypeStapA) {
    // STAP-A: 1-byte NAL header, then a sequence of
    //   [u16 size][NALU bytes...] entries.
    var p = off + 1;
    while (p + 2 <= rtp.length) {
      final size = (rtp[p] << 8) | rtp[p + 1];
      p += 2;
      if (size == 0 || p + size > rtp.length) break;
      final aggType = rtp[p] & 0x1f;
      if (_isKeyframeNalType(aggType)) return true;
      p += size;
    }
    return false;
  }

  if (nalType == _nalTypeFuA) {
    // FU-A: 1-byte FU indicator, 1-byte FU header.
    //   FU header: S(1) E(1) R(1) Type(5)
    // Only the START fragment carries the original NAL type.
    if (off + 1 >= rtp.length) return false;
    final fuHeader = rtp[off + 1];
    final isStart = (fuHeader & 0x80) != 0;
    if (!isStart) return false;
    final origType = fuHeader & 0x1f;
    return _isKeyframeNalType(origType);
  }

  return false;
}

bool _isKeyframeNalType(int t) {
  // 5 = IDR slice
  // 6 = SEI            (often precedes IDR)
  // 7 = SPS            (parameter set)
  // 8 = PPS            (parameter set)
  return t == 5 || t == 6 || t == 7 || t == 8;
}
