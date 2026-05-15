# 5. Subscriber and DownTrack

The downlink side. A Subscriber is the SFU-side view of one client's
"receive" PeerConnection; a DownTrack is the per-(subscriber, source)
state that rewrites packets so the client only ever sees stable
SSRCs.

---

## 5.1. The Subscriber

File: [`lib/src/subscriber.dart`](../../example/ion_style_sfu/lib/src/subscriber.dart).

```dart
class Subscriber {
  final String peerId;
  final Session session;
  final RTCPeerConnection pc;
  final RtcUdpTransport transport;
  final SsrcAllocator allocator;
  final BandwidthEstimator bwe;
  final TwccStamper twccStamper;
  final LeakyBucketPacer? pacer;
  final LayerSelector layerSelector;

  static Future<Subscriber> create({...});
  Future<RTCSessionDescription> createOffer();
  Future<void> setAnswer(String answerSdp);
  void addReceiver(Receiver receiver);
  void removeReceiver(Receiver receiver);
  void close();
}
```

The Subscriber is the SFU's most stateful object. It owns:

| Field | Purpose | Chapter |
|---|---|---|
| `pc` | RTCPeerConnection (offerer) | here |
| `transport` | UDP socket + SRTP context | parent repo |
| `allocator` | Hands out stable SSRCs to each new DownTrack | here §5.5 |
| `bwe` | Bandwidth estimate from REMB/TWCC/RR feedback | chapter 8 |
| `twccStamper` | Per-PC 16-bit transport seq counter | chapter 8 |
| `pacer` | Optional leaky-bucket smoother | chapter 8 |
| `layerSelector` | Maps `bwe.currentBps` → per-receiver RID | chapter 6, 8 |
| `_downTracks: Map<String, DownTrack>` | trackId → forwarder |
| `_byRewrittenSsrc: Map<int, DownTrack>` | reverse-map for inbound RTCP |

---

## 5.2. `addReceiver` — birthing a DownTrack

When `Session.publish(router, receiver)` fires, every existing
Subscriber gets `addReceiver(receiver)` called.

```dart
void addReceiver(Receiver receiver) {
  if (_downTracks.containsKey(receiver.id)) return;

  // 1. Allocate stable downstream SSRCs for this track.
  final primary = allocator.allocate();
  final rtx     = allocator.allocate();

  // 2. Build the DownTrack.
  final dt = DownTrack(
    receiver: receiver,
    rewrittenPrimarySsrc: primary,
    rewrittenRtxSsrc: rtx,
    twccStamper: twccStamper,
    pacer: pacer,
    transport: transport,
    isKeyframe: _keyframeFnFor(receiver.codecs),
  );

  // 3. Register both directions.
  _downTracks[receiver.id]      = dt;
  _byRewrittenSsrc[primary]     = dt;
  _byRewrittenSsrc[rtx]         = dt;
  receiver.attachDownTrack(dt);

  // 4. Add a transceiver and trigger renegotiation.
  pc.addTransceiver(track: dt.localTrack, kind: receiver.kind,
                    init: RTCRtpTransceiverInit(direction: sendOnly));
  // ... fires onNegotiationNeeded → outer code emits offer/sub
}
```

`removeReceiver` is the inverse — `pc.removeTransceiver()`,
detach from the receiver, drop both maps. This *also* fires
`onNegotiationNeeded`, which the client must answer with a new
SDP that no longer mentions that track's `m=` line.

---

## 5.3. The DownTrack

File: [`lib/src/down_track.dart`](../../example/ion_style_sfu/lib/src/down_track.dart).

```dart
class DownTrack {
  final String id;                  // = receiver.id
  final Receiver receiver;
  final int rewrittenPrimarySsrc;
  final int rewrittenRtxSsrc;
  late final SimulcastRewriter _rewriter;
  late final JitterBuffer _jitter;
  late final NackResponder nack;

  void writeRtp(Uint8List rtp);
  void replay(List<Uint8List> packets);
  void setCurrentLayer(String rid);
  void close();

  // counters → /stats
  int packetsForwarded, bytesForwarded;
  int packetsTwccStamped;
  int packetsDroppedWrongLayer;
}
```

State, in three groups:

* **Identity**: `id` + the rewritten SSRCs.
* **Per-stream rewrite**: `_rewriter` (SimulcastRewriter — chapter 6).
* **Resilience**: `_jitter` ring buffer (last ~512 outbound primary
  packets) + `nack` responder using it.

---

## 5.4. The hot path inside `writeRtp`

