// Phase 2 — describe one published track.
//
// Populated by parsing the publisher's offer SDP (`a=ssrc`,
// `a=ssrc-group:FID`, `a=msid`).

class ProducerStream {
  /// 'audio' or 'video' (matches sdp_transform's `m['type']`).
  final String kind;

  /// `m['mid']`. Diagnostic only.
  final String mid;

  /// Primary RTP SSRC the publisher sends on.
  final int primarySsrc;

  /// RTX SSRC paired with [primarySsrc] via `a=ssrc-group:FID`. Null if
  /// the publisher didn't negotiate RTX.
  final int? rtxSsrc;

  /// CNAME (defaults to publisher peer id when not declared).
  final String cname;

  /// MediaStream id (`<stream> <track>` first token). Defaults to the
  /// publisher peer id.
  final String msidStream;

  /// MediaStream track id (`<stream> <track>` second token). Defaults to
  /// `<peerId>-<kind>-<mid>`.
  final String msidTrack;

  const ProducerStream({
    required this.kind,
    required this.mid,
    required this.primarySsrc,
    required this.rtxSsrc,
    required this.cname,
    required this.msidStream,
    required this.msidTrack,
  });

  @override
  String toString() => 'ProducerStream($kind mid=$mid primary=$primarySsrc'
      '${rtxSsrc == null ? '' : ' rtx=$rtxSsrc'})';
}
