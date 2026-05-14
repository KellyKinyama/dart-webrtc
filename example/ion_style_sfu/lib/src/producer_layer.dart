// Phase 3 — one encoding layer of a (potentially simulcast) producer.
//
// For non-simulcast tracks, [ProducerStream.layers] holds a single
// layer whose [rid] is empty. For simulcast (SIM SSRC group, or RID-
// based, or SVC), each layer carries its own primary + optional RTX
// SSRC.

class ProducerLayer {
  /// RID name (`'q'`, `'h'`, `'f'`, …) or empty string for the
  /// non-simulcast/default layer. Diagnostic only — routing is by SSRC.
  final String rid;

  /// Primary RTP SSRC the publisher sends this layer on.
  final int primarySsrc;

  /// Paired RTX SSRC (RFC 4588) for this layer, or null when not
  /// negotiated.
  final int? rtxSsrc;

  const ProducerLayer({
    required this.rid,
    required this.primarySsrc,
    required this.rtxSsrc,
  });

  @override
  String toString() => 'ProducerLayer($rid primary=$primarySsrc'
      '${rtxSsrc == null ? '' : ' rtx=$rtxSsrc'})';
}
