# **RTCP and SRTCP — A Practical Deep Dive**

> Companion chapter to the [Dart edition tutorial](./README.md).
> RTCP is the most under-documented and most-mis-implemented part
> of WebRTC. This chapter walks through every RTCP message that
> matters for an SFU, the SRTCP wrapper that protects them on the
> wire, and includes hands-on exercises you can run against the
> code in this repo.

---

## Table of contents

1. [Why RTCP is hard](#1-why-rtcp-is-hard)
2. [The packet model: header + compound packets](#2-the-packet-model)
3. [Sender Report (SR, PT=200)](#3-sender-report-sr-pt200)
4. [Receiver Report (RR, PT=201)](#4-receiver-report-rr-pt201)
5. [SDES, BYE](#5-sdes-bye)
6. [Feedback messages: NACK, PLI, FIR](#6-feedback-messages-nack-pli-fir)
7. [Bandwidth feedback: REMB and TWCC](#7-bandwidth-feedback-remb-and-twcc)
8. [SRTCP: encryption + replay protection](#8-srtcp-encryption--replay-protection)
9. [The SFU rewrite layer](#9-the-sfu-rewrite-layer)
10. [Practical exercises](#10-practical-exercises)
11. [Cheat sheet](#11-cheat-sheet)

---

## 1. Why RTCP is hard

RTCP looks deceptively simple — it's "just" a few packet formats — but
it sits at the intersection of three independently-evolving specs:

* **RFC 3550** defines the base SR / RR / SDES / BYE / APP packets and
  a hand-wavy "compound packet" rule that says you must include at
  least one report and one SDES per UDP datagram.
* **RFC 4585 / 5104** layer "feedback" packets (NACK, PLI, FIR…) on
  top, with payload-type 205 (transport) and 206 (payload-specific)
  and a sub-format in the header's RC field.
* **RFC 3711 / 8723** wrap *every* RTCP packet in SRTCP — encrypted
  body + 16-byte AEAD tag + a 4-byte SRTCP index trailer that has
  its own sliding-window replay protection.

Add an SFU on top — which has to *rewrite* SSRCs and RTP timestamps
across the publisher↔subscriber boundary — and you've got the most
fiddly state machine in WebRTC.

The good news: every piece is small and individually testable. This
chapter takes them one at a time, all anchored to the Dart
implementation in [lib/src/rtcp/](../../lib/src/rtcp/),
[lib/src/srtp/](../../lib/src/srtp/), and
[example/ion_style_sfu/lib/src/](../../example/ion_style_sfu/lib/src/).

---

## 2. The packet model

### 2.1. The 4-byte RTCP header

Defined in
[lib/src/rtcp/rtcp_header.dart](../../lib/src/rtcp/rtcp_header.dart):

```text
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|V=2|P|   RC/FMT  |       PT      |             length            |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

* `V=2` always.
* `P` — padding flag.
* `RC/FMT` — five bits whose meaning depends on `PT`:
  * For `SR`/`RR`: number of reception report blocks (0–31).
  * For feedback (`PT=205/206`): the **feedback message type** (FMT)
    selecting the sub-format — e.g. `NACK=1`, `PLI=1`, `FIR=4`,
    `TWCC=15`, `REMB`/`AFB=15`.
* `PT` — packet type:

  | PT  | Type | Class |
  |-----|------|-------|
  | 200 | SR (Sender Report) | base |
  | 201 | RR (Receiver Report) | base |
  | 202 | SDES (Source Description) | base |
  | 203 | BYE | base |
  | 204 | APP | base |
  | 205 | RTPFB (transport-layer feedback) | feedback |
  | 206 | PSFB (payload-specific feedback) | feedback |

  These are mirrored in `RtcpReportTypesEnum` in
  [rtcp_header.dart](../../lib/src/rtcp/rtcp_header.dart).

* `length` — packet length in **32-bit words minus 1** (so a 12-byte
  packet has `length=2`). This is the trip-wire that catches almost
  every parsing bug.

### 2.2. Compound packets

A single UDP/SRTCP payload usually carries **several** RTCP packets
back-to-back. RFC 3550 §6.1 mandates that every compound packet:

* starts with an SR or RR,
* contains at least one SDES with a CNAME item.

Browsers cheat constantly — Chrome will sometimes emit a bare PLI,
and most SFUs (this one included) accept it. The Dart parser walks
the buffer header-by-header until it runs out of bytes:

```dart
// see lib/src/rtcp/compound_packet.dart
final compound = RtcpCompoundPacket.parse(buffer);
compound.senderReport     // RtcpSenderReport?
compound.receiverReport   // RtcpReceiverReport?
compound.sDesReport       // RtcpSdesReport?
compound.bye              // RtcpBye?
compound.feedback         // RtcpFeedback?         ← NACK / PLI / REMB
compound.twccFeedback     // RtcpTwccFeedback?
```

The SFU side uses a leaner, allocation-free walker —
`parseFeedback()` in
[example/ion_style_sfu/lib/src/rtcp.dart](../../example/ion_style_sfu/lib/src/rtcp.dart) —
which yields a sealed `RtcpFeedback` subtree (`NackFeedback`,
`PliFeedback`, `FirFeedback`, `RrFeedback`, `RembFeedback`,
`TwccFeedback`) directly off the `Uint8List`.

---

## 3. Sender Report (SR, PT=200)

A media sender emits an SR every few seconds for **two** reasons:

1. **NTP↔RTP timestamp mapping** (the *sender info* block) — lets
   receivers correlate the wallclock with the codec clock for A/V
   sync.
2. **Reception reports** — embedded RR blocks describing what *this
   sender* has received from the other side (it can include both
   roles in one packet).

### 3.1. Layout

```text
+----- header (4 bytes) -----+
| V=2 P RC | PT=200 | length |
+----------------------------+
| sender SSRC (4)            |
+----------------------------+
| NTP timestamp (8)          |  ← seconds since 1900 + fraction
+----------------------------+
| RTP timestamp (4)          |  ← codec-clock units
+----------------------------+
| sender's packet count (4)  |
+----------------------------+
| sender's octet count (4)   |
+----------------------------+
| reception report blocks    |  ← RC × 24 bytes
+----------------------------+
```

The Dart class:
[lib/src/rtcp/sender_report.dart](../../lib/src/rtcp/sender_report.dart),
fields:

```dart
class RtcpSenderReport {
  int ssrc;
  Int64 ntpTimestamp;      // 64-bit NTP
  int rtpTimestamp;        // 32-bit codec ts
  int packetCount;
  int octetCount;
  List<ReceptionReportSample> receptionReports;
}
```

### 3.2. NTP↔RTP, in plain English

The receiver does:

```text
elapsed_seconds_since_SR = (ntpNow - sr.ntpTimestamp)       // wallclock
expected_rtp_now         = sr.rtpTimestamp
                         + elapsed_seconds_since_SR * codecHz
```

That mapping is what lets a video frame and an audio frame from the
same source line up in time even though they have entirely different
clock rates (90 kHz vs 48 kHz).

### 3.3. Why SFUs must rewrite SR

When the SFU rewrites a publisher's SSRC and shifts its sequence
numbers/timestamps to keep simulcast continuity (chapter 7 §7.4), the
SR's `ssrc` and `rtpTimestamp` fields **also** have to be patched —
or the subscriber will think the wallclock and the media clock have
drifted by hours.

That rewrite happens in `rewriteRtcpForSubscriber()` in
[example/ion_style_sfu/lib/src/rtcp_rewrite.dart](../../example/ion_style_sfu/lib/src/rtcp_rewrite.dart):

* `ssrc` (bytes 4–7 of the SR) → the rewritten primary SSRC.
* `rtpTimestamp` (bytes 16–19) gets `tsOffsetFor(publisherSsrc)`
  added to it (mod 2³²), where the offset is the same one
  `SimulcastRewriter` uses on RTP packets.
* Each embedded reception report block at offset `28 + i*24` has its
  *source SSRC* (first 4 bytes) translated.

---

## 4. Receiver Report (RR, PT=201)

```text
+----- header -----+
| V=2 P RC | PT=201 | length |
+------------------+
| reporter SSRC (4)|
+------------------+
| report block 0   |  ← 24 bytes
| report block 1   |
| …                |
| report block RC-1|
+------------------+
```

Each report block ([reception_report.dart](../../lib/src/rtcp/reception_report.dart))
is **the** RTCP datum:

| Bytes | Field | Notes |
|---|---|---|
| 0–3   | source SSRC | who this block describes |
| 4     | fraction lost | (lost / expected) since last RR, scaled to 0–255 |
| 5–7   | cumulative packets lost | 24-bit signed |
| 8–11  | extended highest seq number | high 16 bits = ROC (rollover) |
| 12–15 | inter-arrival jitter | RFC 3550 §A.8 EMA, RTP-ts units |
| 16–19 | LSR (last SR) | middle 32 bits of last received NTP |
| 20–23 | DLSR | delay since last SR, in 1/65536 sec |

LSR and DLSR exist so a sender can compute **round-trip time** when
it gets the RR back: `RTT = nowNtp − lsr − dlsr`.

The Dart implementation maintains the running state (cycles, max
seq, jitter) inside `ReceptionReportSample.update(seq, arrivalTime,
rtpTs)`, and `RtcpSession`
([lib/src/rtcp/session.dart](../../lib/src/rtcp/session.dart)) calls
it from the inbound RTP callback.

The SFU has its own faster path for inbound stats — it keeps the
counters directly on `Receiver` (chapter 7 §7.5) — and only uses
`ReceptionReportSample` when generating RR for sources where it isn't
already counting per-packet.

---

## 5. SDES, BYE

* **SDES** ([sdes_report.dart](../../lib/src/rtcp/sdes_report.dart)) —
  a list of `(item type, value)` pairs per SSRC. The only mandatory
  item is **CNAME (item type 1)**: a string that uniquely identifies
  the source across SSRC changes (the browser sometimes flips SSRCs
  mid-call).
* **BYE** ([bye.dart](../../lib/src/rtcp/bye.dart)) — sent once when
  a source leaves; carries an optional reason string.

The SFU passes both through unchanged (no SSRC rewrite is needed in
SDES because the CNAME is opaque).

---

## 6. Feedback messages: NACK, PLI, FIR

These are the levers the SFU and the browsers actually pull at
runtime.

### 6.1. NACK — "send me these packets again"

* `PT=205` (`RTPFB`), `FMT=1`.
* FCI is one or more **NACK items**, each 4 bytes:

  ```text
  +-------------------+----------------+
  | PID (16 bits)     | BLP (16 bits)  |
  +-------------------+----------------+
  ```

  `PID` is the missing seq; each set bit `i` of `BLP` (bitmask
  following PID) means "and seq `PID+1+i` is also missing." So one
  NACK item describes up to 17 missing packets in a 17-packet window.

In the Dart SFU:

```dart
// example/ion_style_sfu/lib/src/rtcp.dart
class NackFeedback extends RtcpFeedback {
  final List<NackFci> items;
  Iterable<int> allMissing();   // expands PID + BLP bits to seq numbers
}
```

When the SFU receives a NACK from a *subscriber*, it tries to satisfy
it from its **NACK cache** before bothering the publisher:

```dart
// example/ion_style_sfu/lib/src/buffer/nack.dart
class NackResponder {
  ({List<Uint8List> hits, List<int> stillMissing}) lookup(
    List<int> missing,
  );
}
```

`hits` get re-sent immediately as RTX (RFC 4588) on the subscriber's
RTX SSRC; `stillMissing` is escalated upstream as a NACK against the
publisher.

### 6.2. PLI — "send me a keyframe, please"

* `PT=206` (`PSFB`), `FMT=1`.
* No FCI — header alone (12 bytes total).

PLI is the cheapest "I lost video" signal. A subscriber emits one
when:

* its decoder reported errors, or
* the SFU just performed a layer switch (`SimulcastRewriter` opens
  the keyframe gate after a layer flip).

The SFU forwards PLIs upstream, *coalescing* multiple PLI requests
within a short window so an idle publisher isn't asked for ten
keyframes per second.

### 6.3. FIR — "Full Intra Request" (RFC 5104)

* `PT=206`, `FMT=4`.
* FCI is a list of `(target SSRC, sequence number)` 8-byte entries.

FIR is the older, big-hammer version of PLI. It includes a sequence
number so the receiver can de-dupe identical requests. Modern Chrome
prefers PLI, but Firefox / older versions still emit FIR — the SFU
handles both via `FirFeedback` in
[rtcp.dart](../../example/ion_style_sfu/lib/src/rtcp.dart).

---

## 7. Bandwidth feedback: REMB and TWCC

Two competing schemes. Modern browsers send **TWCC** by default; the
SFU handles both for compatibility.

### 7.1. REMB — Receiver Estimated Max Bitrate

* `PT=206`, `FMT=15` (`AFB` — application-layer feedback).
* FCI starts with the ASCII bytes `'R','E','M','B'`, then:

  ```text
  | num SSRCs | exp (6 bits) | mantissa (18 bits) | SSRC list … |
  ```

  The bitrate is `mantissa << exp` bits per second.

REMB is **rate-only** — the receiver tells the sender "don't send me
more than X bps." Simple, but it has to be combined with the SFU's
own measurements to estimate where the bottleneck actually is.

### 7.2. TWCC — Transport-Wide Congestion Control

The modern path. It splits responsibility:

* **Sender** stamps every outbound RTP packet with a 16-bit
  *transport-wide sequence number* in an RTP header extension
  (RFC 5285).
* **Receiver** periodically emits a TWCC feedback packet that lists
  every received transport-wide seq and its arrival time delta.
* **Sender** turns those arrival deltas into a delay-based bandwidth
  estimate (Google Congestion Control).

The Dart implementation:

* **Stamping**:
  [example/ion_style_sfu/lib/src/twcc/twcc_stamper.dart](../../example/ion_style_sfu/lib/src/twcc/twcc_stamper.dart)
  — `TwccStamper.stamp(rtp, twccExtId)` writes the next 16-bit
  sequence into the matching one-byte extension and remembers
  `(seq → sendTimeUs, sizeBytes)` in a bounded history map.
* **Parsing inbound TWCC**: `TwccFeedback` in
  [example/ion_style_sfu/lib/src/rtcp.dart](../../example/ion_style_sfu/lib/src/rtcp.dart)
  decodes the RFC 8888 chunk encoding (run-length and status-vector)
  into a flat list of `(status, deltaUs)` per stamped seq.
* **Feedback construction** (downstream side):
  [twcc.dart](../../example/ion_style_sfu/lib/src/twcc/twcc.dart) —
  `TwccResponder.observePacket(twSeq, arrivalTime)` records
  arrivals; `buildFeedback()` produces the next TWCC packet to send
  back upstream.
* **Bandwidth estimation**:
  [example/ion_style_sfu/lib/src/bwe.dart](../../example/ion_style_sfu/lib/src/bwe.dart)
  — `BandwidthEstimator.onTwcc(...)` converts arrival deltas to a
  delay slope; `onRr(...)` folds in `fractionLost`. Combined output:
  `currentBps`, which `LayerBitrateThresholds.pickRid()` translates
  into a simulcast layer choice.

### 7.3. The TWCC packet body, briefly

```text
+--- header (PT=205, FMT=15) ---+
| sender SSRC (4)               |
| media SSRC (4)                |
| base sequence number (2)      |  ← first transport seq covered
| packet status count (2)       |  ← how many seqs are described
| reference time (3, 24-bit)    |  ← absolute time, 64 ms units
| feedback packet count (1)     |  ← rolling counter
| packet status chunks …        |  ← run-length OR status-vector
| packet receive deltas …       |  ← 1 or 2 bytes per *received* pkt
+-------------------------------+
```

`packet status chunks` is the trickiest part — see
[twcc_feedback.dart](../../lib/src/rtcp/twcc_feedback.dart) for the
encoder/decoder. Two formats coexist (run-length and 1-bit /
2-bit status vector), chosen to minimise size for the actual
distribution of "received / not received" outcomes.

---

## 8. SRTCP: encryption + replay protection

Once both SRTP contexts are armed (chapter 6), every RTCP packet is
wrapped in SRTCP before it goes on the wire.

### 8.1. The trailer

SRTCP appends a 4-byte trailer to every packet:

```text
+---+-----------------------+
| E |    SRTCP index (31)   |
+---+-----------------------+
```

* `E` (1 bit, MSB) — `1` if the body is encrypted, `0` otherwise.
  Browsers always set it.
* `SRTCP index` (31 bits) — a *per-SSRC* monotonically-increasing
  counter that's part of the GCM nonce input. Distinct from the RTP
  sequence number, distinct from the RTCP "compound packet count" —
  it's its own thing.

The full on-the-wire shape for an AES-128-GCM SRTCP packet is:

```text
| RTCP header (4)
| sender SSRC (4)
| ciphertext body (variable)
| GCM authentication tag (16)
| SRTCP trailer (4)   ← E | index
| (optional) MKI bytes — not used here
```

### 8.2. The Dart implementation

[lib/src/srtp/srtp_context.dart](../../lib/src/srtp/srtp_context.dart):

```dart
Future<Uint8List> encryptRtcpPacket(Uint8List rtcp);
Future<Uint8List> decryptRtcpPacket(Uint8List srtcp);
```

* **Per-SSRC outbound index**: `_srtcpOutIndex: Map<int, int>` —
  starts at 0 for each new SSRC, capped at `0x7FFFFFFF` (31 bits).
  Exhausting it throws (a fresh DTLS handshake would be required).
* **Per-SSRC inbound replay**: `_srtcpInboundReplay: Map<int,
  _SrtcpReplay>` — a 64-entry sliding bitmap on the index space.
  `check(index)` runs *before* GCM decrypt (cheap rejection of
  obvious replays); `commit(index)` runs *after* a successful tag
  verify (so an attacker can't push the window forward with bad
  tags).

### 8.3. Why SRTCP needs its own index

RTCP packets do not carry a sequence number in the clear (the way
RTP does in bytes 2–3). Without an index the AEAD nonce would
collide as soon as the same RTCP message was sent twice — and
duplicate RR/SR packets are perfectly normal. The 31-bit index keeps
the nonce unique.

The "fail at 2³¹" cap is *not* a limit you'll hit in practice: at
4 RTCP packets per second per SSRC, that's ~17 years.

---

## 9. The SFU rewrite layer

When the SFU forwards RTCP across the publisher↔subscriber boundary,
it has to translate SSRCs (and sometimes RTP timestamps) to match the
rewriting it already did on RTP. Without this, subscribers will see
loss reports and SR timestamps for SSRCs they've never heard of.

[example/ion_style_sfu/lib/src/rtcp_rewrite.dart](../../example/ion_style_sfu/lib/src/rtcp_rewrite.dart):

```dart
class RtcpSsrcMap {
  Map<int, int> primary;   // publisher → subscriber-rewritten primary
  Map<int, int> rtx;       // publisher RTX → subscriber-rewritten RTX
  int? translate(int ssrc);
}

Uint8List rewriteRtcpForSubscriber(
  Uint8List rtcp,
  RtcpSsrcMap map, {
  int? Function(int)? tsOffsetFor,
});
```

What it touches:

| PT | What's rewritten |
|---|---|
| 200 (SR) | sender SSRC; RTP timestamp += `tsOffsetFor(publisherSsrc)`; per-block source SSRC |
| 201 (RR) | per-block source SSRC (the reporter SSRC is left alone — it's the subscriber's own ID) |
| 202 (SDES) | passthrough |
| 203 (BYE)  | passthrough |
| 205/206 (NACK / PLI / FIR / REMB / TWCC) | passthrough; the SFU emits its own from scratch when needed |

Why TWCC is *not* SSRC-rewritten in this function: TWCC seq numbers
are transport-wide, and the SFU re-stamps every outbound packet with
its own TWCC seq via `TwccStamper`. The publisher's TWCC seqs aren't
meaningful downstream and aren't forwarded.

---

## 10. Practical exercises

The repo's [test/srtcp_test.dart](../../test/srtcp_test.dart) is the
shortest path into RTCP without a full WebRTC stack. The exercises
below build on it.

### Exercise 1 — Round-trip a Receiver Report through SRTCP

Run the existing test:

```pwsh
cd c:\www\dart\dart-webrtc
dart test test/srtcp_test.dart
```

Read the test source. You'll see:

1. A minimal RR is built by hand (8 bytes: header + reporter SSRC).
2. It's encrypted with the *client* `SRTPContext`.
3. Decrypted with the *server* `SRTPContext`.
4. The SRTCP trailer is parsed back out and the index is asserted to
   increment on the second encrypt.

**Try it:** modify the test to encrypt the same RR ten times and
print the indices. They should be `0..9`. Now decrypt them in
reverse order — only the first (index 9) succeeds; the rest fail the
replay check because index 9 already pushed the window past them.

### Exercise 2 — Build and parse a NACK

In a one-off Dart script:

```dart
import 'dart:typed_data';
import 'package:pure_dart_webrtc_ion_style_sfu/src/rtcp.dart';

void main() {
  // RTCP NACK header: V=2, P=0, FMT=1, PT=205, length=3 (16 bytes total).
  final pkt = Uint8List(16);
  pkt[0] = 0x80 | 0x01;     // V=2, FMT=1
  pkt[1] = 205;             // PT = RTPFB
  pkt[2] = 0; pkt[3] = 3;   // length = 3 (16 bytes / 4 - 1)
  // sender ssrc = 0xAAAAAAAA
  pkt[4] = 0xAA; pkt[5] = 0xAA; pkt[6] = 0xAA; pkt[7] = 0xAA;
  // media ssrc = 0xBBBBBBBB
  pkt[8] = 0xBB; pkt[9] = 0xBB; pkt[10] = 0xBB; pkt[11] = 0xBB;
  // FCI: PID = 100, BLP = 0b...0101 → also 102 and 104 missing
  pkt[12] = 0; pkt[13] = 100;
  pkt[14] = 0; pkt[15] = 0x05;

  for (final fb in parseFeedback(pkt)) {
    if (fb is NackFeedback) {
      print('missing seqs: ${fb.allMissing().toList()}');
      // → [100, 102, 104]
    }
  }
}
```

That's the complete NACK round trip. Try changing `BLP` to `0xFFFF`
and verify all 17 seqs appear.

### Exercise 3 — Find an SR in a live stream

With the SFU running (chapter 1), use Wireshark on the loopback
interface and filter on `udp.port == 51000`. Once SRTP is established
you'll see opaque encrypted blobs — but every ~5 s a slightly larger
one passes that's an SRTCP-wrapped SR.

To verify it from inside the SFU code, set a breakpoint at
`SRTPContext.decryptRtcpPacket` in
[srtp_context.dart](../../lib/src/srtp/srtp_context.dart). On a hit,
inspect the returned plaintext: byte 1 will be `200`. Pass it
through `RtcpCompoundPacket.parse(...)` and read the
`senderReport.rtpTimestamp`.

### Exercise 4 — Trigger a PLI

Easiest reproduction: with two browser tabs joined to the SFU, hit
"refresh" on the *subscriber* tab. The new Subscriber PC starts cold,
so its first job after DTLS is to ask the SFU for a keyframe → the
SFU forwards a PLI upstream → the publisher encoder produces an IDR
(H.264) or keyframe (VP8/VP9).

Set a breakpoint inside the `PliFeedback` branch in
[rtcp.dart](../../example/ion_style_sfu/lib/src/rtcp.dart). You
should see exactly one PLI per refresh — possibly more if the keyframe
is large enough to fragment.

### Exercise 5 — Watch the SR rewrite happen

With both peers connected and a video stream flowing:

1. Set a breakpoint on `rewriteRtcpForSubscriber` in
   [rtcp_rewrite.dart](../../example/ion_style_sfu/lib/src/rtcp_rewrite.dart).
2. When it hits with an SR (PT=200), capture:
   * `rtcp[4..8]` — publisher SSRC.
   * `rtcp[16..20]` — publisher's RTP timestamp.
3. Step over and capture the same offsets in the returned bytes:
   * The SSRC will be the subscriber-side rewritten primary.
   * The RTP timestamp will be `original + tsOffsetFor(publisherSsrc)`.

That offset is the **same** value `SimulcastRewriter` is using to
shift the RTP packets. If they ever diverge, A/V sync will drift —
which is precisely the bug class this rewrite exists to prevent.

### Exercise 6 — Inspect TWCC in flight

1. Make sure you connected with TWCC negotiated (Chrome enables
   `transport-cc` extension by default).
2. Add a one-line print in `TwccStamper.stamp()`:

   ```dart
   print('twcc seq=$_next ts=$sendTimeMicros size=$sizeBytes');
   ```

3. Run a video call. You should see ~30 lines/sec for a 30 fps video
   track, plus audio packets at ~50 lines/sec.

4. Now break in `TwccFeedback` parsing in
   [rtcp.dart](../../example/ion_style_sfu/lib/src/rtcp.dart). Each
   feedback packet contains arrival deltas for ~tens to hundreds of
   the seqs you just printed. If you log
   `(seq, deltaUs)` and bin them, that's the input to GCC.

### Exercise 7 — Force NACK retransmission

Put a chaos hook into the demultiplexer in
[rtc_udp_transport.dart](../../lib/webrtc/rtc_udp_transport.dart):

```dart
// inside _handleDatagram, just before the SRTP decrypt branch:
if (isRtpPacket(data) && Random().nextDouble() < 0.05) return;  // drop 5%
```

Reload the subscriber. You'll see:

* A flood of NACK feedback in
  [rtcp.dart](../../example/ion_style_sfu/lib/src/rtcp.dart)
  (`NackFeedback` cases).
* `NackResponder.lookup()` hitting the cache and re-emitting RTX
  packets.
* The video freezing only occasionally despite the loss — that's the
  jitter buffer and NACK mechanism doing its job.

Remember to remove the chaos hook afterwards.

---

## 11. Cheat sheet

### PT / FMT matrix

| PT  | FMT | Meaning                       | Dart class |
|-----|-----|-------------------------------|---|
| 200 | RC  | Sender Report                 | `RtcpSenderReport` |
| 201 | RC  | Receiver Report               | `RtcpReceiverReport` |
| 202 | RC  | SDES                          | `RtcpSdesReport` |
| 203 | RC  | BYE                           | `RtcpBye` |
| 204 | —   | APP                           | (passthrough) |
| 205 | 1   | NACK                          | `NackFeedback` |
| 205 | 3   | TMMBR (rate request)          | (parsed only) |
| 205 | 15  | TWCC                          | `TwccFeedback` / `RtcpTwccFeedback` |
| 206 | 1   | PLI                           | `PliFeedback` |
| 206 | 4   | FIR                           | `FirFeedback` |
| 206 | 15  | REMB / generic AFB            | `RembFeedback` |

### Length field, in three rules

* `length` is in **32-bit words minus 1**.
* A bare PLI (12 bytes) has `length = 2`.
* If your parser walks off the end of the buffer, you got the
  word-vs-byte conversion wrong. Always.

### SRTCP nonce inputs

| Nonce part | Source |
|---|---|
| Implicit IV | derived from the master key + PRF |
| SSRC | bytes 4–7 of the RTCP header |
| SRTCP index | trailing 4 bytes (mask off the E bit) |
| Roll-over | none — the index is global per SSRC |

### Where each piece of state lives

| State | Owner |
|---|---|
| Inbound packet counters | `Receiver` ([receiver.dart](../../example/ion_style_sfu/lib/src/receiver.dart)) |
| Per-SSRC inbound jitter (RFC 3550 EMA) | `Receiver` |
| Outbound NACK cache | `JitterBuffer` + `NackResponder` ([buffer/](../../example/ion_style_sfu/lib/src/buffer/)) |
| TWCC seq → `(sendTime, size)` history | `TwccStamper` |
| Per-subscriber BWE state | `BandwidthEstimator` ([bwe.dart](../../example/ion_style_sfu/lib/src/bwe.dart)) |
| Per-SSRC SRTCP index | `_srtcpOutIndex` in [srtp_context.dart](../../lib/src/srtp/srtp_context.dart) |
| Per-SSRC SRTCP replay window | `_srtcpInboundReplay` in same file |

### Common pitfalls

1. **Forgetting the SRTCP trailer** when computing GCM length —
   the 4 trailer bytes are *outside* the AEAD ciphertext range.
2. **Not rewriting the SR `rtpTimestamp`** when forwarding — A/V
   drifts by exactly the simulcast offset.
3. **Treating NACK BLP as little-endian** — it's big-endian like
   everything else in RTCP, but the bit assignment is "bit `i` =
   PID + 1 + i", *not* "bit `i` = PID + i".
4. **Sending PLI per packet loss** — coalesce. One PLI per
   ~500 ms is plenty.
5. **Allocating a `Packet` for every datagram** on the hot path —
   the Dart SFU uses byte helpers in
   [rtp_header.dart](../../example/ion_style_sfu/lib/src/rtp_header.dart)
   to avoid allocations; do the same for RTCP if you ever profile a
   bottleneck.

---

That's the full RTCP/SRTCP picture. Once you can comfortably write
the table in §11.1 from memory and run exercises 1–4 without notes,
you understand more about WebRTC than 90% of people who *use*
WebRTC daily.

<br>

---

<div align="right">

[&lt;&nbsp;&nbsp;Documentation Index](./README.md)

</div>
