# 0. Overview — the data-flow picture

Before diving into individual files, install the mental model. The
rest of the tutorial is just adding precision to the picture you'll
build here.

---

## 0.1. What an SFU is, in 30 seconds

A **Selective Forwarding Unit** is a WebRTC media server that:

1. Holds one `RTCPeerConnection` per participant (per direction —
   see §0.4).
2. Receives RTP packets from publishers.
3. Forwards (with minimal modification) those RTP packets to every
   other participant who wants them.

It does **not** decode media (that would cost CPU). It does **not**
re-encode (ditto). It rewrites packet headers — SSRC, sequence
number, timestamp — and that's it for the media path. Everything else
is feedback (NACK / PLI / TWCC) and bookkeeping.

Compare to:

* **MCU**: decodes, mixes, re-encodes. CPU-heavy, single output stream.
* **TURN relay**: blind L3 packet forwarder, no SDP/SRTP awareness.
* **Mesh**: no server, every peer connects to every other peer. Falls
  apart at >4 participants.

SFUs win because they scale (~100s of viewers per publisher) without
needing to decode anything.

---

## 0.2. The two-PC model

For each participant, this SFU holds **two** PeerConnections:

```
                        ┌─────────────┐
                client ─┤ Publisher PC├─► server  (uplink: client sends)
                        └─────────────┘
                        ┌─────────────┐
                client ◄┤Subscriber PC├─ server  (downlink: client receives)
                        └─────────────┘
```

Why two? Because in WebRTC, a transceiver's direction is either
`sendrecv` or `sendonly`/`recvonly`, but renegotiation across many
participants is much simpler when each direction has its own PC. Ion
SFU pioneered this pattern; this Dart port follows it.

Files:
* [`lib/src/publisher.dart`](../../example/ion_style_sfu/lib/src/publisher.dart)
* [`lib/src/subscriber.dart`](../../example/ion_style_sfu/lib/src/subscriber.dart)

---

## 0.3. The hot path — one RTP packet's journey

Follow a single RTP packet from publisher Alice to subscriber Bob:

```
1. Alice's browser encodes a video frame, packetises into RTP, encrypts
   into SRTP, sends over UDP.
        ↓
2. The SFU's RtcUdpTransport for Alice's Publisher PC receives the
   datagram, demuxes (STUN vs DTLS vs SRTP), decrypts SRTP, hands raw
   RTP to Publisher.
        ↓
3. Publisher → Router.routeRtp(rtp).
        ↓
4. Router looks up Receiver by SSRC: O(1) Map lookup.
        ↓
5. Receiver.deliverRtp(rtp): updates jitter/loss counters, resolves
   simulcast layer (by SSRC or RID extension), then iterates attached
   DownTracks.
        ↓
6. For each DownTrack (one per subscriber):
     a. SimulcastRewriter.rewrite(rtp): patch SSRC, SN, TS.
     b. TwccStamper.stamp(rtp): write 16-bit transport seq.
     c. (optional) JitterBuffer.record(rtp): cache for NACK.
     d. (optional) Pacer.enqueue(rtp).
     e. SRTP encrypt, send over UDP via Subscriber's RtcUdpTransport.
        ↓
7. Bob's browser receives, decrypts, depacketises, decodes, plays.
```

Steps 4–6 happen **per packet, per subscriber, in the worker
isolate**. They have to be fast. The Dart SFU goes to some lengths
to avoid per-packet allocations: byte helpers in
[`rtp_header.dart`](../../example/ion_style_sfu/lib/src/rtp_header.dart),
the `BytePool` for `Uint8List` reuse, sealed `RtcpFeedback` parsed
off raw bytes.

---

## 0.4. The cold path — control-plane events

Less frequent, but more complex:

| Event | Trigger | What happens |
|---|---|---|
| Peer joins | WebSocket `join` frame | Session created if missing; Publisher + Subscriber PCs constructed |
| Track published | Publisher's offer SDP carries `a=ssrc` lines | Router.bindToRemoteOffer creates Receivers; Session.publish fans out to all subscribers' Subscriber PCs |
| Subscriber needs renegotiation | Receiver added/removed | Subscriber emits `negotiationneeded` → JS client answers with offer/answer |
| Layer switch | BWE crosses threshold | LayerSelector → DownTrack.setCurrentLayer → SimulcastRewriter records new offsets, gates until keyframe |
| Peer leaves | WebSocket disconnect or `leave` | Session.removePeer → tear down Publisher/Subscriber → if last peer, shard exits |

---

## 0.5. State ownership map

