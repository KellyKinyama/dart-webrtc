# 4. Router and fan-out

The Router is the per-publisher hub. It owns the publisher's
Receivers, demultiplexes inbound RTP/RTCP by SSRC, and is the *only*
object on the hot path that knows about both the publisher and the
session as a whole.

---

## 4.1. The class

File: [`lib/src/router.dart`](../../example/ion_style_sfu/lib/src/router.dart).

```dart
class Router {
  final String peerId;
  final Session session;

  void bindToRemoteOffer(RTCPeerConnection pc, String offerSdp);
  void routeRtp(Uint8List rtp);
  void routeRtcp(Uint8List rtcp);
  Receiver? receiverForSsrc(int ssrc);

  void Function(Uint8List pkt)? onUpstreamFeedback;
}
```

State:

| Field | Purpose |
|---|---|
| `_byPrimarySsrc: Map<int, Receiver>` | Hot-path RTP demux |
| `_byRtxSsrc: Map<int, Receiver>` | Hot-path RTX demux |
| `_byId: Map<String, Receiver>` | Cold-path lookups by `peerId:mid` |
| `_gap: Map<int, SeqGapDetector>` | Per primary SSRC, for upstream NACK |

---

## 4.2. `bindToRemoteOffer` — turning SDP into Receivers

This is the cold-path "track inventory" step. Called once when the
publisher's offer is received.

Steps:

1. Parse the offer SDP (via the parent repo's `lib/signal/sdp_v2.dart`).
2. For each `m=` line:
    * Read `mid`, `kind` (audio/video), and the codec list.
    * Read RTP header extensions (`urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id`,
      `urn:ietf:params:rtp-hdrext:ssrc-audio-level`,
      `http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01`).
    * Read `a=ssrc:` lines (CNAME, MSID).
    * Read `a=ssrc-group:FID` (primary↔RTX pairing) and
      `a=simulcast:` (RIDs).
3. Build a `ProducerStream` with the parsed extension IDs and a
   `ProducerLayer` per RID (or one layer for the bare-SSRC case).
4. Construct one `Receiver` per `m=` line.
5. Index it: `_byId[receiver.id] = receiver`; for every known SSRC
   in any layer, `_byPrimarySsrc[s] = receiver` and same for RTX.
6. For every layer where the SSRC isn't yet known (RID-only
   simulcast), wire `receiver.onSsrcLearned = (ssrc) =>
   _byPrimarySsrc[ssrc] = receiver` so the lazy-binding from
   chapter 3 §3.4 keeps the Router's index up to date.
7. Call `session.publish(this, receiver)` — fans out to every other
   peer's Subscriber.

After this returns, the Publisher is ready to receive RTP.

---

## 4.3. `routeRtp` — the hottest function in the SFU

```dart
void routeRtp(Uint8List rtp) {
  final ssrc = rtpSsrc(rtp);

  var receiver = _byPrimarySsrc[ssrc];
  if (receiver != null) {
    _checkGap(ssrc, rtp, receiver);  // schedules NACK if seq gap
    receiver.deliverRtp(rtp);
    return;
  }

  receiver = _byRtxSsrc[ssrc];
  if (receiver != null) {
    receiver.deliverRtp(rtp);
    return;
  }

  // SSRC not yet bound — try RID-based learning by walking _byId
  // (a small list, typically 1–2 entries).
  for (final r in _byId.values) {
    if (r.tryLearnSsrcFromRid(rtp)) {
      _byPrimarySsrc[ssrc] = r;
      r.deliverRtp(rtp);
      return;
    }
  }
  // truly unknown — drop silently.
}
```

Two map lookups, one delivery. That's the whole hot path on the
Router. Everything else in this file is cold.

---

## 4.4. Sequence-gap detection → upstream NACK

`SeqGapDetector` (one per primary SSRC) tracks the sliding 16-bit
sequence space and emits "I'm missing seqs X–Y" callbacks. The
Router collects those and emits a NACK back to the publisher:

```dart
void _checkGap(int ssrc, Uint8List rtp, Receiver receiver) {
  final detector = _gap.putIfAbsent(ssrc, () => SeqGapDetector(ssrc));
  detector.observe(rtpSeq(rtp), (missing) {
    final nack = buildNackPacket(senderSsrc: 0, mediaSsrc: ssrc,
                                  missingSeqs: missing);
    onUpstreamFeedback?.call(nack);
  });
}
```

Important: this is for **publisher-side loss** (publisher → SFU UDP
loss), not subscriber-side loss. Subscriber NACKs come from the
*Subscriber* via `_onSubscriberRtcp` and are answered from the
DownTrack's jitter buffer (chapter 5).

`onUpstreamFeedback` is set by `Publisher` to `pc.sendRtcp(...)`
which encrypts via SRTCP and sends back over the UDP socket.

---

## 4.5. `routeRtcp` — inbound RTCP from the publisher

The publisher periodically sends:

* **SR** (sender reports — once every few seconds per SSRC).
* **SDES** (CNAME).
* Possibly **RR** if the publisher's PC also receives anything (it
  doesn't in pure-publish flows but some clients still emit empty RR).
* **TWCC feedback** about packets the SFU sent upstream — but in
  this SFU we only stamp TWCC on the *downstream* side, so this is
  rarely meaningful and is mostly logged.

`routeRtcp` parses the compound packet via `parseFeedback()` from
[`rtcp.dart`](../../example/ion_style_sfu/lib/src/rtcp.dart) and
walks the sealed hierarchy (`SrFeedback`, `SdesFeedback`,
`RrFeedback`, ...). SRs are forwarded to subscribers via the
rewriting pipeline (chapter 7 §7.4); SDES is largely ignored
(forwarded for CNAME consistency); RR is fed to the upstream BWE if
present.

---

## 4.6. Inverse SSRC mapping for outbound feedback

When a subscriber NACKs SSRC `0xRWRWRWRW` (the rewritten one), the
Router needs to translate that back to the publisher's original SSRC
to actually escalate it upstream.

That mapping isn't held in the Router itself — it lives in the
`DownTrack` as `(receiver, rewrittenPrimarySsrc, rewrittenRtxSsrc)`.
The Subscriber's RTCP handler (chapter 5 §5.4) does the lookup
**by rewritten SSRC**, finds the DownTrack, and calls
`router._receiverFromDownTrack(dt)` to get the publisher-side
Receiver. That's how the loop closes:

```
sub NACK (rewritten SSRC) → Subscriber._onSubscriberRtcp
                            → DownTrack lookup by rewritten SSRC
                            → DownTrack.receiver (publisher-side)
                            → Router.onUpstreamFeedback(...)
                            → Publisher PC sends NACK to publishing client
```

---

## 4.7. Why the Router doesn't own DownTracks

A reasonable question: why isn't the fan-out list `_downTracks`
held on the Router instead of on each Receiver?

Two reasons:

1. **Granularity**: a Subscriber wants to subscribe to *some* of a
   publisher's tracks (say, just the camera, not the screen-share),
   so the per-receiver list is the natural unit.
2. **Layer-switch independence**: each (subscriber, receiver) pair
   needs its own SimulcastRewriter state. Storing that next to the
   fan-out target avoids a second indirection in the hot path.

The trade-off is that a single SSRC lookup hits the Router's map,
*then* the Receiver's `_downTracks` list. In Dart, both are
near-zero cost.

---

Next: [Chapter 5 — Subscriber and DownTrack](./05-SUBSCRIBER-AND-DOWNTRACK.md).
