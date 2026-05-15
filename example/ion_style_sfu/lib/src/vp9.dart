// VP9 RTP payload-descriptor keyframe detection (RFC 8741 §4.2).
//
// The VP9 descriptor sits between the RTP header and the VP9 frame
// data. Its first byte carries the bits we care about for keyframe
// gating:
//
//   bit 7 (I): PictureID present
//   bit 6 (P): Inter-picture predicted layer frame
//                0 → this packet's layer frame can be decoded
//                    without referencing earlier frames
//                    (i.e., it's a keyframe for this spatial layer)
//   bit 5 (L): Layer indices present
//   bit 4 (F): Flexible mode
//   bit 3 (B): Start of a (layer) frame
//   bit 2 (E): End of a (layer) frame
//   bit 1 (V): Scalability structure (SS) present
//   bit 0 (Z): Not a reference for upper spatial layers
//
// For a simulcast/SVC layer-switch gate, "this packet opens a
// decodable boundary" iff B=1 (start-of-frame) AND P=0
// (not inter-predicted). For SVC streams, we additionally require
// the base spatial layer (SID==0) when layer indices are present, so
// the gate doesn't open on an enhancement-layer keyframe whose base
// reference hasn't arrived yet.

import 'dart:typed_data';

import 'rtp_header.dart';

/// True iff [rtp] carries the start of a VP9 keyframe (a layer frame
/// that does not reference any earlier frame). For SVC streams, only
/// returns true when the packet belongs to the base spatial layer.
bool isVp9Keyframe(Uint8List rtp) {
  final off = rtpPayloadOffset(rtp);
  if (off >= rtp.length) return false;

  final b0 = rtp[off];
  final iBit = (b0 & 0x80) != 0;
  final pBit = (b0 & 0x40) != 0;
  final lBit = (b0 & 0x20) != 0;
  final bBit = (b0 & 0x08) != 0;

  // Must be the start of a frame and not inter-predicted.
  if (!bBit || pBit) return false;

  // If layer indices are present, require the base spatial layer
  // (SID == 0). The first L byte layout (in both flexible and
  // non-flexible modes) is: TID(3) | U(1) | SID(3) | D(1).
  if (lBit) {
    var p = off + 1;
    // Skip the variable-width PictureID (I=1).
    if (iBit) {
      if (p >= rtp.length) return false;
      final mBit = (rtp[p] & 0x80) != 0;
      p += mBit ? 2 : 1;
    }
    if (p >= rtp.length) return false;
    final sid = (rtp[p] >> 1) & 0x07;
    if (sid != 0) return false;
  }

  return true;
}