If you remember nothing else from this chapter, remember which
object owns which state:

| State | Owner | File |
|---|---|---|
| Session map (id → Session) | `Sfu` | [sfu.dart](../../example/ion_style_sfu/lib/src/sfu.dart) |
| Peer map (id → Peer) | `Session` | [session.dart](../../example/ion_style_sfu/lib/src/session.dart) |
| Publisher / Subscriber PCs | `Peer` | [peer.dart](../../example/ion_style_sfu/lib/src/peer.dart) |
| Receivers (per published track) | `Router` | [router.dart](../../example/ion_style_sfu/lib/src/router.dart) |
| Per-SSRC counters, jitter, layer index | `Receiver` | [receiver.dart](../../example/ion_style_sfu/lib/src/receiver.dart) |
| Per-(sub, track) rewrite state | `DownTrack` | [down_track.dart](../../example/ion_style_sfu/lib/src/down_track.dart) |
| Per-(sub, track) jitter buffer + NACK cache | `DownTrack` (delegates to `buffer/`) | [buffer/](../../example/ion_style_sfu/lib/src/buffer/) |
| Per-subscriber bandwidth estimate | `Subscriber.bwe` | [bwe.dart](../../example/ion_style_sfu/lib/src/bwe.dart) |
| Per-subscriber TWCC stamper | `Subscriber.twccStamper` | [twcc/twcc_stamper.dart](../../example/ion_style_sfu/lib/src/twcc/twcc_stamper.dart) |
| Per-subscriber pacer | `Subscriber.pacer` | [pacer/leaky_bucket.dart](../../example/ion_style_sfu/lib/src/pacer/leaky_bucket.dart) |
| SRTP context (in/out keys, replay window) | `RtcUdpTransport` | `lib/webrtc/rtc_udp_transport.dart` (parent repo) |
| Per-shard active-speaker EMA | `AudioObserver` (on `Session`) | [audio_observer.dart](../../example/ion_style_sfu/lib/src/audio_observer.dart) |
| Cluster bridge routes | `ClusterCoordinator` (main isolate) | [cluster/cluster_coordinator.dart](../../example/ion_style_sfu/lib/src/cluster/cluster_coordinator.dart) |

---

## 0.6. Glossary

* **SSRC** — Synchronization Source. 32-bit ID identifying one RTP
  source. The SFU rewrites these.
* **RID** — Restriction Identifier (RFC 8851). String label like
  `q`/`h`/`f` (low/medium/high) identifying a simulcast layer. Sent
  in an RTP header extension.
* **MID** — Media stream Identifier (RFC 8843). String identifying a
  transceiver across SDP renegotiations.
* **PT** — Payload Type. 7-bit ID in the RTP header selecting the
  codec (e.g. 96 = VP8 by SDP convention).
* **NACK** — Negative ACK. Receiver tells sender "I'm missing seq X".
* **PLI** — Picture Loss Indication. Receiver tells sender "I lost
  video, please send a keyframe".
* **FIR** — Full Intra Request. Older big-hammer version of PLI.
* **REMB** — Receiver Estimated Maximum Bitrate.
* **TWCC** — Transport-Wide Congestion Control. Per-packet arrival
  feedback for delay-based BWE.
* **RTX** — Retransmission. Replays of lost packets carry a separate
  payload type and SSRC (RFC 4588).
* **Simulcast** — Publisher encodes the same video at multiple
  qualities and sends them all; the SFU forwards only one per
  subscriber.
* **SVC** — Scalable Video Coding. Same idea, but layers are
  embedded in the same stream (VP9, AV1). This SFU prefers simulcast.
* **Cascade** — SFU-to-SFU relay. Used to scale across regions.

---

## 0.7. What this SFU explicitly is and isn't

**Is:**

* A reference Dart implementation that exercises the parent repo's
  WebRTC stack end-to-end.
* Single-isolate per session by default; opt-in cluster mode with
  cross-SFU relay over UDP.
* Production-shaped — has stats, sharding, BWE, simulcast, NACK
  cache, TWCC, audio observer, leaky-bucket pacer.

**Is not:**

* A drop-in replacement for ion-sfu in a Go production deployment.
* An MCU. There's no transcoding, mixing, or recording (yet).
* A media gateway. There's no RTSP, HLS, RTMP, or WebTransport
  bridging in this package (other examples cover those).
* SVC-aware in the temporal/spatial-layer-pruning sense. SVC streams
  are forwarded but not decomposed.

---

Next: [Chapter 1 — Process and signalling](./01-PROCESS-AND-SIGNALLING.md).
