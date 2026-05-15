# **8. VP8 PACKET DECODE**

The Go original ended its tour by feeding a VP8 RTP payload into
`libvpx` and producing decoded YUV. The Dart port can do the same —
**but** the SFU itself never decodes media (chapter 7 §7.4); it
forwards opaque RTP. So this chapter splits in two:

1. **What the SFU does with VP8 packets** (parse the RTP descriptor,
   detect keyframes, rewrite picture-IDs across simulcast layer
   switches).
2. **How the side-tools in [bin/](../../bin/) decode VP8 to raw
   frames** when you actually want pixels.

## **8.1. The VP8 RTP payload descriptor (RFC 7741)**

Every VP8 RTP packet starts with a variable-length descriptor before
the VP8 bitstream:

```text
 0 1 2 3 4 5 6 7
+-+-+-+-+-+-+-+-+
|X|R|N|S|R| PID | ← required first byte
+-+-+-+-+-+-+-+-+
|I|L|T|K|     RSV    |  (only if X=1)
+-+-+-+-+-+-+-+-+
|     PictureID     |  (only if I=1; 7- or 15-bit)
+-+-+-+-+-+-+-+-+
|     TL0PICIDX     |  (only if L=1)
+-+-+-+-+-+-+-+-+
| TID|Y| KEYIDX |     (only if T=1 or K=1)
+-+-+-+-+-+-+-+-+
| VP8 frame data …
```

The Dart parser is `parseVp8Descriptor()` in
[example/ion_style_sfu/lib/src/vp8.dart](../../example/ion_style_sfu/lib/src/vp8.dart).
It returns a `Vp8Descriptor` exposing `headerLength`,
`startOfPartition`, `partitionIndex`, `pictureId`, `tl0PicIdx`, and
the byte offsets of each field (so the rewriter in §8.3 can patch
them in place).

## **8.2. Keyframe detection**

`isVp8Keyframe(rtp)` (same file) returns true iff the packet is the
**first partition of a VP8 keyframe**:

* `S=1` and `PID=0` (start of partition zero in this access unit).
* The first byte of the VP8 uncompressed header (`payloadOffset +
  desc.headerLength`) has bit 0 = 0 (the inverse-keyframe `P` bit
  per RFC 6386 §9.1).

The SFU uses this in two places:

* **Layer-switch keyframe gate** (`SimulcastRewriter`) — drop the
  first delta frames of the new layer until a keyframe lands, so the
  decoder sees a clean GOP boundary.
* **PLI / FIR generation** — when the SFU notices a subscriber would
  benefit from a keyframe (layer switch, packet loss) it sends a
  `Picture-Loss-Indication` upstream. RTCP machinery is in
  [example/ion_style_sfu/lib/src/rtcp.dart](../../example/ion_style_sfu/lib/src/rtcp.dart).

VP9 and H.264 have analogous detectors in
[vp9.dart](../../example/ion_style_sfu/lib/src/vp9.dart) and
[h264.dart](../../example/ion_style_sfu/lib/src/h264.dart).

## **8.3. Picture-ID rewriting across simulcast layers**

VP8 PictureID is a per-encoder counter. When the SFU switches a
subscriber from the *low* layer to the *high* layer, the new layer's
PictureID space starts wherever its encoder happens to be — usually
not where the previous layer left off. A naive forward jump or
backward step would make the decoder drop frames.

`Vp8PicIdRewriter` (in
[vp8.dart](../../example/ion_style_sfu/lib/src/vp8.dart)) keeps a
per-layer offset that's recomputed on every keyframe-aligned layer
switch so the *outbound* PictureID stays monotonically increasing
modulo `0x8000` (15-bit) — same idea as `SimulcastRewriter` but for
the codec descriptor instead of the RTP header.

`TL0PICIDX` is patched the same way (modulo `0x100`).

## **8.4. Where the actual decode lives**

The forwarding plane never decodes. If you want raw frames out, use
the FFI binding to **libvpx**:

