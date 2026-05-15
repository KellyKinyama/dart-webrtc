// VP8 RTP payload-descriptor helpers (RFC 7741 §4.2 + §4.3).
//
// Only what the SFU needs:
//   * [parseVp8Descriptor]   — decode the variable-length descriptor
//     so we can read PictureID / TL0PICIDX and locate the actual VP8
//     payload.
//   * [isVp8Keyframe]        — true iff the packet carries the first
//     partition of a keyframe (S=1, PID=0, payload P-bit = 0).
//   * [Vp8PicIdRewriter]     — maintains a continuous outbound
//     PictureID + TL0PICIDX sequence across simulcast layer switches,
//     so the decoder doesn't see backwards jumps when we flip layers.
//
// Mirrors `pkg/buffer/helpers.go::VP8` and `pkg/sfu/helpers.go::setVP8`
// in the Go ion-sfu, kept narrow to the fields we actually rewrite.

import 'dart:typed_data';

import 'rtp_header.dart';

/// Decoded view of the VP8 RTP payload descriptor that sits between
/// the RTP header and the VP8 frame payload itself.
class Vp8Descriptor {
  /// Total length of the descriptor, in bytes. Add to the RTP payload
  /// offset to reach the first byte of VP8 frame data.
  final int headerLength;

  /// Start-of-partition flag (S bit).
  final bool startOfPartition;

  /// Partition index (PID, 3 bits).
  final int partitionIndex;

  /// True iff X=1 → an extension byte is present.
  final bool hasExtension;

  /// Whether [pictureId] is 15-bit (M=1) or 7-bit (M=0). Only
  /// meaningful when [pictureId] != null.
  final bool pictureIdIsLong;

  /// Decoded PictureID, or null when the I bit is unset.
  final int? pictureId;

  /// Byte offset within the RTP payload at which the (variable-width)
  /// PictureID starts. -1 when [pictureId] is null. Used by the
  /// rewriter to overwrite it in place.
  final int pictureIdOffset;

  /// Decoded TL0PICIDX, or null when the L bit is unset.
  final int? tl0PicIdx;

  /// Byte offset within the RTP payload at which TL0PICIDX sits, or
  /// -1.
  final int tl0PicIdxOffset;

  const Vp8Descriptor({
    required this.headerLength,
    required this.startOfPartition,
    required this.partitionIndex,
    required this.hasExtension,
    required this.pictureIdIsLong,
    required this.pictureId,
    required this.pictureIdOffset,
    required this.tl0PicIdx,
    required this.tl0PicIdxOffset,
  });
}

/// Parse the VP8 descriptor that begins at [payloadOffset] inside
/// [rtp]. Returns null when the buffer is too short or malformed.
Vp8Descriptor? parseVp8Descriptor(Uint8List rtp, int payloadOffset) {
  if (payloadOffset >= rtp.length) return null;
  final p0 = rtp[payloadOffset];
  final hasExt = (p0 & 0x80) != 0;
  final s = (p0 & 0x10) != 0;
  final pid = p0 & 0x07;

  if (!hasExt) {
    return Vp8Descriptor(
      headerLength: 1,
      startOfPartition: s,
      partitionIndex: pid,
      hasExtension: false,
      pictureIdIsLong: false,
      pictureId: null,
      pictureIdOffset: -1,
      tl0PicIdx: null,
      tl0PicIdxOffset: -1,
    );
  }

  if (payloadOffset + 1 >= rtp.length) return null;
  final p1 = rtp[payloadOffset + 1];
  final iBit = (p1 & 0x80) != 0;
  final lBit = (p1 & 0x40) != 0;
  final tBit = (p1 & 0x20) != 0;
  final kBit = (p1 & 0x10) != 0;

  var p = payloadOffset + 2;
  int? pictureId;
  var pictureIdLong = false;
  var pictureIdOffset = -1;
  if (iBit) {
    if (p >= rtp.length) return null;
    pictureIdOffset = p;
    final mBit = (rtp[p] & 0x80) != 0;
    if (mBit) {
      if (p + 1 >= rtp.length) return null;
      pictureIdLong = true;
      pictureId = ((rtp[p] & 0x7f) << 8) | rtp[p + 1];
      p += 2;
    } else {
      pictureId = rtp[p] & 0x7f;
      p += 1;
    }
  }

  int? tl0;
  var tl0Off = -1;
  if (lBit) {
    if (p >= rtp.length) return null;
    tl0Off = p;
    tl0 = rtp[p];
    p += 1;
  }

  if (tBit || kBit) {
    if (p >= rtp.length) return null;
    p += 1; // TID/Y/KEYIDX byte
  }

  return Vp8Descriptor(
    headerLength: p - payloadOffset,
    startOfPartition: s,
    partitionIndex: pid,
    hasExtension: true,
    pictureIdIsLong: pictureIdLong,
    pictureId: pictureId,
    pictureIdOffset: pictureIdOffset,
    tl0PicIdx: tl0,
    tl0PicIdxOffset: tl0Off,
  );
}

