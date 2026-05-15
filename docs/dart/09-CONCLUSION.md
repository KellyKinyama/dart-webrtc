# **9. CONCLUSION**

You followed a single packet from the browser's encoder, through ICE,
DTLS, and SRTP, into the SFU's media plane, out across a router and a
simulcast rewriter, back through SRTP, and into another peer's
decoder — all in pure Dart.

The headline takeaways:

* **Pure Dart goes a long way.** Every protocol on the WebRTC stack —
  STUN, ICE, DTLS 1.2, SRTP/SRTCP, RTP, RTCP, SDP — is implemented
  in this repo without `dart:ffi`. The only native dependency is
  `libvpx` for raw codec work, and even that is optional unless you
  need pixels.
* **The SFU is a thin wiring layer.** The `ion_style_sfu` example is
  ~30 source files in
  [example/ion_style_sfu/lib/src/](../../example/ion_style_sfu/lib/src/)
  on top of the protocol primitives in
  [lib/](../../lib/). Most of the bulk is forwarding logic
  (Receiver / Router / DownTrack / SimulcastRewriter), not crypto.
* **One UDP socket per `RTCPeerConnection`.** The Dart codebase
  trades the Go original's single-port multiplexer for per-PC
  sockets. It's simpler to reason about, easier to terminate, and
  makes test isolation trivial — at the cost of one extra ephemeral
  port per peer.
* **Per-PC certificates and lazy state.** Nothing crypto-relevant
  is allocated until a peer is *known good* (chapter 4 §4.2). The
  attack surface for forged-source-port floods is small.
* **Continuous flows replace background goroutines.** Dart's
  single-threaded event loop is enough — `async`/`await` keeps the
  control flow linear without sacrificing throughput, and
  `ShardedSfu` adds isolate-level concurrency only where it matters.

## Where to read next

* The protocol implementation: [lib/src/](../../lib/src/).
* The SFU example: [example/ion_style_sfu/](../../example/ion_style_sfu/).
* Other end-to-end examples:
  [example/play_from_disk/](../../example/play_from_disk/),
  [example/whip_publisher/](../../example/whip_publisher/),
  [example/whip_server/](../../example/whip_server/),
  [example/rtsp_to_webrtc/](../../example/rtsp_to_webrtc/),
  [example/sfu/](../../example/sfu/).
* The original Go-based tutorial that inspired this port:
  [../README.md](../README.md).

If something in this tutorial doesn't match the code on `main` —
the code wins. File an issue.

---

<div align="right">

[&lt;&nbsp;&nbsp;Previous chapter: VP8 PACKET DECODE](./08-VP8-PACKET-DECODE.md)&nbsp;&nbsp;|&nbsp;&nbsp;[Documentation Index&nbsp;&gt;](./README.md)

</div>