```dart
void writeRtp(Uint8List rtp) {
  // 1. Rewrite SSRC + SN + TS for the current layer; bail if gated.
  final result = _rewriter.rewrite(rtp);
  if (result.dropped) {
    packetsDroppedWrongLayer++;
    return;
  }
  final out = result.packet;

  // 2. Stamp transport-wide seq if negotiated.
  twccStamper.stamp(out, twccExtId);
  packetsTwccStamped++;

  // 3. Cache for NACK replay.
  _jitter.record(rtpSeq(out), out);

  // 4. Send (via pacer if present).
  if (pacer != null) {
    pacer!.enqueue(out, false);
  } else {
    transport.sendRtp(out);
  }
  packetsForwarded++;
  bytesForwarded += out.length;
}
```

The rewriter is the only allocation in the steady state — and even
that is into a pre-sized `Uint8List` from the `BytePool` if
configured. TwccStamper writes in-place. JitterBuffer takes a
reference (does not copy).

---

## 5.5. Inbound RTCP — the NACK / PLI loop

The Subscriber's transport calls `_onSubscriberRtcp(rtcp)` for every
RTCP datagram from the client.

```dart
void _onSubscriberRtcp(Uint8List rtcp) {
  for (final fb in parseFeedback(rtcp)) {
    if (fb is NackFeedback) {
      final dt = _byRewrittenSsrc[fb.mediaSsrc];
      if (dt == null) continue;

      final r = dt.nack.lookup(fb.allMissing().toList());
      // Replay what we have in cache as RTX
      dt.replay(r.hits);
      // Escalate the rest to the publisher
      if (r.stillMissing.isNotEmpty) {
        final upstream = buildNackPacket(
          senderSsrc: 0,
          mediaSsrc: dt.receiver.primarySsrcForLayer(dt.currentLayer),
          missingSeqs: r.stillMissing,
        );
        dt.receiver.router.onUpstreamFeedback?.call(upstream);
      }
    } else if (fb is PliFeedback) {
      final dt = _byRewrittenSsrc[fb.mediaSsrc];
      if (dt == null) continue;
      // Coalesce; forward upstream only if it's been > 500ms since last.
      dt.requestKeyframeUpstream();
    } else if (fb is RembFeedback) {
      bwe.onRemb(fb);
      layerSelector.onRemb(fb);
    } else if (fb is TwccFeedback) {
      bwe.onTwcc(fb);
      layerSelector.onTwcc(fb);
    } else if (fb is RrFeedback) {
      bwe.onRr(fb);
      layerSelector.onRr(fb);
    }
  }
}
```

Each branch is simple in isolation. Together they're the SFU's
quality-control loop:

* **NACK** → cache lookup → RTX or escalate
* **PLI** → coalesced upstream PLI → publisher emits keyframe
* **REMB / TWCC / RR** → BWE → layer choice → DownTrack switches

---

## 5.6. RTX — how retransmissions look on the wire

When `dt.replay(packets)` runs, each packet is wrapped per RFC 4588:

* SSRC = `rewrittenRtxSsrc`
* PT   = the RTX PT negotiated in SDP (`apt=primaryPt`)
* SN   = a fresh per-RTX-SSRC sequence number
* The original SN is prepended to the payload as 2 bytes

The browser sees an RTX packet, looks up `apt=` in its SDP, finds
the primary PT, peels the original SN, and reinjects into the jitter
buffer for the primary SSRC.

If `dt._jitter` *doesn't* have the packet, it was either too old
(evicted from the 512-deep ring) or never arrived from the
publisher. Either way it goes into `stillMissing` and gets escalated
via `onUpstreamFeedback`.

---

## 5.7. The DownTrack's idea of "current layer"

A simulcast video DownTrack starts on its **default layer** (usually
the lowest, `q`). The LayerSelector (chapter 6, chapter 8) calls
`dt.setCurrentLayer(rid)` whenever the BWE crosses a threshold or
when the operator forces it.

`setCurrentLayer` doesn't immediately flip — it tells the
SimulcastRewriter "switch in flight". The next packet on the new
layer that *also* passes `isKeyframe(rtp)` commits the switch (see
chapter 6 §6.4). Until then, packets on the old layer continue to
flow; new-layer non-keyframe packets are dropped (counted as
`packetsDroppedWrongLayer`) so the decoder doesn't get garbage
references.

---

## 5.8. What dies when a DownTrack closes

* Detach from `receiver._downTracks`.
* Remove from both `_downTracks[id]` and both `_byRewrittenSsrc[*]`.
* Free both rewritten SSRCs back to the `SsrcAllocator` (which can
  recycle them after a cooldown so a slow remote isn't confused by
  reuse).
* Drain the JitterBuffer (so cached packets aren't held forever).
* Remove the transceiver from the PC (which fires
  `negotiationneeded`).

Subscriber-level state (`bwe`, `pacer`, `twccStamper`) survives —
those are PC-wide.

---

Next: [Chapter 6 — Simulcast and layers](./06-SIMULCAST-AND-LAYERS.md).
