# 2. Sfu, Session, Peer

The three-tier registry that owns everything else. This is the
shortest chapter — these classes are pure bookkeeping — but it pays
to read it before chapters 3–5 because everything past here has a
parent in this hierarchy.

---

## 2.1. The hierarchy

```
Sfu                ← one per shard / isolate
  └── Session      ← one per room (sid)
        ├── Peer   ← one per participant (uid)
        │     ├── Publisher    (uplink PC)
        │     └── Subscriber   (downlink PC)
        ├── Peer
        │     └── ...
        └── Router (×N, one per Publisher with media)
              └── Receiver (×M, one per published track)
```

Ownership = "I delete it when I'm closed". A Session deletes its
Peers; a Peer deletes its Publisher/Subscriber; the parent isolate
deletes the Sfu.

---

## 2.2. `Sfu`

File: [`lib/src/sfu.dart`](../../example/ion_style_sfu/lib/src/sfu.dart).

```dart
class Sfu implements SessionProvider {
  Sfu(WebRTCTransportConfig config);

  int allocatePort();
  Session getSession(String sid);   // creates if absent
  Future<void> close();
}
```

* Holds `_sessions: Map<String, Session>`.
* Hands out **UDP ports**: each call to `allocatePort()` returns
  the next port from the shard's reserved range (`rtpBase +
  shardSlot * portsPerShard + offset`). Publishers and Subscribers
  each take one — so a 50-peer room consumes 100 UDP ports.
* `close()` shuts down every session, which cascades to peers,
  which cascades to PCs and transports.

`SessionProvider` is the narrow interface `Peer` depends on (so
tests can substitute a fake `Sfu`).

---

## 2.3. `Session`

File: [`lib/src/session.dart`](../../example/ion_style_sfu/lib/src/session.dart).

```dart
class Session {
  Session(String id, Sfu sfu);

  void addPeer(Peer peer);
  void removePeer(Peer peer);
  void publish(Router router, Receiver receiver);  // a publisher started a track
  void subscribe(Peer peer);                       // attach to all existing producers
  Future<void> close();

  AudioObserver get audioObserver;                 // active-speaker (chapter 10)
  // event hooks
  void Function()? onFirstPeer;
  void Function(String uid)? onPeerJoined;
  void Function(String uid)? onPeerLeft;
  void Function(SessionTrackEvent ev)? onTrackPublished;
}
```

Two responsibilities:

1. **Membership**: peers come and go; emit events upward.
2. **Track fan-out**: when any peer publishes a track, *every other
   peer's* Subscriber needs to grow a DownTrack for it. That's
   what `publish(router, receiver)` does — it walks `_peers`,
   calls `subscriber.addReceiver(receiver)` on each (skipping the
   publisher itself), which spawns the DownTrack.

`removePeer` is the mirror: closes the peer, then for each
*remaining* peer's subscribers, removes any DownTrack that pointed
to a Receiver owned by the leaving peer's Router.

When `_peers` becomes empty:

* `audioObserver.stop()`
* `Sfu` removes the session from its map
* The shard's idle-timer can fire `idleSessionTimeoutMs` later
  and trigger `SessionShard.close()` (chapter 9)

---

## 2.4. `Peer`

File: [`lib/src/peer.dart`](../../example/ion_style_sfu/lib/src/peer.dart).

```dart
class Peer {
  Peer(SessionProvider provider);

  Future<void> join({
    required String sid,
    required String uid,
    PeerJoinConfig joinConfig,
  });

  Future<RTCSessionDescription> answerPublisherOffer(String offerSdp);
  Future<RTCSessionDescription> createSubscriberOffer();
  Future<void> setSubscriberAnswer(String sdp);
  Future<void> addPublisherIceCandidate(RTCIceCandidate c);
  Future<void> addSubscriberIceCandidate(RTCIceCandidate c);
  Future<void> close();

  // Wired from sfu_server.dart so SDP/ICE produced by the
  // PC bubbles back out as a JSON `trickle` / `offer`.
  void Function(RTCIceCandidate)?     onPublisherIceCandidate;
  void Function(RTCIceCandidate)?     onSubscriberIceCandidate;
  void Function(RTCSessionDescription)? onSubscriberNegotiationNeeded;
}
```

`join()` does the heavy work:

1. Look up `Session` from the `SessionProvider`.
2. Construct a `Publisher` (which constructs an `RtcUdpTransport`
   on a port from `Sfu.allocatePort()`, and the `RTCPeerConnection`
   bound to it).
3. Construct a `Subscriber` (same, plus its own
   `SsrcAllocator`/`BandwidthEstimator`/`TwccStamper`/`Pacer`).
4. Wire `Publisher.router` ↔ `Session` so receivers from this peer
   fan out.
5. `session.addPeer(this)`. This may also call
   `subscriber.addReceiver(...)` for every existing track in the
   room (so a late joiner immediately sees existing publishers).

After `join()`, the peer is "live" — but no media flows yet because
the **client hasn't sent a publisher offer**.

`answerPublisherOffer(sdp)` is the next step: it parses the SDP,
binds the Router (chapter 4), and answers. From that moment on, RTP
arriving on the Publisher's transport goes through the hot path.

---

## 2.5. Lifecycle diagram

```
new Peer(sfu)
    │
    ▼
peer.join(sid, uid)
    ├── Sfu.getSession(sid)         ← creates Session if first peer
    ├── new Publisher(...)
    ├── new Subscriber(...)
    └── session.addPeer(this)       ← fires onPeerJoined; adds existing receivers to subscriber
    │
    ▼
peer.answerPublisherOffer(sdp)
    ├── publisher.answerOffer(sdp)
    │     ├── transport.start()      ← ICE → DTLS → SRTP
    │     ├── parse SDP, allocate Receivers, bind to Router
    │     └── return answer SDP
    └── for each receiver: session.publish(router, receiver)
          └── for each other peer: subscriber.addReceiver(receiver)
    │
    ▼
... media flows ...
    │
    ▼
peer.close()
    ├── publisher.close()
    │     ├── for each receiver: session.unpublish(router, receiver)
    │     └── transport.close()
    ├── subscriber.close()
    │     ├── for each downTrack: dispose
    │     └── transport.close()
    └── session.removePeer(this)
          └── if last peer: session.close() → Sfu drops it
```

The `unpublish` step (not always a public method — sometimes it's
inlined as iterating `session._peers` and calling
`removeReceiver`) is what makes a leaving publisher cleanly
disappear from every subscriber.

---

## 2.6. Why this layering matters

You'll be tempted to "just put a method on `Peer`" or "let the
DownTrack reach into `Session`". Resist. The current shape has
exactly the dependencies the data flow needs and nothing more:

* `Peer` knows `Session` (via `provider.getSession(sid)`).
* `Session` knows its `Peer`s.
* `Session` *does not* know about `DownTrack`s — it just calls
  `subscriber.addReceiver()`.
* `Router` knows `Session` only to fire `session.publish()` events.
* `DownTrack` knows the `Receiver` it's forwarding from, but
  *nothing* about other peers in the room.

The result: each chapter from here on can be read in isolation
because each subsystem touches only its immediate parent and child.

---

Next: [Chapter 3 — Publisher and Receiver](./03-PUBLISHER-AND-RECEIVER.md).
