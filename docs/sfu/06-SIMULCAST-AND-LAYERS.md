# 6. Simulcast and layers

Simulcast is what makes an SFU pay off. The publisher encodes the
same video N times at different bitrates and sends them all; the
SFU forwards **one** layer per subscriber, picking based on each
subscriber's measured bandwidth. The challenge: subscribers can't
see the layer flip. SN, TS, SSRC must look continuous.

---

## 6.1. RID, simulcast SDP, and what the publisher sends

The publisher's SDP advertises simulcast via:

```text
a=extmap:4 urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id
a=extmap:5 urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id
a=rid:q send
a=rid:h send
a=rid:f send
a=simulcast:send q;h;f
```

— meaning "I will send three layers labelled `q`, `h`, `f`, and the
RID of each packet is in extension id 4."

The publisher then sends three RTP streams in parallel, each with a
**different SSRC** (chosen by the publisher), each tagged with its
RID in the extension. RTX packets carry the *primary's* RID via
extension 5 ("repaired-rid").

The SFU never tells the publisher which layers to send — that's
purely the publisher's choice, sometimes adapted by its own internal
estimator. The SFU only chooses which *forwarded* layer each
subscriber sees.

---

## 6.2. The data structures

* `ProducerStream.layers: List<ProducerLayer>` — chapter 3 §3.5.
  Three entries for `q`/`h`/`f`. SSRCs are filled in either at SDP
  parse time (Firefox-style with explicit `a=ssrc-group`) or
  lazily on first packet (Chrome-style with RID extension only).

* `Receiver._byRid` — RID → layer.

* `DownTrack._rewriter.currentLayer` — which RID this DownTrack is
  currently *forwarding*. Starts at the lowest available, switches
  on BWE.

---

## 6.3. The SimulcastRewriter

File: [`lib/src/simulcast_rewriter.dart`](../../example/ion_style_sfu/lib/src/simulcast_rewriter.dart).

```dart
class SimulcastRewriter {
  final int rewrittenPrimarySsrc;
  final int rewrittenRtxSsrc;
  String currentLayer = '';
  bool get switchInFlight;

  bool setCurrentLayer(String rid);   // returns true if a real switch
  RewriteResult rewrite(Uint8List rtp);
}

class RewriteResult {
  final Uint8List packet;   // possibly the same buffer
  final bool dropped;       // true if this packet should be silently dropped
}
```

State held per-layer in `_layerOffsets: Map<String, _LayerOffset>`:

```text
_LayerOffset {
  int snOffset;    // added to (rtp.seq) to produce outbound seq
  int tsOffset;    // added to (rtp.ts) to produce outbound ts
}
```

The **purpose of the offsets** is to absorb the discontinuity
between layers. Each layer has its own SN/TS, with no relation to
the other layers. By keeping a per-layer offset, the rewriter can
make all layers *appear* as one continuous stream from the
subscriber's perspective.

---

## 6.4. The switch protocol

A layer switch is **two-phase**:

```
phase 1 (announce):  setCurrentLayer('h') called by LayerSelector.
                     _resyncOnNext = true.
                     currentLayer is *not* changed yet.

phase 2 (commit):    next packet whose RID == 'h' AND isKeyframe(packet) == true
                     →  compute new offsets so output SN/TS continue from
                        the last forwarded SN/TS,
                        currentLayer = 'h',
                        _resyncOnNext = false,
                        forward the keyframe.

between phases:      packets on the *old* layer ('q') still flow
                     normally; packets on the new layer that aren't
                     keyframes are dropped (no reference frames in
                     the decoder yet, so they'd render as artifacts).
```

In code (paraphrased):

```dart
RewriteResult rewrite(Uint8List rtp) {
  final rid = _ridOf(rtp);
  if (_resyncOnNext && rid == _pendingLayer) {
    if (!_isKeyframe(rtp)) {
      return RewriteResult(packet: rtp, dropped: true);  // wait for keyframe
    }
    // commit
    _layerOffsets[rid] = _LayerOffset(
      snOffset: _lastOutSn + 1 - rtpSeq(rtp),
      tsOffset: _lastOutTs + _tsBumpFor(rid) - rtpTimestamp(rtp),
    );
    currentLayer = rid;
    _resyncOnNext = false;
  }
  if (rid != currentLayer) {
    return RewriteResult(packet: rtp, dropped: true);  // wrong layer
  }
  // apply offsets, return rewritten copy
  ...
}
```

The `_isKeyframe` function pointer is plugged in by the DownTrack
based on the codec — `isVp8Keyframe`, `isVp9Keyframe`, or
`isH264Keyframe` from
[`vp8.dart`](../../example/ion_style_sfu/lib/src/vp8.dart),
[`vp9.dart`](../../example/ion_style_sfu/lib/src/vp9.dart),
[`h264.dart`](../../example/ion_style_sfu/lib/src/h264.dart).

