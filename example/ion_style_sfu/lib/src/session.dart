// Session — a set of peers whose Publishers are auto-subscribed to each
// other. Mirrors `pkg/sfu/session.go` `SessionLocal`.

import 'dart:async';

import 'audio_observer.dart';
import 'peer.dart';
import 'receiver.dart';
import 'router.dart';
import 'sfu.dart';

typedef SessionEvent = void Function(Peer peer);

/// Phase B11 — fired when a publisher learns about a new track and that
/// track is broadcast to existing peers. Subscribers built lazily after
/// the publish call still see this event because [Session.publish] runs
/// before [SessionStreamTracker] forwards it.
typedef SessionTrackEvent = void Function(Router router, Receiver receiver);

/// One conferencing room. Holds the live peers and acts as the broadcast
/// hub when a publisher gets a new track (`publish`) or when a subscriber
/// joins (`subscribe`).
class Session {
  /// Stable session id (room id).
  final String id;

  /// SFU we belong to. Used by Router/Subscriber to allocate transports
  /// and to notify when this session goes idle.
  final Sfu sfu;

  /// peerId → Peer.
  final Map<String, Peer> _peers = {};

  /// All routers currently publishing into this session, keyed by peer id.
  /// Used so a freshly-joined subscriber can be subscribed to every
  /// existing producer in one pass.
  final Map<String, Router> _routers = {};

  /// Phase 4: audio observer (RFC 6464). Created up-front so callers can
  /// attach event listeners before the first peer joins. Started lazily
  /// when the first peer joins; stopped when the session goes idle.
  final AudioObserver audioObserver = AudioObserver();

  bool _closed = false;

  /// Fires when the peer count transitions 0→1.
  SessionEvent? onFirstPeer;

  /// Fires whenever a peer joins.
  SessionEvent? onPeerJoined;

  /// Fires whenever a peer leaves.
  SessionEvent? onPeerLeft;

  /// Phase B11 — fires whenever a publisher [publish]es a new track
  /// into this session. Used by `SessionStreamTracker` to keep its
  /// snapshot of live tracks in sync without having to poll.
  SessionTrackEvent? onTrackPublished;

  Session(this.id, this.sfu);

  bool get isClosed => _closed;

  Iterable<Peer> get peers => _peers.values;

  Peer? getPeer(String peerId) => _peers[peerId];

  /// Number of live peers.
  int get peerCount => _peers.length;

  /// Add [peer] to this session. Called by [Peer.join].
  void addPeer(Peer peer) {
    if (_closed) {
      throw StateError('Session $id is closed');
    }
    final wasEmpty = _peers.isEmpty;
    _peers[peer.id] = peer;
    if (wasEmpty) {
      audioObserver.start();
      onFirstPeer?.call(peer);
    }
    onPeerJoined?.call(peer);
  }

  /// Remove [peer] from this session. Called by [Peer.close].
  void removePeer(Peer peer) {
    final removed = _peers.remove(peer.id);
    if (removed == null) return;
    _routers.remove(peer.id);
    onPeerLeft?.call(peer);
    if (_peers.isEmpty) {
      audioObserver.stop();
      // Idle session — let the SFU drop us. Phase 8 may keep sessions
      // warm for a configurable grace period.
      sfu.removeSession(id);
    }
  }

  /// Called by a [Publisher] when it learns about a new producer track.
  /// Wires the [receiver] up to every other peer's subscriber.
  ///
  /// Mirrors `Session.Publish(router, receiver)`.
  void publish(Router router, Receiver receiver) {
    _routers[router.peerId] = router;
    for (final p in _peers.values) {
      if (p.id == router.peerId) continue;
      p.subscriber?.addReceiver(receiver);
    }
    onTrackPublished?.call(router, receiver);
  }

  /// Subscribe [peer] to every existing producer track. Called from
  /// [Peer.join] when `noAutoSubscribe` is false.
  ///
  /// Mirrors `Session.Subscribe(peer)`.
  void subscribe(Peer peer) {
    final sub = peer.subscriber;
    if (sub == null) return;
    for (final r in _routers.values) {
      if (r.peerId == peer.id) continue;
      for (final receiver in r.receivers) {
        sub.addReceiver(receiver);
      }
    }
  }

  /// All routers currently producing into this session.
  Iterable<Router> get routers => _routers.values;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final all = _peers.values.toList();
    _peers.clear();
    _routers.clear();
    await Future.wait(all.map((p) => p.close()));
    audioObserver.dispose();
  }
}
