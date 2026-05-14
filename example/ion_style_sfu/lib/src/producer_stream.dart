// Phase 2/3 — describe one published track.
//
// Populated by parsing the publisher's offer SDP (`a=ssrc`,
// `a=ssrc-group:FID`, `a=ssrc-group:SIM`, `a=msid`). For non-simulcast
// tracks [layers] has a single entry; for simulcast (SIM group) there
// are N entries (typically 3 — q/h/f), ordered low→high quality.

import 'producer_layer.dart';

class ProducerStream {
  /// 'audio' or 'video' (matches sdp_transform's `m['type']`).
  final String kind;

  /// `m['mid']`. Diagnostic only.
  final String mid;

  /// One entry per encoding layer. Length >= 1, ordered from lowest to
  /// highest quality. The last entry is the default forwarded layer.
  final List<ProducerLayer> layers;

  /// CNAME (defaults to publisher peer id when not declared).
  final String cname;

  /// MediaStream id (`<stream> <track>` first token). Defaults to the
  /// publisher peer id.
  final String msidStream;

  /// MediaStream track id (`<stream> <track>` second token). Defaults to
  /// `<peerId>-<kind>-<mid>`.
  final String msidTrack;

  /// extmap id of `urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id`, or
  /// null if the publisher didn't negotiate it. Required for routing
  /// modern (Chrome ≥ M71) simulcast where the publisher omits the
  /// `a=ssrc-group:SIM` group and only the RID header extension
  /// identifies the encoding layer.
  final int? ridExtId;

  /// extmap id of `urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id`,
  /// or null. Identifies the layer that an RTX packet retransmits when
  /// SSRCs are not pre-announced.
  final int? repairedRidExtId;

  ProducerStream._({
    required this.kind,
    required this.mid,
    required this.layers,
    required this.cname,
    required this.msidStream,
    required this.msidTrack,
    this.ridExtId,
    this.repairedRidExtId,
  }) : assert(layers.isNotEmpty, 'ProducerStream needs at least one layer');

  /// Single-layer factory (preserves the Phase 2 API).
  factory ProducerStream({
    required String kind,
    required String mid,
    required int primarySsrc,
    required int? rtxSsrc,
    required String cname,
    required String msidStream,
    required String msidTrack,
  }) =>
      ProducerStream._(
        kind: kind,
        mid: mid,
        cname: cname,
        msidStream: msidStream,
        msidTrack: msidTrack,
        layers: [
          ProducerLayer(rid: '', primarySsrc: primarySsrc, rtxSsrc: rtxSsrc),
        ],
      );

  /// Multi-layer factory used by SIM-group / RID-based simulcast.
  factory ProducerStream.simulcast({
    required String kind,
    required String mid,
    required List<ProducerLayer> layers,
    required String cname,
    required String msidStream,
    required String msidTrack,
    int? ridExtId,
    int? repairedRidExtId,
  }) =>
      ProducerStream._(
        kind: kind,
        mid: mid,
        cname: cname,
        msidStream: msidStream,
        msidTrack: msidTrack,
        layers: List.unmodifiable(layers),
        ridExtId: ridExtId,
        repairedRidExtId: repairedRidExtId,
      );

  /// Highest-quality layer — the default forwarded layer, and the one
  /// whose SSRC is mirrored onto the subscriber-facing track.
  ProducerLayer get defaultLayer => layers.last;

  /// Convenience: the default layer's primary SSRC. The subscriber-side
  /// SSRC allocator keys off this so all layers funnel into one
  /// outbound SSRC per subscriber.
  int get primarySsrc => defaultLayer.primarySsrc;

  /// Convenience: the default layer's RTX SSRC (or null).
  int? get rtxSsrc => defaultLayer.rtxSsrc;

  /// True when more than one encoding layer is present.
  bool get isSimulcast => layers.length > 1;

  /// All primary SSRCs across every layer. Used by the router to index
  /// the receiver under each layer's SSRC.
  Iterable<int> get allPrimarySsrcs => layers.map((l) => l.primarySsrc);

  /// All RTX SSRCs across every layer (skipping layers without RTX).
  Iterable<int> get allRtxSsrcs =>
      layers.where((l) => l.rtxSsrc != null).map((l) => l.rtxSsrc!);

  @override
  String toString() => 'ProducerStream($kind mid=$mid '
      '${isSimulcast ? "simulcast(${layers.map((l) => l.rid).join(",")})" : "primary=$primarySsrc"})';
}
