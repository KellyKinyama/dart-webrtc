// Phase 4 — RFC 6464 audio level observer.
//
// Mirrors `pkg/sfu/audioobserver.go`. Producers tagged with the
// audio-level RTP header extension contribute their dBov reading; the
// observer publishes a periodic "loudest N speakers" snapshot.
//
// Phase 4 will:
//   * Parse the audio-level extension (one-byte form, ID 1).
//   * Maintain an EMA of -dBov per producer ssrc.
//   * Fire [onSpeakers] every [interval] with the top-K loudest.
//
// Phase 1 ships an empty observer so wiring sites compile.

import 'dart:async';

class AudioObserverEvent {
  /// Producer track ids (`<peerId>:<mid>`) currently considered active,
  /// loudest first.
  final List<String> speakers;
  const AudioObserverEvent(this.speakers);
}

class AudioObserver {
  /// Snapshot interval. Phase 4 will sample at this cadence.
  final Duration interval;

  /// Threshold in -dBov above which a stream counts as "active".
  /// 0 = silence, 127 = loudest. Lower threshold == stricter "active".
  final int threshold;

  /// Top-K active speakers to emit per snapshot.
  final int filter;

  final StreamController<AudioObserverEvent> _ctl =
      StreamController<AudioObserverEvent>.broadcast();

  AudioObserver({
    this.interval = const Duration(milliseconds: 1000),
    this.threshold = 40,
    this.filter = 3,
  });

  Stream<AudioObserverEvent> get events => _ctl.stream;

  /// Phase 4: feed an RTP audio-level observation. No-op for now.
  void observe(String trackId, int dBov) {
    // PHASE 4: maintain rolling stats and emit AudioObserverEvent.
  }

  void dispose() {
    _ctl.close();
  }
}
