# 3. Publisher and Receiver

The uplink side. A Publisher is the SFU-side view of one client's
"send" PeerConnection; a Receiver is the per-published-track state.
This is where opaque encrypted bytes turn into routed RTP.

---

## 3.1. The Publisher PC

File: [`lib/src/publisher.dart`](../../example/ion_style_sfu/lib/src/publisher.dart).

```dart
class Publisher {
  final String peerId;
  final Session session;
  final RTCPeerConnection pc;
  final RtcUdpTransport transport;
  final Router router;

  static Future<Publisher> create({
    required String peerId,
    required Session session,
  });

  Future<RTCSessionDescription> answerOffer(String offerSdp);
  void close();

  void Function(RTCIceCandidate)? onIceCandidate;
  void Function(RTCIceConnectionState)? onIceConnectionStateChange;
}
```

What the constructor builds:

1. An **`RtcUdpTransport`** bound to a port from
   `Sfu.allocatePort()`. This transport multiplexes STUN, DTLS, and
   SRTP/SRTCP on one UDP socket (see
   [`docs/dart/02-BACKEND-INITIALIZATION.md`](../dart/02-BACKEND-INITIALIZATION.md)).
2. An **`RTCPeerConnection`** wrapping the transport, configured with
   the codec list, ICE servers, and the SFU's DTLS fingerprint.
3. A **`Router`** keyed on this peer (chapter 4).

When `answerOffer()` is called:

1. Parse the publisher's offer SDP.
2. ICE candidates start arriving via `onIceCandidate` and are
   trickled back to the client.
3. ICE → DTLS handshake → SRTP keys derived. The transport flips to
   "ready". (All of this is the parent repo's stack.)
4. `Router.bindToRemoteOffer(pc, offerSdp)` creates Receivers for
   the publisher's `m=` lines (chapter 4 §4.2).
5. Build & return the answer SDP.

From here, **inbound RTP**:

```dart
// inside Publisher
void _onPublisherRtp(Uint8List rtp) {
  _rtpCount++;
  router.routeRtp(rtp);
}

void _onPublisherRtcp(Uint8List rtcp) {
  _rtcpCount++;
  router.routeRtcp(rtcp);
}
```

That's it for Publisher. All the work happens in Router and
Receiver.

---

## 3.2. The Receiver

File: [`lib/src/receiver.dart`](../../example/ion_style_sfu/lib/src/receiver.dart).

One Receiver per **published track**. For a publisher sending one
camera + one mic, that's two Receivers. For simulcast (one camera,
three layers), it's still **one Receiver** with three
`ProducerLayer`s — they share an `mid` and an SDP `m=` line, but
have distinct SSRCs.

```dart
class Receiver {
  final String id;             // "<peerId>:<mid>"
  final MediaKind kind;        // audio | video
  final List<SdpCodec> codecs;
  final ProducerStream stream; // mid, cname, msid, extension ids

  void attachDownTrack(DownTrack dt);
  void detachDownTrack(DownTrack dt);
  void deliverRtp(Uint8List rtp);
  ProducerLayer? resolveLayer(Uint8List rtp);
}
```

State held:

| Field | Purpose |
|---|---|
| `_byPrimarySsrc: Map<int, ProducerLayer>` | O(1) lookup for primary RTP |
| `_byRtxSsrc: Map<int, ProducerLayer>` | O(1) lookup for RTX RTP |
| `_byRid: Map<String, ProducerLayer>` | RID-based simulcast |
| `_downTracks: List<DownTrack>` | Fan-out target |
| `_jitterUnits, _jitterSamples, _lastRtpTs, _lastArrivalUs` | RFC 3550 §A.8 inter-arrival jitter |
| `_highestSeqBySsrc: Map<int, int>` | For loss detection |
| `packetsReceived`, `bytesReceived`, `rtxPacketsReceived`, `packetsLost` | Counters surfaced via stats |

---

## 3.3. The hot path inside `deliverRtp`

```dart
void deliverRtp(Uint8List rtp) {
  // 1. Resolve which layer this packet belongs to.
  final layer = resolveLayer(rtp);
  if (layer == null) return;  // unknown SSRC — drop.

  // 2. Update per-SSRC counters (loss, jitter, bytes, rtx).
  _updateStats(rtp, layer);

  // 3. If this packet has an audio-level extension, feed the observer.
  if (kind == MediaKind.audio && stream.audioLevelExtId != null) {
    final lvl = decodeAudioLevel(rtp, stream.audioLevelExtId!);
    if (lvl != null) session.audioObserver.deliverAudioLevel(id, lvl.level, lvl.voice);
  }

  // 4. Fan out to every subscribed DownTrack.
  for (final dt in _downTracks) {
    dt.writeRtp(rtp);
  }
}
```

