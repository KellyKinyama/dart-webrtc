# **Ion-Style SFU — Nuts and Bolts (Dart edition)**

A full architectural walkthrough of [`example/ion_style_sfu/`](../../example/ion_style_sfu/),
the pure-Dart Selective Forwarding Unit shipped with this repo.
Companion to the protocol-stack tutorial in [`../dart/`](../dart/) and
the [RTCP/SRTCP deep-dive](../dart/RTCP-AND-SRTCP.md).

> An SFU does one job: take RTP from one peer and *selectively forward*
> it to N other peers. Everything else in this codebase — sessions,
> simulcast, jitter buffers, TWCC, cascade — exists to do that one
> job at scale, with quality, and without going broke on bandwidth.

---

## Chapters

| # | File | What it covers |
|---|---|---|
| 0 | [00-OVERVIEW.md](./00-OVERVIEW.md) | Big-picture data flow, glossary, mental model |
| 1 | [01-PROCESS-AND-SIGNALLING.md](./01-PROCESS-AND-SIGNALLING.md) | `bin/sfu_server.dart`, WebSocket frames, sharding boot |
| 2 | [02-SFU-SESSION-PEER.md](./02-SFU-SESSION-PEER.md) | Three-tier registry, lifecycle, ownership |
| 3 | [03-PUBLISHER-AND-RECEIVER.md](./03-PUBLISHER-AND-RECEIVER.md) | Uplink PC, SSRC learning, per-source state |
| 4 | [04-ROUTER-AND-FANOUT.md](./04-ROUTER-AND-FANOUT.md) | The hot path: SSRC → Receiver → DownTracks |
| 5 | [05-SUBSCRIBER-AND-DOWNTRACK.md](./05-SUBSCRIBER-AND-DOWNTRACK.md) | Downlink PC, per-subscriber rewrite, RTX |
| 6 | [06-SIMULCAST-AND-LAYERS.md](./06-SIMULCAST-AND-LAYERS.md) | RID, layer offsets, keyframe gate, switch protocol |
| 7 | [07-RTCP-AND-FEEDBACK.md](./07-RTCP-AND-FEEDBACK.md) | NACK / PLI / FIR / REMB / TWCC routing & rewrite |
| 8 | [08-BWE-TWCC-PACER.md](./08-BWE-TWCC-PACER.md) | Stamping, hybrid BWE, leaky-bucket pacer, layer choice |
| 9 | [09-CLUSTER-AND-CASCADE.md](./09-CLUSTER-AND-CASCADE.md) | Sharded isolates, cluster coordinator, cross-SFU relay |
| 10 | [10-OBSERVABILITY-AND-TESTING.md](./10-OBSERVABILITY-AND-TESTING.md) | Stats, Prometheus, audio observer, load test |

## How to read it

Read in order if this is your first SFU. Each chapter ends with
"connect to next stage" so the reader builds the data-flow picture
incrementally.

If you already know SFUs and want to dive into a specific subsystem,
jump straight to the chapter — every section links the **exact files
and class/method names** so you can read source side-by-side.

## Top-level map

```
                    bin/sfu_server.dart       ← chapter 1
                          │
                          ▼
                   ShardedSfu (registry)      ← chapter 9
                          │ spawn isolate per session
                          ▼
                    SessionShard
                       │
                       ▼
                       Sfu                    ← chapter 2
                       │
                       ▼
                    Session (one per room)
                  ┌────┼────┐
                  ▼         ▼
               Peer        Peer               ← chapter 2
              ┌──┴──┐    ┌──┴──┐
              ▼     ▼    ▼     ▼
         Publisher Sub  Pub  Subscriber       ← chapters 3, 5
            │              ▲
            ▼              │
          Router ──────► DownTrack            ← chapters 4, 5
           │ (per pub)    │ (per (sub, track))
           ▼              ▼
         Receiver  ──► SimulcastRewriter      ← chapters 3, 6
                        │
                        ▼
                   TwccStamper → Pacer        ← chapter 8
                        │
                        ▼
                  RtcUdpTransport (SRTP)
                        │
                        ▼
                   wire (UDP)
```

## Prerequisites

* You've read the [Dart edition tutorial](../dart/) — at least
  chapters 0–2 (infrastructure, dev mode, backend init) and 6
  (SRTP).
* Comfortable with WebRTC vocabulary: PeerConnection, ICE, DTLS,
  SRTP, RTP, RTCP, simulcast, RID, NACK, PLI.
* Comfortable with Dart isolates — the cluster chapter assumes it.

## Conventions

* File links go to the actual source. Click them.
* "Hot path" = code that runs per RTP packet (thousands of times per
  second). "Cold path" = once per join/leave/layer-switch.
* "Upstream" = toward the publishing client. "Downstream" = toward
  the subscribing client. The SFU is the middleman.
