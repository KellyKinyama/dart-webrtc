// Phase 5 — Receiver Estimated Maximum Bitrate (REMB) and SR/RR plumbing.
//
// Mirrors the bandwidth-estimation slice of ion-sfu's twcc/buffer.

class RembEstimator {
  /// Most-recent estimate (bps) for the publisher feeding this estimator.
  int currentBps = 0;

  /// Phase 5: GCC-style estimator update on each RTCP sender-report
  /// or arrival timestamp.
  void onArrival(int sizeBytes, DateTime t) {}

  /// Phase 5: build an RTCP PSFB FMT=15 (REMB) message addressed to
  /// the publisher's SSRC.
  void buildRemb() {}
}
