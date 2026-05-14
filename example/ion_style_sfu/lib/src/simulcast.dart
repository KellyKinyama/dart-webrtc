// Phase 3 — simulcast layer selection (q/h/f).
//
// Mirrors `pkg/sfu/simulcast.go`. ion-sfu tracks three RIDs per
// publisher and picks the best layer per subscriber; switches issue a
// PLI to force a keyframe on the new layer.
//
// Phase 1 ships only the type sketch.

enum SimulcastLayer { quarter, half, full }

class SimulcastConfig {
  /// Send the highest layer first when a new subscriber lands.
  final bool bestQualityFirst;

  /// Apply VP8 temporal-layer trimming.
  final bool enableTemporalLayer;

  const SimulcastConfig({
    this.bestQualityFirst = false,
    this.enableTemporalLayer = false,
  });
}

class SimulcastTrackHelpers {
  SimulcastLayer current = SimulcastLayer.full;
  SimulcastLayer target = SimulcastLayer.full;
  DateTime? switchAt;
  // PHASE 3: VP8 temporal helpers (refPicID, lTlZIdx, …).
}
