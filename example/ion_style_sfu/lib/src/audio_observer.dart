// Phase 4 — RFC 6464 audio level observer.
//
// Mirrors `pkg/sfu/audioobserver.go`. Producers tagged with the RFC 6464
// ssrc-audio-level RTP header extension contribute their dBov readings;
// the observer publishes a periodic snapshot of the loudest active
// speakers.
//
// The level value carried in the extension is `-dBov` (RFC 6464 § 3):
//   0   → 0 dBov (loudest possible) → "very loud"
//   127 → -127 dBov (or below)      → silence
//
// Internally we store an EMA of `(127 - level)` so larger values mean
// louder, which makes thresholds and ordering intuitive.

import 'dart:async';

class AudioObserverEvent {
  /// Producer track ids (`<peerId>:<mid>`) currently considered active,
  /// loudest first.
  final List<String> speakers;

  /// Per-track loudness scores (`127 - level`, EMA-smoothed) for every
  /// speaker in [speakers], same order. Useful for tie-break logic on
  /// the consumer side.
  final List<double> scores;

  const AudioObserverEvent(this.speakers, this.scores);

  @override
  String toString() {
    final parts = <String>[];
    for (var i = 0; i < speakers.length; i++) {
      parts.add('${speakers[i]}=${scores[i].toStringAsFixed(1)}');
    }
    return 'AudioObserverEvent(${parts.join(', ')})';
  }
}

class _Track {
  /// EMA of `127 - level`. Higher means louder.
  double ema = 0.0;

  /// Most recent V flag.
  bool voice = false;

  /// Tick of the last observation (so we can decay silent tracks).
  int lastTick = 0;
}

class AudioObserver {
  /// Snapshot interval. The first event fires one [interval] after
  /// [start] is called.
  final Duration interval;

  /// Loudness floor, in `127 - level` units (so larger == louder). A
  /// track must score ≥ [threshold] in the latest snapshot to count
  /// as "active". The default of 40 corresponds to roughly -87 dBov;
  /// most desktop browsers report -127..-30 for typical speech.
  final int threshold;

  /// Top-K active speakers to emit per snapshot.
  final int filter;

  /// EMA smoothing factor in `[0, 1]`. Higher == more reactive.
  final double smoothing;

  final StreamController<AudioObserverEvent> _ctl =
      StreamController<AudioObserverEvent>.broadcast();

  final Map<String, _Track> _tracks = {};
  Timer? _timer;
  int _tick = 0;
  bool _disposed = false;

  AudioObserver({
    this.interval = const Duration(milliseconds: 1000),
    this.threshold = 40,
    this.filter = 3,
    this.smoothing = 0.5,
  })  : assert(filter > 0, 'filter must be > 0'),
        assert(smoothing > 0 && smoothing <= 1, 'smoothing in (0,1]');

  Stream<AudioObserverEvent> get events => _ctl.stream;

  /// Start the periodic snapshot timer. Idempotent.
  void start() {
    if (_disposed || _timer != null) return;
    _timer = Timer.periodic(interval, (_) => _emit());
  }

  /// Stop the timer (without disposing the controller).
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Forget any state for [trackId] (called on receiver close).
  void forget(String trackId) {
    _tracks.remove(trackId);
  }

  /// Feed one RFC 6464 audio-level observation. [level] is the raw
  /// extension value (0 = loudest, 127 = silence). [voice] reflects
  /// the V flag.
  void observe(String trackId, int level, {bool voice = false}) {
    if (_disposed) return;
    final loudness = (127 - (level & 0x7f)).toDouble();
    final t = _tracks.putIfAbsent(trackId, _Track.new);
    t.ema = t.ema + smoothing * (loudness - t.ema);
    t.voice = voice;
    t.lastTick = _tick;
  }

  /// Force an immediate snapshot. Mostly useful for tests; production
  /// callers should rely on [start] + [interval].
  void emitNow() => _emit();

  void _emit() {
    if (_disposed) return;
    // Decay tracks that did not observe since the previous emit. We
    // compare against the current _tick (which observe() also writes
    // into the track), then bump _tick so the next interval starts a
    // fresh "did anyone observe?" window.
    for (final t in _tracks.values) {
      if (t.lastTick < _tick) {
        t.ema *= (1 - smoothing);
      }
    }
    _tick++;
    final entries = _tracks.entries
        .where((e) => e.value.ema >= threshold)
        .toList(growable: false)
      ..sort((a, b) => b.value.ema.compareTo(a.value.ema));

    final top = entries.take(filter).toList(growable: false);
    final speakers = [for (final e in top) e.key];
    final scores = [for (final e in top) e.value.ema];
    if (!_ctl.isClosed) {
      _ctl.add(AudioObserverEvent(speakers, scores));
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _tracks.clear();
    _ctl.close();
  }
}
