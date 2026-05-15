# **7. SRTP PACKETS COME**

The handshake is done, both `SRTPContext`s are armed, and the
browser's encoder finally starts pushing media. Each UDP datagram
arriving on the publisher's socket is now an **SRTP packet** (or an
SRTCP one), and the SFU's job becomes:

1. **Decrypt** the packet → get plaintext RTP.
2. **Hand the RTP off to the SFU's media plane** so it can be
   forwarded to subscribers.
3. **Re-encrypt** when sending downstream over each subscriber's
   own SRTP context.

## **7.1. Anatomy of an RTP packet**

The plaintext header is 12 bytes (RFC 3550 §5.1) plus optional
CSRC list and extension area:

```text
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|V=2|P|X|  CC   |M|     PT      |       sequence number         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                           timestamp                           |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|           synchronization source (SSRC) identifier            |
+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
|            contributing source (CSRC) identifiers             |
|                             ....                              |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
| RFC 5285 header extensions (when X=1)                         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
| payload …                                                     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

In the Dart code:

* High-level packet object: `Packet` in [lib/src/rtp/](../../lib/src/rtp/) /
  [lib/src/rtp2/](../../lib/src/rtp2/).
* Byte-level helpers (used on the SFU hot path so we don't allocate
  a `Packet` per datagram):
  * `rtpSeq(buf)`, `rtpTimestamp(buf)`, `rtpPayloadOffset(buf)` —
    [example/ion_style_sfu/lib/src/rtp_header.dart](../../example/ion_style_sfu/lib/src/rtp_header.dart).
  * `readRtpExtensions(buf)`, `decodeRidString(...)`,
    `decodeAudioLevel(...)`, `stripAudioLevel(...)` — same file.

## **7.2. Decrypt: SRTP → RTP**

From `RtcUdpTransport._handleDatagram` (chapter 4):

```dart
if (isRtpPacket(data)) {
  final ctx = p.srtp;
  if (ctx != null && ctx.gcm != null) {
    final pkt = rtp.Packet.unmarshal(data);
    ctx.decryptRtpPacket(pkt).then((decoded) {
      onRtp?.call(p, decoded);    // → SFU media plane
    }).catchError((Object e) { /* drop on decrypt failure */ });
  }
  return;
}
```

`SRTPContext.decryptRtpPacket()` (in
[lib/src/srtp/srtp_context.dart](../../lib/src/srtp/srtp_context.dart)):

1. Looks up the per-SSRC state (ROC, replay window, session keys).
2. Computes the 32-bit + 16-bit (ROC + seq) reconstructed packet
   index used as the AEAD nonce input.
3. **Replay check** against the sliding window — drops duplicates
   and packets too far in the past.
4. Calls `GCM.decrypt()` from
   [lib/src/srtp/crypto_gcm.dart](../../lib/src/srtp/crypto_gcm.dart)
   (or AES-CM + HMAC-SHA1 for the legacy profile).
5. On success: returns the plaintext payload, advances the highest-
   seq tracker and slides the replay window.

The `onRtp` callback registered on the `RtcUdpTransport` is what hands
the plaintext packet to the SFU.

## **7.3. SRTCP**

`isRtcpPacket(data)` distinguishes RTCP from RTP via the RFC 5761
payload-type trick (RTCP PTs live in 64–95). RTCP gets a separate
path because:

* Its packet shape is different — compound packets, a 4-byte SSRC at
  byte 4, and a 4-byte SRTCP-specific index suffix in encrypted form.
* It uses `decryptRtcpPacket()`, also on `SRTPContext`.

The SFU hooks `onRtcp?.call(p, decoded)` to forward, rewrite or
generate feedback (NACK, PLI, REMB, TWCC). The forwarding/rewrite
logic for the example SFU lives in
[example/ion_style_sfu/lib/src/rtcp.dart](../../example/ion_style_sfu/lib/src/rtcp.dart)
and the sub-modules in
[example/ion_style_sfu/lib/src/twcc/](../../example/ion_style_sfu/lib/src/).

## **7.4. The forwarding plane: Receiver → DownTrack**

Once decrypted, the RTP packet enters the *media plane*:

```text
inbound SRTP
   ↓ decrypt
RTP packet (Uint8List + parsed header)
   ↓ Publisher.deliverRtp(...)
Receiver.deliverRtp(rtp)             ← matches SSRC → ProducerLayer
   ↓ for each attached DownTrack:
DownTrack.writeRtp(layer, isRtx, rtp)
   ↓ SimulcastRewriter.rewrite(...)  ← per-layer SN/TS continuity
   ↓ encrypt
