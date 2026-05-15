// Phase B11 — per-Session aggregator that maintains a live snapshot of
// every published track and emits events when peers join/leave or when
// a publisher contributes a new track. Designed to back a `/streams`
// debug endpoint and the upcoming quality-scorer (B12) without each
// consumer having to walk Session.routers → receivers themselves.
//
// The tracker chains existing Session callbacks (onPeerJoined,
// onPeerLeft, onTrackPublished) so an external owner that already
// subscribes to those hooks keeps working — the tracker's listener
// runs after the previously-installed one.

import 'dart:async';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart' show MediaKind;

import 'peer.dart';
import 'producer_layer.dart';
import 'receiver.dart';
import 'router.dart';
import 'session.dart';

/// Snapshot of one currently-published track.
class TrackInfo {
  /// Stable receiver id — `<peerId>:<mid>`.
  final String trackId;

  /// Owning publisher peer id.
  final String peerId;

  /// `audio` or `video`.
  final MediaKind kind;

  /// Default-layer primary SSRC (0 if not bound yet).
  final int primarySsrc;

  /// Default-layer RTX SSRC (null if not negotiated).
  final int? rtxSsrc;

  /// Per-layer descriptors. For non-simulcast tracks this has one entry
  /// with [LayerInfo.rid] == ''.
  final List<LayerInfo> layers;

  /// First negotiated codec name (e.g. `VP8`, `opus`). Null when the
  /// router hasn't bound any codecs yet.
  final String? codec;

  // Live counters — captured at snapshot time.
  final int packetsReceived;
  final int bytesReceived;
  final int packetsLost;
  final int rtxPacketsReceived;
  final int jitter;

  const TrackInfo({
    required this.trackId,
    required this.peerId,
    required this.kind,
    required this.primarySsrc,
    required this.rtxSsrc,
    required this.layers,
    required this.codec,
    required this.packetsReceived,
    required this.bytesReceived,
    required this.packetsLost,
    required this.rtxPacketsReceived,
    required this.jitter,
  });

  factory TrackInfo.fromReceiver(Receiver r) {
    return TrackInfo(
      trackId: r.id,
      peerId: r.peerId,
      kind: r.kind,
      primarySsrc: r.primarySsrc,
      rtxSsrc: r.rtxSsrc,
      layers: r.layers.map(LayerInfo.fromLayer).toList(growable: false),
      codec: r.codecs.isEmpty ? null : r.codecs.first.name,
      packetsReceived: r.packetsReceived,
      bytesReceived: r.bytesReceived,
      packetsLost: r.packetsLost,
      rtxPacketsReceived: r.rtxPacketsReceived,
      jitter: r.jitter,
    );
  }

  bool get isSimulcast => layers.length > 1;

  Map<String, Object?> toJson() => {
        'trackId': trackId,
        'peerId': peerId,
        'kind': kind == MediaKind.audio ? 'audio' : 'video',
        'primarySsrc': primarySsrc,
        if (rtxSsrc != null) 'rtxSsrc': rtxSsrc,
        if (codec != null) 'codec': codec,
        'simulcast': isSimulcast,
        'layers': layers.map((l) => l.toJson()).toList(),
        'packetsReceived': packetsReceived,
        'bytesReceived': bytesReceived,
        'packetsLost': packetsLost,
        'rtxPacketsReceived': rtxPacketsReceived,
        'jitter': jitter,
      };

  @override
  String toString() => 'TrackInfo($trackId kind=$kind ssrc=$primarySsrc'
      '${isSimulcast ? ' simulcast(${layers.length})' : ''})';
}

/// Per-encoding layer descriptor.
class LayerInfo {
  final String rid;
  final int primarySsrc;
  final int? rtxSsrc;

  const LayerInfo({
    required this.rid,
    required this.primarySsrc,
    required this.rtxSsrc,
  });

  factory LayerInfo.fromLayer(ProducerLayer l) => LayerInfo(
        rid: l.rid,
        primarySsrc: l.primarySsrc,
        rtxSsrc: l.rtxSsrc,
      );

  Map<String, Object?> toJson() => {
        'rid': rid,
        'primarySsrc': primarySsrc,
        if (rtxSsrc != null) 'rtxSsrc': rtxSsrc,
      };
}

