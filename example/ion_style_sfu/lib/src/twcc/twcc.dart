// Phase 5 — Transport-Wide Congestion Control feedback.
//
// Mirrors `pkg/twcc/`. Receivers stamp inbound packets with the
// transport-wide sequence header extension and the SFU emits periodic
// TWCC feedback packets so the publisher can run a congestion
// controller (typically GCC).
//
// Phase 1: just the empty type so wiring sites compile.

class TwccResponder {
  /// Phase 5: feed the inbound TWCC sequence + timestamp.
  void observePacket(int twSeq, DateTime arrived) {}

  /// Phase 5: build and send an `RTPFB FMT=15` packet.
  void buildFeedback() {}
}