| File | What it is |
|---|---|
| [lib/vpx.dart](../../lib/vpx.dart) | Public Dart wrapper |
| [generated_bindings.dart](../../generated_bindings.dart) | `dart:ffi` bindings to `libvpx` |
| [lib/src/codecs/vpx/vpx_decoder.dart](../../lib/src/codecs/vpx/) | High-level `VpxDecoder` |
| [lib/src/codecs/vpx/vpx_encoder.dart](../../lib/src/codecs/vpx/) | High-level `VpxEncoder` |
| [lib/src/codecs/vpx/ivf.dart](../../lib/src/codecs/vpx/) | IVF file format I/O |
| [lib/src/codecs/vpx/i420_frame.dart](../../lib/src/codecs/vpx/) | Decoded I420 (YUV) frame |

The CLIs in [bin/](../../bin/) wire these together:

* [bin/vpx_decode.dart](../../bin/vpx_decode.dart) — IVF in, YUV out.
* [bin/vpx_encode.dart](../../bin/vpx_encode.dart) — RGB24 in, IVF out.
* [bin/vpx_example.dart](../../bin/vpx_example.dart) — end-to-end
  encode/decode round-trip.
* [bin/vpx_test_vectors.dart](../../bin/vpx_test_vectors.dart) —
  conformance harness against the WebM project's test vectors.

A typical decode loop:

```dart
final dec = VpxDecoder(VpxCodec.vp8);
final ivf = IvfReader.openSync('example.ivf');
for (final frame in ivf.frames) {
  final i420 = dec.decode(frame.data);   // returns I420Frame
  i420?.writeTo(yuvSink);                // 3 planes (Y, U, V)
}
```

This is what you'd plug into a custom recording sink, a VP8 → JPEG
thumbnail tap, or a server-side video analytics pipeline.

## **8.5. Going from SRTP to a decoder, end-to-end**

Putting chapters 6–8 together — what you'd write in a custom Dart
client that *records* an inbound VP8 stream:

```dart
final transport = await RtcUdpTransport.bind(/* … */);
transport.onRtp = (peer, pkt) async {
  // 1. drop everything that isn't VP8 (PT comes from your SDP)
  if (pkt.header.payloadType != vp8Pt) return;

  // 2. depacketize: collect the partitions of one frame
  final frame = depacketizer.add(pkt);
  if (frame == null) return;             // not yet complete

  // 3. decode
  final yuv = vpxDecoder.decode(frame.data);

  // 4. do whatever you wanted to do with raw YUV
  if (yuv != null) await yuvSink.add(yuv);
};
```

The depacketizer-by-codec is **not** something the SFU needs (it
forwards individual packets unchanged), so there's no shipped
"VP8 frame assembler" in the SFU package — see the H.264 example in
[lib/src/codecs/h264/h264_rtp.dart](../../lib/src/codecs/) and
[bin/srtp_client.dart](../../bin/srtp_client.dart) for the inverse
direction (frame → packets).

## **8.6. Summary of who does what**

| Concern | Owner |
|---|---|
| Decrypt SRTP | `SRTPContext` |
| Parse RTP header bytes | `rtpSeq` / `rtpPayloadOffset` etc. in [rtp_header.dart](../../example/ion_style_sfu/lib/src/rtp_header.dart) |
| Parse VP8 descriptor | `parseVp8Descriptor` in [vp8.dart](../../example/ion_style_sfu/lib/src/vp8.dart) |
| Detect VP8 keyframe | `isVp8Keyframe` in same file |
| Rewrite PictureID across layers | `Vp8PicIdRewriter` in same file |
| Decode VP8 → YUV | `VpxDecoder` ([lib/src/codecs/vpx/](../../lib/src/codecs/)) — **only used by side-tools** |

That closes the loop: a packet that left the browser's encoder, was
encrypted by SRTP, demultiplexed by `RtcUdpTransport`, decrypted by
`SRTPContext`, picked up by `Receiver`, fanned out by `Router`,
rewritten by `SimulcastRewriter` and `Vp8PicIdRewriter`, re-encrypted
by another `SRTPContext`, and finally landed in another browser's
decoder — possibly several thousand kilometres away.

<br>

---

<div align="right">

[&lt;&nbsp;&nbsp;Previous chapter: SRTP PACKETS COME](./07-SRTP-PACKETS-COME.md)&nbsp;&nbsp;|&nbsp;&nbsp;[Next chapter: CONCLUSION&nbsp;&nbsp;&gt;](./09-CONCLUSION.md)

</div>
