// Phase 6 — SFU-to-SFU relay.
//
// Mirrors `pkg/relay/`. A relay peer is a peer in the local session
// whose publisher/subscriber sit on the *other* SFU; signaling moves
// over a custom JSON envelope rather than browser WS, and the relay
// avoids the usual SDP renegotiation churn by pre-agreeing the codec
// set out of band.
//
// Phase 1 ships only the public API shape.

class RelayPeer {
  /// Stable id of the remote peer this relay represents.
  final String remoteId;

  /// True once the upstream SFU has acknowledged the relay handshake.
  bool established = false;

  RelayPeer(this.remoteId);

  /// Phase 6: serialize signal data for the remote SFU.
  List<int> handshake() => const [];
}