enum StreamEventKind { peerJoined, peerLeft, trackPublished }

/// Stream-event delivered on [SessionStreamTracker.events].
class StreamEvent {
  final StreamEventKind kind;
  final String sessionId;
  final String peerId;

  /// Populated only for [StreamEventKind.trackPublished].
  final TrackInfo? track;

  const StreamEvent({
    required this.kind,
    required this.sessionId,
    required this.peerId,
    this.track,
  });

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'sessionId': sessionId,
        'peerId': peerId,
        if (track != null) 'track': track!.toJson(),
      };

  @override
  String toString() =>
      'StreamEvent(${kind.name} session=$sessionId peer=$peerId'
      '${track == null ? '' : ' track=${track!.trackId}'})';
}

/// Aggregates publish/peer state for a single [Session]. Construct via
/// [attach], dispose via [dispose] to restore the previously-installed
/// callbacks.
class SessionStreamTracker {
  final Session session;

  final SessionEvent? _prevJoined;
  final SessionEvent? _prevLeft;
  final SessionTrackEvent? _prevPublished;

  final StreamController<StreamEvent> _events =
      StreamController<StreamEvent>.broadcast();

  bool _disposed = false;

  SessionStreamTracker._(
    this.session,
    this._prevJoined,
    this._prevLeft,
    this._prevPublished,
  );

  /// Wire [tracker] up to [session]. Chains any callbacks the caller
  /// already installed so existing logic keeps firing.
  factory SessionStreamTracker.attach(Session session) {
    final tracker = SessionStreamTracker._(
      session,
      session.onPeerJoined,
      session.onPeerLeft,
      session.onTrackPublished,
    );

    session.onPeerJoined = (Peer peer) {
      tracker._prevJoined?.call(peer);
      if (tracker._disposed || tracker._events.isClosed) return;
      tracker._events.add(StreamEvent(
        kind: StreamEventKind.peerJoined,
        sessionId: session.id,
        peerId: peer.id,
      ));
    };
    session.onPeerLeft = (Peer peer) {
      tracker._prevLeft?.call(peer);
      if (tracker._disposed || tracker._events.isClosed) return;
      tracker._events.add(StreamEvent(
        kind: StreamEventKind.peerLeft,
        sessionId: session.id,
        peerId: peer.id,
      ));
    };
    session.onTrackPublished = (Router router, Receiver receiver) {
      tracker._prevPublished?.call(router, receiver);
      if (tracker._disposed || tracker._events.isClosed) return;
      tracker._events.add(StreamEvent(
        kind: StreamEventKind.trackPublished,
        sessionId: session.id,
        peerId: router.peerId,
        track: TrackInfo.fromReceiver(receiver),
      ));
    };

    return tracker;
  }

  /// Stream of join/leave/publish events. Multi-listener safe.
  Stream<StreamEvent> get events => _events.stream;

  /// Snapshot of every track currently published into the session.
  /// Order is stable per-router, but routers are not sorted.
  List<TrackInfo> snapshot() {
    final out = <TrackInfo>[];
    for (final router in session.routers) {
      for (final r in router.receivers) {
        out.add(TrackInfo.fromReceiver(r));
      }
    }
    return out;
  }

  /// JSON-friendly snapshot for `/streams` style debug endpoints.
  Map<String, Object?> snapshotJson() {
    final tracks = snapshot();
    var audioCount = 0;
    var videoCount = 0;
    for (final t in tracks) {
      if (t.kind == MediaKind.audio) {
        audioCount++;
      } else {
        videoCount++;
      }
    }
    return {
      'sessionId': session.id,
      'peerCount': session.peerCount,
      'trackCount': tracks.length,
      'audioTracks': audioCount,
      'videoTracks': videoCount,
      'tracks': tracks.map((t) => t.toJson()).toList(),
    };
  }

  /// Restore the previously-installed Session callbacks and close the
  /// event stream. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Only restore if Session is still pointing at our chained closure.
    // If somebody else replaced the callback in the meantime we leave
    // theirs in place rather than clobbering it.
    session.onPeerJoined = _prevJoined;
    session.onPeerLeft = _prevLeft;
    session.onTrackPublished = _prevPublished;
    await _events.close();
  }
}
