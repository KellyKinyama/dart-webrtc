# **WebRTC Nuts and Bolts — Dart Edition**

A step-by-step adventure through a WebRTC stream, narrated against the
**pure-Dart** implementation in this repository
(`pure_dart_webrtc` + the `ion_style_sfu` example).

This tutorial is a Dart-language re-port of the Go-based original
*"WebRTC Nuts and Bolts"* tutorial that lives one folder up
(see [../README.md](../README.md)). The story is the same — a packet's
journey from the browser to the SFU and back — but every line of code,
every type, and every file path now points at the Dart source tree.

> The reference application is the **ion-style SFU** under
> [example/ion_style_sfu/](../../example/ion_style_sfu/), which uses
> the protocol primitives in [lib/](../../lib/) (DTLS, ICE, STUN, SRTP,
> RTP/RTCP, SDP). When a chapter says *"the server"*, it means
> [example/ion_style_sfu/bin/sfu_server.dart](../../example/ion_style_sfu/bin/sfu_server.dart).

---

## Chapters

[0. INFRASTRUCTURE](./00-INFRASTRUCTURE.md)
<br>[1. RUNNING IN DEVELOPMENT MODE](./01-RUNNING-IN-DEV-MODE.md)
<br>[2. SERVER INITIALIZATION](./02-BACKEND-INITIALIZATION.md)
<br>[3. FIRST CLIENT COMES IN](./03-FIRST-CLIENT-COMES-IN.md)
<br>[4. STUN BINDING REQUEST FROM CLIENT](./04-STUN-BINDING-REQUEST-FROM-CLIENT.md)
<br>[5. DTLS HANDSHAKE](./05-DTLS-HANDSHAKE.md)
<br>[6. SRTP INITIALIZATION](./06-SRTP-INITIALIZATION.md)
<br>[7. SRTP PACKETS COME](./07-SRTP-PACKETS-COME.md)
<br>[8. VP8 PACKET DECODE](./08-VP8-PACKET-DECODE.md)
<br>[9. CONCLUSION](./09-CONCLUSION.md)

## Deep-dive companion chapters

* [RTCP and SRTCP — A Practical Deep Dive](./RTCP-AND-SRTCP.md) —
  every RTCP message that matters for an SFU (SR, RR, NACK, PLI, FIR,
  REMB, TWCC), the SRTCP wrapper, the SFU rewrite layer, and seven
  hands-on exercises against the code in this repo.

## Cross-reference: Go → Dart

| Go concept (original tutorial) | Dart equivalent in this repo |
|---|---|
| `backend/src/main.go` | [example/ion_style_sfu/bin/sfu_server.dart](../../example/ion_style_sfu/bin/sfu_server.dart) |
| `dtls.Init()` (cert + fingerprint) | [lib/src/dtls/cert_utils.dart](../../lib/src/dtls/cert_utils.dart), [lib/signal/fingerprint.dart](../../lib/signal/fingerprint.dart) |
| `stun.NewStunClient` | [lib/src/stun/stun_server.dart](../../lib/src/stun/stun_server.dart) |
| `udp.NewUdpListener` (demux) | [lib/webrtc/rtc_udp_transport.dart](../../lib/webrtc/rtc_udp_transport.dart) |
| `signaling.NewHttpServer` | [example/ion_style_sfu/lib/src/sfu_server.dart](../../example/ion_style_sfu/lib/src/sfu_server.dart) |
| `conference.NewConferenceManager` | [example/ion_style_sfu/lib/src/sfu.dart](../../example/ion_style_sfu/lib/src/sfu.dart) + [session.dart](../../example/ion_style_sfu/lib/src/session.dart) |
| `agent.NewServerAgent` (ICE) | [lib/src/ice/ice2.dart](../../lib/src/ice/ice2.dart) |
| `dtls/handshake/*` | [lib/src/dtls/handshake/](../../lib/src/dtls/handshake/) |
| SRTP key derivation | [lib/src/srtp/srtp_session.dart](../../lib/src/srtp/srtp_session.dart), [srtp_context.dart](../../lib/src/srtp/srtp_context.dart) |
| RTP/RTCP packet handling | [lib/src/rtp/](../../lib/src/rtp/), [lib/src/rtcp/](../../lib/src/rtcp/) |
| VP8 / VP9 / H.264 helpers | [example/ion_style_sfu/lib/src/vp8.dart](../../example/ion_style_sfu/lib/src/vp8.dart), [vp9.dart](../../example/ion_style_sfu/lib/src/vp9.dart), [h264.dart](../../example/ion_style_sfu/lib/src/h264.dart), [lib/src/codecs/vpx/](../../lib/src/codecs/) |

---

<div align="right">

[&lt;&lt;&nbsp;&nbsp;Original (Go) tutorial](../README.md)&nbsp;&nbsp;|&nbsp;&nbsp;[Next chapter: INFRASTRUCTURE&nbsp;&nbsp;&gt;](./00-INFRASTRUCTURE.md)

</div>