Three things to notice:

* **No copy**: `rtp` is passed by reference to every DownTrack. The
  rewriter copies-on-write into a fresh buffer when it needs to
  modify, but un-rewritten bytes (e.g. payload) are shared.
* **No allocation in the steady state**: counter updates use raw
  byte access via [`rtp_header.dart`](../../example/ion_style_sfu/lib/src/rtp_header.dart);
  no `RtpPacket` object is constructed.
* **The RID extension** is parsed once in `resolveLayer()` *only on
  the first packet of an unknown SSRC*. After that, `_byPrimarySsrc`
  short-circuits.

---

## 3.4. RID-based SSRC learning

In modern Chrome simulcast, the publisher's offer SDP only
advertises that "MID 0 has these RIDs (q, h, f) on these payload
types". It does **not** tell you which SSRCs they'll arrive with.
Those are announced **in the first RTP packet** of each layer via
the RFC 8852 RID header extension.

So `Receiver.resolveLayer(rtp)`:

1. If `_byPrimarySsrc` has the SSRC → return the layer. Done.
2. Else parse the RID extension from RTP header extensions:
    * `decodeRidString(rtp, stream.ridExtId)` → `"q"` / `"h"` / `"f"`.
3. Look up `_byRid[rid]` → that's the layer descriptor.
4. **Bind it**: write `_byPrimarySsrc[ssrc] = layer`. From now on,
   step 1 succeeds.

The same pattern handles RTX SSRCs via `repairedRidExtId` (RFC 8852
again — RTX packets carry the *primary's* RID via the "repaired-rid"
extension so the SFU can pair them).

---

## 3.5. The `ProducerStream` and `ProducerLayer` shapes

File: [`producer_stream.dart`](../../example/ion_style_sfu/lib/src/producer_stream.dart),
[`producer_layer.dart`](../../example/ion_style_sfu/lib/src/producer_layer.dart).

```dart
class ProducerStream {
  String kind;       // "audio" or "video"
  String mid;        // MID from SDP
  String cname;      // SDES CNAME for SR generation
  String msidStream; // MediaStream id
  String msidTrack;  // MediaStreamTrack id
  List<ProducerLayer> layers;
  int? ridExtId;
  int? repairedRidExtId;
  int? audioLevelExtId;
  int? twccExtId;
}

class ProducerLayer {
  String rid;          // 'q' | 'h' | 'f' | ''
  int primarySsrc;
  int? rtxSsrc;
}
```

Most of these are ID 0 / null for non-video, non-simulcast streams.
A typical webcam without simulcast will have **one** `ProducerLayer`
with `rid: ''` and `rtxSsrc: <something>`. Audio always has one
layer with `rid: ''` and no RTX.

---

## 3.6. Per-source counters and what they're used for

| Counter | Used by |
|---|---|
| `packetsReceived` / `bytesReceived` | `/stats`, `/metrics` |
| `packetsLost` | RR generation (when the SFU emits one upstream); BWE input via `RrFeedback` if echoed back from a subscriber |
| `_jitterUnits` (smoothed in RTP-ts units) | Same as above; `/stats` exposes `publisherJitterMs` |
| Per-SSRC highest seq (16-bit, with rollover detection) | `SeqGapDetector` in Router (chapter 4 §4.4) → upstream NACK |

The Receiver intentionally does **not** generate RR or NACK. Those
are the Router's job because they need cross-SSRC coordination (one
RR/SR per source group; one NACK per missing window across the
whole layer).

---

## 3.7. What happens on a publisher leave

`Publisher.close()`:

1. `transport.close()` — flushes pending packets, closes UDP socket.
2. For each `Receiver` owned by `router`:
    * `session.unpublish(router, receiver)` — removes the receiver
      from every other peer's Subscriber.
    * `receiver.dispose()` — drops counters, NACK state.
3. Router itself dropped.

If this was the only peer in the room, the Session also closes
(chapter 2 §2.3).

---

Next: [Chapter 4 — Router and fan-out](./04-ROUTER-AND-FANOUT.md).
