# **0. INFRASTRUCTURE**

The Go original ran two Docker containers (`webrtcnb-ui` and
`webrtcnb-backend`). The Dart port is deliberately leaner: there is no
custom UI container — the browser talks to the SFU directly over a
WebSocket — and the server is a single Dart process that you can run
either bare-metal, inside a container, or under VS Code's debugger.

This chapter describes the runtime pieces that have to exist before a
single packet flows.

## **0.1. Runtime requirements**

The SFU is **pure Dart** (no platform plugins, no `dart:ffi` is
required for the signalling/transport path). You need:

* The Dart SDK (3.4+ recommended). See [pubspec.yaml](../../pubspec.yaml)
  for the exact constraint of the root package and
  [example/ion_style_sfu/pubspec.yaml](../../example/ion_style_sfu/pubspec.yaml)
  for the SFU.
* A modern browser (Chrome / Edge / Firefox) for the client side.
* Optional: `libvpx` available on `PATH` if you want to run the
  side-tools in [bin/vpx_*.dart](../../bin/) that decode/encode
  raw frames through the FFI bindings in
  [lib/src/codecs/vpx/](../../lib/src/codecs/vpx/) — these are **not**
  required for the SFU itself, which forwards opaque RTP.

There is no Docker compose file in this repo; the deployment story is
"`dart run`". A minimal Dockerfile would be a single
`FROM dart:stable` layer that copies the workspace and runs the SFU
binary — see chapter 1 for the command.

## **0.2. Source-tree layout**

```text
dart-webrtc/
├─ lib/
│  ├─ dart_webrtc.dart              ← public barrel for the core lib
│  ├─ signal/                       ← SDP v2 parser/builder, fingerprint
│  ├─ webrtc/                       ← RTCPeerConnection, RtcUdpTransport
│  └─ src/
│     ├─ stun/                      ← STUN message codec
│     ├─ dtls/                      ← DTLS 1.2 handshake state machine
│     ├─ ice/                       ← ICE agent (host + srflx + prflx)
│     ├─ srtp/                      ← SRTP / SRTCP cipher contexts
│     ├─ rtp/, rtp2/                ← RTP header + packet helpers
│     ├─ rtcp/                      ← SR / RR / NACK / PLI / TWCC / REMB
│     └─ codecs/                    ← VP8/VP9 (libvpx FFI), H.264, G.711
├─ bin/                             ← single-purpose demos
│  ├─ dart_webrtc.dart              ← bare DTLS server smoke test
│  ├─ srtp_webrtc2.dart             ← DTLS+SRTP echo server
│  ├─ srtp_client.dart              ← DTLS client + SRTP VP8 sender
│  └─ vpx_*.dart                    ← libvpx encode/decode CLIs
└─ example/
   ├─ ion_style_sfu/                ← FULL SFU — the focus of this tutorial
   ├─ play_from_disk/               ← play a file as a WebRTC track
   ├─ whip_publisher/  whip_server/ ← WHIP ingest
   ├─ rtsp_to_webrtc/               ← RTSP → WebRTC bridge
   └─ flutter_camera/               ← Flutter UI sample
```

The two pieces that matter most for this tutorial are
**[lib/](../../lib/)** (the protocol primitives) and
**[example/ion_style_sfu/](../../example/ion_style_sfu/)** (the SFU
that wires those primitives into a working server).

## **0.3. The SFU package**

[example/ion_style_sfu/](../../example/ion_style_sfu/) is a regular Dart
package with its own `pubspec.yaml`. It depends on the parent
`pure_dart_webrtc` package by `path:` so the tutorial chapters can
freely cross-reference the two trees.

The interesting subdirectories of the SFU are:

```text
example/ion_style_sfu/
├─ bin/
│  ├─ sfu_server.dart        ← CLI entry point (parses flags, calls runIonStyleSfuServer)
│  └─ load_test.dart         ← stress harness
└─ lib/src/
   ├─ sfu.dart               ← top-level engine (room registry)
   ├─ session.dart           ← room
   ├─ peer.dart              ← (publisher PC, subscriber PC) pair
   ├─ publisher.dart         ← inbound PeerConnection
   ├─ subscriber.dart        ← outbound PeerConnection
   ├─ router.dart            ← per-publisher fan-out hub
   ├─ receiver.dart          ← one inbound track + downtrack list
   ├─ down_track.dart        ← rewritten outbound stream per subscriber
   ├─ rtp_header.dart        ← RTP byte helpers used by the SFU
   ├─ rtcp.dart              ← NACK / PLI / REMB rewrite layer
   ├─ vp8.dart  vp9.dart  h264.dart   ← codec-specific keyframe gating
   ├─ twcc/                  ← transport-wide congestion control
   ├─ pacer/                 ← outbound bitrate pacer
   └─ buffer/                ← jitter buffer, NACK list
```

## **0.4. Ports**

By default the SFU opens:

| Port    | Proto | Purpose                                              |
|---------|-------|------------------------------------------------------|
| `9090`  | TCP   | HTTP + WebSocket signalling (SDP offer/answer)       |
| `51000` | UDP   | First media transport; subsequent peers get +1, +2…  |

Both are configurable via CLI flags
(`--ws-port`, `--rtp-base`) parsed in
[example/ion_style_sfu/bin/sfu_server.dart](../../example/ion_style_sfu/bin/sfu_server.dart).

Unlike the Go original (which used a single fixed UDP port for *all*
peers and demultiplexed by ICE ufrag), the Dart SFU allocates **one
UDP socket per peer-connection** through
[`RtcUdpTransport`](../../lib/webrtc/rtc_udp_transport.dart). That
keeps NAT punching simple at the cost of consuming one ephemeral UDP
port per active publisher/subscriber.

## **0.5. Sanity check**

You're ready for the next chapter when the following two commands
both exit zero:

```pwsh
dart pub get
cd example/ion_style_sfu
dart pub get
dart analyze
```

A clean `dart analyze` against the SFU example is the green light.

---

<div align="right">

[&lt;&nbsp;&nbsp;Documentation Index](./README.md)&nbsp;&nbsp;|&nbsp;&nbsp;[Next chapter: RUNNING IN DEVELOPMENT MODE&nbsp;&nbsp;&gt;](./01-RUNNING-IN-DEV-MODE.md)

</div>
