// lib/src/vpx_enums.dart
// ignore_for_file: constant_identifier_names

/// Enum for VP8 encoder control IDs.
enum Vp8eEncControlId {
  VP8E_SET_CPUUSED(13),
  VP8E_SET_NOISE_SENSITIVITY(15),
  VP8E_SET_STATIC_THRESHOLD(17),
  VP8E_SET_TOKEN_PARTITIONS(18);

  final int value;
  const Vp8eEncControlId(this.value);
}

/// Enum for VPX codec error codes.
enum VpxCodecErrT {
  VPX_CODEC_OK(0),
  VPX_CODEC_ERROR(1),
  VPX_CODEC_MEM_ERROR(2),
  VPX_CODEC_ABI_MISMATCH(3),
  VPX_CODEC_INCAPABLE(4),
  VPX_CODEC_UNSUP_BITSTREAM(5),
  VPX_CODEC_UNSUP_FEATURE(6),
  VPX_CODEC_CORRUPT_FRAME(7),
  VPX_CODEC_INVALID_PARAM(8),
  VPX_CODEC_LIST_END(9);

  final int value;
  const VpxCodecErrT(this.value);
}

/// Enum for VPX bit depth.
enum VpxBitDepthT {
  VPX_BITS_8(8),
  VPX_BITS_10(10),
  VPX_BITS_12(12);

  final int value;
  const VpxBitDepthT(this.value);
}

/// Enum for VPX encoding pass.
enum VpxEncPass {
  VPX_RC_ONE_PASS(0),
  VPX_RC_FIRST_PASS(1),
  VPX_RC_LAST_PASS(2);

  final int value;
  const VpxEncPass(this.value);
}

/// Enum for VPX rate control mode.
enum VpxRcMode {
  VPX_VBR(0),
  VPX_CBR(1),
  VPX_CQ(2),
  VPX_Q(3);

  final int value;
  const VpxRcMode(this.value);
}

/// Enum for VPX keyframe mode.
enum VpxKfMode {
  VPX_KF_FIXED(0),
  VPX_KF_AUTO(1),
  VPX_KF_DISABLED(2);

  final int value;
  const VpxKfMode(this.value);
}

/// Enum for VPX image format.
enum VpxImgFmtT {
  VPX_IMG_FMT_NONE(0),
  VPX_IMG_FMT_I420(258); // Assuming this is the primary one from PHP code

  final int value;
  const VpxImgFmtT(this.value);
}

/// Enum for VPX color space.
enum VpxColorSpaceT {
  VPX_CS_UNKNOWN(0),
  VPX_CS_BT_601(1),
  VPX_CS_BT_709(2),
  VPX_CS_SMPTE_170(3),
  VPX_CS_SMPTE_240(4),
  VPX_CS_BT_2020(5),
  VPX_CS_RESERVED(6),
  VPX_CS_SRGB(7);

  final int value;
  const VpxColorSpaceT(this.value);
}

/// Enum for VPX color range.
enum VpxColorRangeT {
  VPX_CR_STUDIO_RANGE(0),
  VPX_CR_FULL_RANGE(1);

  final int value;
  const VpxColorRangeT(this.value);
}

/// Enum for VPX codec output packet kind.
enum VpxCodecCxPktKind {
  VPX_CODEC_CX_FRAME_PKT(0),
  VPX_CODEC_STATS_PKT(1),
  VPX_CODEC_FPMB_STATS_PKT(2),
  VPX_CODEC_PSNR_PKT(3),
  VPX_CODEC_CUSTOM_PKT(256);

  final int value;
  const VpxCodecCxPktKind(this.value);
}

/// Enum for codec interfaces (used by Config and Encoder/Decoder).
enum BriefInterface {
  VP8_CX('vpx_codec_vp8_cx'),
  VP8_DX('vpx_codec_vp8_dx'),
  VP9_CX('vpx_codec_vp9_cx'), // Assuming VP9 exists based on PHP comments
  VP9_DX('vpx_codec_vp9_dx'); // Assuming VP9 exists based on PHP comments

  final String functionName;
  const BriefInterface(this.functionName);
}
