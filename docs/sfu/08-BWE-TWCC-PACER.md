# 8. BWE, TWCC, pacer

Bandwidth estimation is the most opaque part of any SFU. This
chapter walks the actual signal flow — what gets stamped, what gets
fed back, how the estimate is computed, and how it ends up choosing
a simulcast layer or rate-limiting a pacer.

---

## 8.1. Why an SFU needs BWE at all

Each subscriber sits behind a different network — Wi-Fi, LTE, fibre,
hotel uplink. The publisher always sends 3 simulcast layers; the
SFU's job is to deliver the *highest layer the subscriber's network
can carry without congestion*.

That requires:

1. A **per-subscriber bandwidth estimate** (in bits/s).
2. A **layer-selection policy** that maps that estimate to a RID.
3. (Optional) A **pacer** that smooths bursts so the estimate
   actually reflects the network rather than the codec's
   batch-output bursts.

All three live on `Subscriber` (chapter 5 §5.1), one instance per
downlink PC.

---

## 8.2. TWCC — what gets stamped

File: [`lib/src/twcc/twcc_stamper.dart`](../../example/ion_style_sfu/lib/src/twcc/twcc_stamper.dart).

```dart
class TwccStamper {
  final int historyCapacity;   // default 1024
  int _next = 0;               // rolling 16-bit
  Map<int, _StampedSample> _history;  // seq → (sendTimeUs, sizeBytes)

  int? stamp(Uint8List rtp, int twccExtId, {int? sendTimeMicros});
  int? sendTimeMicrosFor(int seq);
}
```

Every outbound primary RTP packet from a DownTrack flows through
`twccStamper.stamp(rtp, twccExtId)`:

1. Look up the one-byte RFC 5285 RTP header extension whose ID is
   `twccExtId` (negotiated in SDP, typically id=3).
2. Write the next 16-bit `_next` value into it (big-endian).
3. Bump `_next` (mod 2¹⁶), evict the oldest history entry if at
   capacity.
4. Return the seq written.

The stamper is **per-Subscriber, not per-DownTrack**. Why: TWCC
seqs are *transport-wide* — they cover *all* RTP traffic on the PC,
so the receiver can build one timeline regardless of which media
SSRC each packet belonged to.

---

## 8.3. TWCC — what comes back

