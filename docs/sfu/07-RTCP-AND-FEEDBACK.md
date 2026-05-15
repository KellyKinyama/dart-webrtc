# 7. RTCP and feedback routing

This chapter is the SFU-specific complement to the deeper
[RTCP and SRTCP deep-dive](../dart/RTCP-AND-SRTCP.md). The deep-dive
explains what each packet *is*; this chapter explains how this SFU
*routes and rewrites* them.

---

## 7.1. The four flows

```
                    ┌─────────────────┐
                    │     Publisher   │
                    │  (uplink PC)    │
                    └────────┬────────┘
                             │
   ① publisher → SFU         │      ② SFU → publisher
      (SR, SDES, RR)         │         (NACK, PLI, RR)
                             │
                             ▼
                     ┌────────────┐
                     │   Router   │
                     └──────┬─────┘
                            │
                            ▼
                     ┌────────────┐
                     │  Receiver  │
                     │  (per src) │
                     └──────┬─────┘
                            │ deliverRtp / SR forwarding
                            ▼
                  ┌─────────────────┐
                  │   DownTrack(s)  │
                  └────────┬────────┘
                           │
                           ▼
                    ┌─────────────────┐
                    │   Subscriber    │
                    │  (downlink PC)  │
                    └────────┬────────┘
                             │
   ③ SFU → subscriber        │      ④ subscriber → SFU
      (rewritten SR, SDES,   │         (NACK, PLI, RR, REMB, TWCC)
       BYE)                  │
                             ▼
                          (client)
```

Each numbered arrow is a parser path in this codebase:

| # | Direction | Entry | Format(s) |
|---|---|---|---|
| ① | pub → SFU | `Publisher._onPublisherRtcp` → `Router.routeRtcp` | SR, SDES, optional RR |
| ② | SFU → pub | `Router.onUpstreamFeedback` (publisher's PC sendRtcp) | NACK (loss), PLI (layer switch / sub PLI), RR (echoing sub stats) |
| ③ | SFU → sub | DownTrack-driven; rewriting SRs forwarded from publisher | rewritten SR, SDES, optional RR |
| ④ | sub → SFU | `Subscriber._onSubscriberRtcp` | NACK, PLI, RR, REMB, TWCC |

---

## 7.2. The parser — `parseFeedback()`

File: [`lib/src/rtcp.dart`](../../example/ion_style_sfu/lib/src/rtcp.dart).

```dart
sealed class RtcpFeedback {
  int get senderSsrc;
  int get mediaSsrc;
}

class NackFeedback   extends RtcpFeedback { List<NackFci> fcis; Iterable<int> allMissing(); }
class PliFeedback    extends RtcpFeedback {}
class FirFeedback    extends RtcpFeedback { List<FirEntry> entries; }
class RembFeedback   extends RtcpFeedback { int bps; List<int> ssrcs; }
class RrFeedback     extends RtcpFeedback { List<RrReportBlock> blocks; }
class TwccFeedback   extends RtcpFeedback { /* run-length / status-vector chunks */ }
class SrFeedback     extends RtcpFeedback { Int64 ntpTimestamp; int rtpTimestamp; int packets; int bytes; }
class SdesFeedback   extends RtcpFeedback { /* CNAME mapping */ }

Iterable<RtcpFeedback> parseFeedback(Uint8List bytes);
```

`parseFeedback` is a zero-allocation walker: each yielded object
holds field offsets into the original `Uint8List` and reads them on
demand. That's why even high-rate TWCC packets (one per ~30 ms with
100s of seqs) don't allocate per-packet.

---

## 7.3. The four flows in detail

### ① Publisher → SFU RTCP

Publisher PCs receive SR + SDES per source. The Router's handler
walks `parseFeedback(rtcp)`:

* **`SrFeedback`** — extract `(ssrc, ntpTimestamp, rtpTimestamp,
  packets, bytes)`. If any DownTrack subscribes to this source's
  receiver, the Router rewrites and forwards the SR downstream
  (see ③). The receiver also caches `(ntp, rtp_ts)` so it can be
  used by RR generation later.
* **`SdesFeedback`** — record the CNAME (used in our outbound
  SDES, both upstream and downstream).
* **`RrFeedback`** — usually empty in publish-only flows. If
  present, fed to the publisher-side BWE (rare path).

### ② SFU → Publisher RTCP

Triggered by the data-plane:

* **NACK upstream**: Router's `SeqGapDetector` (publisher-side
  loss) or DownTrack's escalation (subscriber-reported loss the
  cache couldn't satisfy) — see chapter 4 §4.4 and chapter 5 §5.5.
* **PLI upstream**: triggered by either (a) a subscriber's PLI
  arriving, or (b) `setCurrentLayer` flipping the simulcast layer
  (chapter 6 §6.5). Coalesced — at most one PLI per ~500 ms per
  source.
* **RR upstream**: very rare. Most clients don't send the SFU
  enough media downstream for RR to be meaningful, and the SFU
  isn't really a "receiver" anyway.