outbound SRTP (per-subscriber SRTPContext)
```

The relevant files:

| Step | File |
|---|---|
| `Receiver.deliverRtp` | [example/ion_style_sfu/lib/src/receiver.dart](../../example/ion_style_sfu/lib/src/receiver.dart) |
| `DownTrack.writeRtp`  | [example/ion_style_sfu/lib/src/down_track.dart](../../example/ion_style_sfu/lib/src/down_track.dart) |
| Simulcast SN/TS rewriter | [example/ion_style_sfu/lib/src/simulcast_rewriter.dart](../../example/ion_style_sfu/lib/src/simulcast_rewriter.dart) |
| RTX (RFC 4588) handling | inside the rewriter — looks at the embedded OSN field |
| Codec-aware keyframe gate | [vp8.dart](../../example/ion_style_sfu/lib/src/vp8.dart), [vp9.dart](../../example/ion_style_sfu/lib/src/vp9.dart), [h264.dart](../../example/ion_style_sfu/lib/src/h264.dart) |

The key idea — and why the Dart SFU is structured the way it is —
is that **the SFU doesn't decode media**. It rewrites SSRCs,
sequence numbers, timestamps, RTX OSNs, and a few RTP header
extensions, then re-encrypts. Decode is only a thing for the
side-tools in [bin/vpx_*.dart](../../bin/) and the codec demos.

## **7.5. Per-SSRC state on the receiver side**

`Receiver` (in [receiver.dart](../../example/ion_style_sfu/lib/src/receiver.dart))
also maintains:

* **Inter-arrival jitter** — RFC 3550 §A.8 EMA, exposed via
  `Receiver.jitterMs`.
* **Receive counters** — `packetsReceived`, `bytesReceived`,
  `rtxPacketsReceived`, `packetsLost` (estimated from per-SSRC
  sequence-number gaps with wrap detection).
* **Audio-level observer feed** — when the publisher negotiated
  RFC 6464 `ssrc-audio-level`, primary audio packets are pushed into
  the per-room
  [`AudioObserver`](../../example/ion_style_sfu/lib/src/audio_observer.dart)
  to drive active-speaker detection.

These feed the RR / TWCC feedback the SFU emits back upstream.

## **7.6. The simulcast rewriter, briefly**

When the publisher sends three encodings (low / mid / high) and the
SFU flips a subscriber from one layer to another, the outbound
sequence-number / timestamp space must stay monotonically continuous
or the decoder will drop frames. `SimulcastRewriter` keeps a
`(snOffset, tsOffset)` per layer recomputed at every layer switch,
plus a **keyframe gate** so it doesn't open the new layer mid-GOP.

Codec-specific detectors (`isVp8Keyframe`, `isVp9Keyframe`,
`isH264Keyframe`) sit in their respective files in
[example/ion_style_sfu/lib/src/](../../example/ion_style_sfu/lib/src/).

## **7.7. Encrypt: RTP → SRTP (downstream)**

Each `Subscriber` owns its own `RtcPeerTransport` → `SRTPContext`
(symmetrically: its own DTLS handshake, its own keys). When
`DownTrack.writeRtp` finishes building the rewritten packet, it
calls `subscriber.sendRtp(packet)`, which:

1. Acquires a buffer from the per-isolate `BytePool` (avoids GC churn
   on the hot path) — [example/ion_style_sfu/lib/src/buffer/](../../example/ion_style_sfu/lib/src/).
2. Calls `outboundContext.encryptRtpPacket(...)`.
3. Sends the resulting bytes through the subscriber's
   `RtcUdpTransport.sendDatagram(...)`.

Same path for RTCP via `encryptRtcpPacket`.

## **7.8. Where to set breakpoints**

| Question | Breakpoint |
|---|---|
| Did SRTP decrypt? | `SRTPContext.decryptRtpPacket` ([srtp_context.dart](../../lib/src/srtp/srtp_context.dart)) |
| Was the packet replayed? | `_SrtpReplay.check()` in same file |
| Did the SFU receive a frame? | `Publisher._onRtp` / `Receiver.deliverRtp` |
| Did it reach a subscriber? | `DownTrack.writeRtp` |
| What did it look like on the wire? | `RtcUdpTransport.sendDatagram` |

By the end of this chapter, an end-to-end media path exists for every
subscriber. The remaining puzzle is what's actually *inside* the
payload — chapter 8 cracks open a VP8 packet.

<br>

---

<div align="right">

[&lt;&nbsp;&nbsp;Previous chapter: SRTP INITIALIZATION](./06-SRTP-INITIALIZATION.md)&nbsp;&nbsp;|&nbsp;&nbsp;[Next chapter: VP8 PACKET DECODE&nbsp;&nbsp;&gt;](./08-VP8-PACKET-DECODE.md)

</div>