The remote peer collects (transport-seq, arrival-time) for every
packet it receives, and periodically emits a **TWCC feedback packet**
(RTCP, PT=205, FMT=15). Layout in
[`lib/src/rtcp.dart`](../../example/ion_style_sfu/lib/src/rtcp.dart) and
[deep-dive §7.3](../dart/RTCP-AND-SRTCP.md#73-the-twcc-packet-body-briefly).

The Subscriber's RTCP handler routes each `TwccFeedback` into:

```dart
bwe.onTwcc(fb);
layerSelector.onTwcc(fb);
```

Inside `BandwidthEstimator.onTwcc(fb)`:

1. For each `(transport-seq, arrival-delta-µs)` pair in the feedback:
    * Look up `(sendTimeUs, sizeBytes)` from the stamper's history.
    * Compute `delaySlope = (arrival-delta) − (send-delta)`.
2. Smooth the slope across the feedback's window into
   `_lastSlope`.
3. If `_lastSlope > positiveThreshold`, the network is queuing →
   **decrease**. If `< negativeThreshold` for sustained period →
   **increase**. Else **hold**.
4. Multiply current `currentBps` by the chosen factor (e.g. ×0.85
   for decrease, ×1.05 for increase) and clamp.

The classic Google Congestion Control (GCC) shape, simplified.

---

## 8.4. REMB — the legacy parallel signal

REMB (chapter 7) is a single number: "I, the receiver, estimate the
max bitrate I can handle is X bps". The Subscriber routes
`RembFeedback` into both `bwe.onRemb(fb)` and
`layerSelector.onRemb(fb)`.

`bwe.onRemb`:

* Treats the REMB value as a *cap*: `currentBps = min(currentBps,
  fb.bps)`.
* Stores `_lastRembBps` for stats.

REMB is older than TWCC and most modern Chromes don't send it
anymore. It remains a useful fallback for older Edge versions and
when TWCC is suppressed.

---

## 8.5. RR — the loss signal

`RrFeedback` carries `fractionLost` (0..255 → 0..1) per source. The
BWE folds this into a **loss-based correction**:

* If `fractionLost > 0.10` → strong "decrease" hint.
* If `fractionLost < 0.02` → permits "increase".
* Between → hold.

Combined with the delay-based TWCC signal, the BWE is "hybrid":

```dart
class BandwidthEstimator {
  int currentBps;             // smoothed estimate
  BweDecision lastDecision;   // hold | increase | decrease
  int lastMeasuredBps;
  double lastSlope;           // delay-based
  double lastFractionLost;    // loss-based

  void onTwcc(TwccFeedback fb);
  void onRemb(RembFeedback fb);
  void onRr(RrFeedback fb);
}
```

The two signals can disagree (loss-only when the bottleneck is a
lossy wireless link; delay-only when it's a deep buffer). The
estimator takes the more conservative action.

---

## 8.6. Layer selection

File: [`lib/src/bwe.dart`](../../example/ion_style_sfu/lib/src/bwe.dart).

```dart
class LayerSelector {
  final BandwidthEstimator estimator;
  final LayerBitrateThresholds thresholds;
  Map<String, String> _preferredLayer;   // receiverId → rid
  void Function(String receiverId, String rid)? onLayerChange;

  void onTwcc(TwccFeedback fb);
  void onRemb(RembFeedback fb);
  void onRr(RrFeedback fb);

  String pickLayerFor(String receiverId);
}
```

After every BWE update, `pickLayerFor(receiverId)`:

1. `bps = estimator.currentBps`
2. Look up the receiver's available RIDs (from the Receiver's
   `_byRid` keys).
3. `rid = thresholds.pickRid(bps, availableRids)` (chapter 6 §6.7).
4. If `rid != _preferredLayer[receiverId]`:
    * Apply hysteresis (don't switch if last switch was < 2 s ago).
    * If still committing: `_preferredLayer[receiverId] = rid`,
      fire `onLayerChange(receiverId, rid)`.

`onLayerChange` is wired by the Subscriber to call
`dt.setCurrentLayer(rid)` on the matching DownTrack — which kicks
the two-phase switch in chapter 6 §6.4.

---

## 8.7. The pacer

File: [`lib/src/pacer/leaky_bucket.dart`](../../example/ion_style_sfu/lib/src/pacer/leaky_bucket.dart).

```dart
class LeakyBucketPacer {
  LeakyBucketPacer({
    required void Function(Uint8List rtp, {required bool isRtx}) sink,
    int targetBitrateBps = 8_000_000,
    Duration interval = kDefaultPacerInterval,         // 5 ms
    double maxOvershootFactor = kDefaultMaxOvershootFactor,  // 2.0
    int maxQueueDepth = kDefaultMaxQueueDepth,         // 1024
  });

  void enqueue(Uint8List rtp, bool isRtx);
  void setBitrate(int bps);
  Future<void> close();
}
```

What it does:

1. `enqueue(rtp, isRtx)` appends to `_queue`.
2. Every `interval` (5 ms by default), the timer fires:
    * Compute `budget = targetBitrateBps × interval / 8` bytes
      (plus carry-over from `_overage`).
    * Drain packets from `_queue` until the budget is exhausted or
      the queue is empty.
    * For each drained packet, call `sink(rtp, isRtx: ...)`.
3. If `_queue.length > maxQueueDepth`, drop the oldest packet
   (counts as `packetsDroppedOverflow`). This catches catastrophic
   stalls without OOMing.

The `sink` is `Subscriber.transport.sendRtp(...)` (or `sendRtx`).

**Why the SFU paces:** an x264/VPx encoder produces frames in
bursts (one I-frame, many small P-frames). Without pacing, the
network sees a sawtooth — which TWCC interprets as severe queueing
delay, which depresses the BWE, which drops the layer. With
pacing, the SFU smooths the burst into the network's natural
cadence and the BWE stabilises higher.

---

## 8.8. Wiring the pacer's bitrate to the BWE

`Subscriber.setPacerBitrate(int bps)` is called by the BWE update
loop. The pacer's `targetBitrateBps` becomes
`bwe.currentBps × pacerHeadroom` (e.g. ×1.25 to allow short bursts
above the estimate).

If the BWE drops faster than the encoder can react, the queue
grows; the overflow drop is the safety valve.

---

## 8.9. The full feedback loop

Putting chapters 5–8 together:

```
publisher sends 3 simulcast layers
    │
    ▼
SFU forwards layer 'h' to subscriber
    │
    ▼
each outbound packet:
   TwccStamper.stamp()  ←  PC-wide seq counter
   Pacer.enqueue()
    │
    ▼ (pacer drains every 5 ms)
   transport.sendRtp()
    │
    ▼
subscriber's network adds delay/loss
    │
    ▼
client browser collects TWCC arrivals → emits TWCC feedback
                                       (and RR, possibly REMB)
    │
    ▼
Subscriber._onSubscriberRtcp() routes feedback
    │
    ├─► bwe.onTwcc/Rr/Remb   →  currentBps updated
    │                            │
    │                            ▼
    │                       layerSelector.pickLayerFor()
    │                            │
    │                            ▼
    │                       dt.setCurrentLayer(newRid)
    │                            │
    │                            ▼
    │                       SimulcastRewriter switch in flight
    │                            (waits for keyframe — chapter 6)
    │                            │
    │                            ▼
    │                       upstream PLI to publisher
    │
    └─► subscriber.setPacerBitrate(newBps × 1.25)
                                │
                                ▼
                       LeakyBucketPacer.setBitrate(...)
```

This loop closes about every 50–200 ms (one TWCC feedback packet
per ~30 ms; the BWE smooths over a few of them; layer-switch
hysteresis prevents flapping).

---

## 8.10. What this SFU intentionally doesn't do (yet)

* **Per-subscriber probing**: GCC normally injects probe packets at
  a higher-than-current rate to test for headroom. This SFU
  doesn't — it just waits for the encoder's next burst.
* **TWCC v2 / "send-side BWE"**: same loop but the BWE lives on
  the *subscriber* (browser) side and the SFU just stamps. We do
  send-side estimation here.
* **TMMBR / TMMBN flow control**: optional and rarely used.
* **AV1 dependency-descriptor-based pruning**: see chapter 6 §6.9.

If you want to extend any of these, the seams are
`BandwidthEstimator.onTwcc`, `LayerSelector.pickLayerFor`, and the
DownTrack's `writeRtp` packet gate.

---

Next: [Chapter 9 — Cluster and cascade](./09-CLUSTER-AND-CASCADE.md).