All emitted via `Router.onUpstreamFeedback(pkt)`, which the
Publisher PC's `sendRtcp()` SRTCP-encrypts and sends.

### ③ SFU → Subscriber RTCP

The subscriber needs to see SR for each track it's receiving so its
A/V sync works. But the publisher's SR has the publisher's SSRC,
and the subscriber's stream uses the *rewritten* SSRC. So:

```dart
// example/ion_style_sfu/lib/src/rtcp_rewrite.dart
Uint8List rewriteRtcpForSubscriber(
  Uint8List rtcp,
  RtcpSsrcMap map, {
  int? Function(int publisherSsrc)? tsOffsetFor,
});
```

Per packet type:

| PT  | Rewrite |
|-----|---|
| 200 SR | sender SSRC → rewritten primary; RTP ts += `tsOffsetFor(publisherSsrc)`; per-block source SSRC translated |
| 201 RR | per-block source SSRC translated (reporter SSRC left alone) |
| 202 SDES | passthrough |
| 203 BYE | passthrough |
| 205/206 feedback | passthrough; the SFU usually generates these from scratch instead |

The `tsOffsetFor` callback is wired to the DownTrack's
SimulcastRewriter so the SR's RTP timestamp is shifted by the
*same* offset that the data-plane SimulcastRewriter is currently
applying to RTP packets. Without this, A/V sync drifts by exactly
the layer offset whenever a switch has happened.

### ④ Subscriber → SFU RTCP

The interesting flow. `Subscriber._onSubscriberRtcp` handles every
type — see chapter 5 §5.5 for the full code. Summary table:

| Type | Effect |
|---|---|
| `NackFeedback` | lookup in `DownTrack.nack` (cache); RTX hits, escalate misses upstream |
| `PliFeedback` | coalesced upstream PLI to publisher |
| `FirFeedback` | same as PLI in this SFU |
| `RembFeedback` | `bwe.onRemb(fb)` + `layerSelector.onRemb(fb)` |
| `TwccFeedback` | `bwe.onTwcc(fb)` + `layerSelector.onTwcc(fb)` |
| `RrFeedback` | `bwe.onRr(fb)` (loss fraction informs the estimator) |

---

## 7.4. SR rewrite, walk-through

A publisher's SR for SSRC `0xPPPPPPPP` reaches a subscriber that
should see SSRC `0xRRRRRRRR`. The DownTrack's `SimulcastRewriter`
has been applying `tsOffset = +12345` for the current layer.

Before:
```
PT=200 length=6
sender SSRC = 0xPPPPPPPP
NTP        = 0xE60E14F1_80000000
RTP ts     = 0x000F4240
packets    = 12345
bytes      = 9876543
```

After `rewriteRtcpForSubscriber()`:
```
PT=200 length=6
sender SSRC = 0xRRRRRRRR        ← translated
NTP        = 0xE60E14F1_80000000 (unchanged)
RTP ts     = 0x000F4240 + 0x3039 = 0x000F7279   ← shifted
packets    = 12345               (unchanged — subscriber sees a count
                                  for the rewritten SSRC, which is
                                  the same forwarded count)
bytes      = 9876543             (likewise)
```

The subscriber computes "wallclock now − NTP" against the (still
correct) NTP, and "expected RTP ts now" against the shifted RTP
ts — and gets a value that lines up with the (already-shifted) RTP
packets it's been receiving. A/V sync holds across layer switches.

---

## 7.5. Why the SFU re-emits feedback rather than forwarding

You may wonder: why doesn't the SFU just forward the subscriber's
NACK upstream verbatim?

Because:

1. **SSRC mismatch**: the subscriber's NACK names the *rewritten*
   SSRC, which the publisher has never heard of.
2. **Cache-first**: most NACKs can be answered from the SFU's local
   cache (the DownTrack's JitterBuffer), saving an upstream round-trip.
3. **Coalescing**: 5 subscribers each NACK'ing seq 1234 should
   produce **one** upstream NACK to the publisher, not 5.
4. **Layer awareness**: the publisher might be sending three
   simulcast layers, but the subscriber is on layer `h`. The NACK
   should target the publisher's `h`-SSRC, which is computable from
   the DownTrack's current layer + the receiver's layer table.

So the SFU *interprets* every inbound feedback and re-emits the
appropriate upstream version.

---

## 7.6. SRTCP wraps everything

Every RTCP packet listed above is encrypted in SRTCP before going
on the wire. The SFU's SRTP context handles this transparently —
see [RTCP-AND-SRTCP.md §8](../dart/RTCP-AND-SRTCP.md#8-srtcp-encryption--replay-protection)
for the gory details (per-SSRC 31-bit index, sliding-window replay).

What the SFU code in this chapter sees is always the **plaintext**
RTCP. The encrypt/decrypt boundary is at `RtcUdpTransport`.

---

Next: [Chapter 8 — BWE, TWCC, pacer](./08-BWE-TWCC-PACER.md).