/// True iff [rtp] carries the first partition of a VP8 keyframe.
///
/// Per RFC 6386 §9.1, the first byte of an uncompressed VP8 frame
/// header has bit 0 (P, "inverse keyframe") = 0 for a keyframe. That
/// byte is only present when the RTP packet is the start of partition
/// zero (S=1, PID=0).
bool isVp8Keyframe(Uint8List rtp) {
  final payloadOff = rtpPayloadOffset(rtp);
  final desc = parseVp8Descriptor(rtp, payloadOff);
  if (desc == null) return false;
  if (!desc.startOfPartition || desc.partitionIndex != 0) return false;
  final frameOff = payloadOff + desc.headerLength;
  if (frameOff >= rtp.length) return false;
  return (rtp[frameOff] & 0x01) == 0;
}

/// Continuous outbound PictureID / TL0PICIDX rewriter.
///
/// Each simulcast layer comes with its own picture-id space. When the
/// SFU flips layers, the decoder would see a backwards or out-of-order
/// PictureID and drop frames; this class tracks `(layer → offset)` so
/// the outbound stream stays monotonically increasing.
class Vp8PicIdRewriter {
  /// Outbound PictureID emitted on the most recent primary packet (15-bit
  /// space, wraps at 0x8000). -1 until the first keyframe arrives.
  int lastOutPicId = -1;

  /// Outbound TL0PICIDX emitted on the most recent primary packet (8-bit
  /// space, wraps at 0x100). -1 until the first packet with L=1.
  int lastOutTl0 = -1;

  /// Per-layer (rid → (picOffset, tl0Offset)) added on each layer-switch
  /// keyframe so subsequent packets on that layer line up with the
  /// outbound sequence.
  final Map<String, _LayerPicOffsets> _layers = {};

  /// True when the next keyframe on the named layer should re-establish
  /// the offset (because we just switched in).
  final Set<String> _needsRebase = {};

  /// Mark [rid] as the active layer; the next keyframe on it will
  /// re-base the picture-id offset. Idempotent.
  void onLayerSwitch(String rid) {
    _needsRebase.add(rid);
    _layers.remove(rid);
  }

  /// Rewrite the descriptor in [rtp] (mutating in place). Returns true
  /// when the packet was rewritten and should be forwarded; false when
  /// it should be dropped (no offset known yet for this layer because
  /// we haven't seen its first keyframe).
  bool rewrite({
    required String rid,
    required Uint8List rtp,
    required bool isKeyframe,
  }) {
    final payloadOff = rtpPayloadOffset(rtp);
    final desc = parseVp8Descriptor(rtp, payloadOff);
    if (desc == null) return true; // not a parseable VP8 packet — pass through

    var off = _layers[rid];
    if (off == null || _needsRebase.contains(rid)) {
      if (!isKeyframe) {
        // Can't establish the offset until a keyframe lands.
        return false;
      }
      // Base outbound id at lastOut+1 (or copy through on the very
      // first packet ever).
      final basePic =
          lastOutPicId < 0 ? (desc.pictureId ?? 0) : ((lastOutPicId + 1) & 0x7fff);
      final baseTl0 = lastOutTl0 < 0
          ? (desc.tl0PicIdx ?? 0)
          : ((lastOutTl0 + 1) & 0xff);
      off = _LayerPicOffsets(
        picOffset:
            ((basePic - (desc.pictureId ?? 0)) & 0x7fff),
        tl0Offset: ((baseTl0 - (desc.tl0PicIdx ?? 0)) & 0xff),
      );
      _layers[rid] = off;
      _needsRebase.remove(rid);
    }

    if (desc.pictureId != null && desc.pictureIdOffset >= 0) {
      final outPic = (desc.pictureId! + off.picOffset) & 0x7fff;
      _writePictureId(rtp, desc.pictureIdOffset, outPic, desc.pictureIdIsLong);
      lastOutPicId = outPic;
    }
    if (desc.tl0PicIdx != null && desc.tl0PicIdxOffset >= 0) {
      final outTl0 = (desc.tl0PicIdx! + off.tl0Offset) & 0xff;
      rtp[desc.tl0PicIdxOffset] = outTl0;
      lastOutTl0 = outTl0;
    }
    return true;
  }
}

class _LayerPicOffsets {
  final int picOffset;
  final int tl0Offset;
  const _LayerPicOffsets({required this.picOffset, required this.tl0Offset});
}

void _writePictureId(Uint8List rtp, int off, int picId, bool isLong) {
  if (isLong) {
    rtp[off] = 0x80 | ((picId >> 8) & 0x7f);
    rtp[off + 1] = picId & 0xff;
  } else {
    rtp[off] = picId & 0x7f;
  }
}
