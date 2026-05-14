// Peer — pairs a Publisher PeerConnection (client→server media) with a
// Subscriber PeerConnection (server→client media). Mirrors
// `pkg/sfu/peer.go` `PeerLocal`.

import 'dart:async';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

import 'publisher.dart';
import 'session.dart';
import 'sfu.dart';
import 'subscriber.dart';

/// Knobs equivalent to ion-sfu's `JoinConfig`.
class PeerJoinConfig {
  /// If true, no Publisher PC is created — the peer is subscribe-only.
  final bool noPublish;

  /// If true, no Subscriber PC is created — the peer is publish-only.
  final bool noSubscribe;

  /// If true and `noSubscribe` is false, the peer is *not* automatically
  /// subscribed to existing producers; the caller must call
  /// `subscriber.addReceiver` explicitly. Useful for SFU clients that
  /// pick which streams to receive.
  final bool noAutoSubscribe;

  const PeerJoinConfig({
    this.noPublish = false,
    this.noSubscribe = false,
    this.noAutoSubscribe = false,
  });
}

/// Peer = (Publisher PC, Subscriber PC) bound to one session.
///
/// The publisher PC is offered by the **client** (browser → server).
/// The subscriber PC is offered by the **server** whenever a producer
/// joins or leaves; the client always answers. This split mirrors
/// ion-sfu's two-PC model.
class Peer {
  final SessionProvider _provider;

  String _id = '';
  Session? _session;
  Publisher? _publisher;
  Subscriber? _subscriber;
  bool _closed = false;

  /// Fired when the Subscriber PC needs to (re)negotiate. The signaling
  /// layer must call [createSubscriberOffer] and ship the SDP.
  void Function()? onSubscriberNegotiationNeeded;

  /// Fired with each ICE candidate gathered on the Publisher PC. The
  /// signaling layer must trickle these to the client with `target:"pub"`.
  void Function(RTCIceCandidate? candidate)? onPublisherIceCandidate;

  /// Fired with each ICE candidate gathered on the Subscriber PC.
  /// Trickle these with `target:"sub"`.
  void Function(RTCIceCandidate? candidate)? onSubscriberIceCandidate;

  /// Fired when either PC's ICE state changes.
  void Function(String target, RTCIceConnectionState state)?
      onIceConnectionStateChange;

  Peer(this._provider);

  String get id => _id;
  Session? get session => _session;
  Publisher? get publisher => _publisher;
  Subscriber? get subscriber => _subscriber;
  bool get isClosed => _closed;

  /// Initialise this peer for [sid] (room) with stable id [uid]. Creates
  /// the Publisher and Subscriber transports per [joinConfig].
  ///
  /// Mirrors `PeerLocal.Join(sid, uid, JoinConfig)`.
  Future<void> join({
    required String sid,
    required String uid,
    PeerJoinConfig joinConfig = const PeerJoinConfig(),
  }) async {
    if (_session != null) {
      throw StateError('Peer already joined session ${_session!.id}');
    }
    _id = uid;
    final session = _provider.getSession(sid);
    _session = session;

    if (!joinConfig.noPublish) {
      _publisher = await Publisher.create(
        peerId: uid,
        session: session,
      );
      _publisher!.onIceCandidate = (c) => onPublisherIceCandidate?.call(c);
      _publisher!.onIceConnectionStateChange =
          (s) => onIceConnectionStateChange?.call('pub', s);
    }

    if (!joinConfig.noSubscribe) {
      _subscriber = await Subscriber.create(
        peerId: uid,
        session: session,
      );
      _subscriber!.noAutoSubscribe = joinConfig.noAutoSubscribe;
      _subscriber!.onNegotiationNeeded =
          () => onSubscriberNegotiationNeeded?.call();
      _subscriber!.onIceCandidate = (c) => onSubscriberIceCandidate?.call(c);
      _subscriber!.onIceConnectionStateChange =
          (s) => onIceConnectionStateChange?.call('sub', s);
    }

    session.addPeer(this);

    if (!joinConfig.noSubscribe && !joinConfig.noAutoSubscribe) {
      session.subscribe(this);
    }
  }

  // ---- Publisher signaling --------------------------------------------

  /// Apply the client's publisher offer and produce the server's answer.
  Future<RTCSessionDescription> answerPublisherOffer(String offerSdp) {
    final pub = _publisher;
    if (pub == null) {
      throw StateError('Peer $_id has noPublish=true');
    }
    return pub.answerOffer(offerSdp);
  }

  Future<void> addPublisherIceCandidate(RTCIceCandidate? candidate) async {
    await _publisher?.pc.addIceCandidate(candidate);
  }

  // ---- Subscriber signaling -------------------------------------------

  /// Build a server-side offer for the Subscriber PC. The signaling
  /// layer ships this SDP to the client with `target:"sub"`.
  Future<RTCSessionDescription> createSubscriberOffer() {
    final sub = _subscriber;
    if (sub == null) {
      throw StateError('Peer $_id has noSubscribe=true');
    }
    return sub.createOffer();
  }

  /// Apply the client's answer to a server-issued subscriber offer.
  Future<void> setSubscriberAnswer(String answerSdp) {
    final sub = _subscriber;
    if (sub == null) {
      throw StateError('Peer $_id has noSubscribe=true');
    }
    return sub.setAnswer(answerSdp);
  }

  Future<void> addSubscriberIceCandidate(RTCIceCandidate? candidate) async {
    await _subscriber?.pc.addIceCandidate(candidate);
  }

  // ---- Lifecycle -------------------------------------------------------

  /// Tear both PeerConnections down and remove from the session.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _publisher?.close();
    _subscriber?.close();
    _session?.removePeer(this);
  }
}