---

## 6.5. Forcing a keyframe — the PLI side

A switch can only commit on a keyframe, but keyframes are
relatively rare (one every few seconds). Waiting blocks the switch.

So when `setCurrentLayer` flips, the DownTrack also fires an
**upstream PLI** for the new layer:

```dart
final upstreamPli = buildPliPacket(
  senderSsrc: 0,
  mediaSsrc: receiver.primarySsrcForLayer(newRid),
);
receiver.router.onUpstreamFeedback?.call(upstreamPli);
```

The publisher receives the PLI, the encoder produces a keyframe on
the requested layer, and the switch commits within ~1 RTT. Without
the PLI, you'd be at the mercy of the encoder's natural keyframe
cadence.

---

## 6.6. Codec keyframe detectors

These are intentionally one-line shims that tell the rewriter "yes,
this packet starts a fresh reference frame":

| Codec | Detector | What it checks |
|---|---|---|
| VP8 | `isVp8Keyframe(rtp)` in [`vp8.dart`](../../example/ion_style_sfu/lib/src/vp8.dart) | S=1, PartID=0, payload byte 0 bit 0 == 0 (P=0 in VP8 frame tag) |
| VP9 | `isVp9Keyframe(rtp)` in [`vp9.dart`](../../example/ion_style_sfu/lib/src/vp9.dart) | B=1, P=0 in the VP9 payload descriptor |
| H.264 | `isH264Keyframe(rtp)` in [`h264.dart`](../../example/ion_style_sfu/lib/src/h264.dart) | NAL type ∈ {5 (IDR), 7 (SPS), 8 (PPS)}, walking STAP-A and FU-A as needed |

For audio (Opus, PCMA, PCMU) every packet is independently
decodable — there's no concept of "keyframe" — so the detector is
`(rtp) => true` and there's no two-phase switch (audio also doesn't
simulcast in this SFU, though it could in principle).

---

## 6.7. Picking the layer — `LayerBitrateThresholds`

File: [`lib/src/bwe.dart`](../../example/ion_style_sfu/lib/src/bwe.dart).

```dart
class LayerBitrateThresholds {
  final int qMinBps;   // e.g. 150_000
  final int hMinBps;   // e.g. 500_000
  final int fMinBps;   // e.g. 1_500_000

  String pickRid(int bps, List<String> availableRids) {
    if (bps >= fMinBps && availableRids.contains('f')) return 'f';
    if (bps >= hMinBps && availableRids.contains('h')) return 'h';
    return 'q';
  }
}
```

The `LayerSelector` calls `pickRid(bwe.currentBps,
receiver.availableRids)` on every BWE update. If the result differs
from `dt.currentLayer`, it calls `dt.setCurrentLayer(rid)`.

To avoid thrashing right at a threshold, the LayerSelector wraps
the choice in a hysteresis: hold-time after a switch, plus a small
"escape velocity" requirement (the BWE has to overshoot the
threshold by ~10% to switch up, but only return to it to switch
down). The exact constants live next to the class.

---

## 6.8. What the subscriber sees

At any point in time, the subscriber's RTP stream looks like one
homogeneous stream: same SSRC, monotonic SN, monotonic TS at the
codec's expected cadence.

What's actually happening:

```
publisher's q layer:  ssrc=A, sn=… ts=…
publisher's h layer:  ssrc=B, sn=… ts=…   ← we forward from here
publisher's f layer:  ssrc=C, sn=… ts=…

  ↓  SimulcastRewriter applies (snOffset_h, tsOffset_h)

subscriber sees:      ssrc=R, sn=monotonic, ts=monotonic
```

When the SFU switches `h` → `f`:

```
subscriber sees:      ssrc=R, sn=monotonic (still!), ts=monotonic (still!)
```

— because the rewriter recomputed the offsets on commit. The decoder
sees one stream, not three, and never has to flush its buffers.

---

## 6.9. Limitations and where SVC would change things

This SFU treats each simulcast layer independently. It does **not**
do *temporal-layer pruning* (forwarding only every other frame of
VP8/H.264 to drop bitrate by ~half) or *spatial-layer pruning* of
SVC (forwarding only the base layer of VP9-SVC).

For VP9 / AV1 SVC, the publisher's bitstream is naturally
hierarchical: dropping the top temporal layer at the SFU is
zero-CPU and gives a smooth bitrate ladder without renegotiation.
Implementing that would mean parsing the VP9/AV1 payload descriptor
deeply enough to know which packets belong to which layer, then
gating in the DownTrack. The hooks are there (`isKeyframe` is
already pluggable) but the gate is not.

---

Next: [Chapter 7 — RTCP and feedback](./07-RTCP-AND-FEEDBACK.md).
