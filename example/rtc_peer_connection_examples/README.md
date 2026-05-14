# RTCPeerConnection — server-side examples

Four self-contained examples that demonstrate how to drive
`RTCPeerConnection` from pure Dart on the **server side**, using the
browser-shaped API exported by
[`package:pure_dart_webrtc/webrtc/webrtc.dart`](../../lib/webrtc/webrtc.dart).

Each example is a single file under [bin/](bin) and is intended to be
read top-to-bottom in order.

| # | File | What it shows |
|---|------|---------------|
| 01 | [bin/ex01_minimal_offer.dart](bin/ex01_minimal_offer.dart) | Build a `PeerConnection`, add transceivers, generate an offer SDP. No socket, no peer. |
| 02 | [bin/ex02_loopback_offer_answer.dart](bin/ex02_loopback_offer_answer.dart) | Two PCs in the same process complete the full SDP offer/answer (loopback). |
| 03 | [bin/ex03_server_offers_to_browser.dart](bin/ex03_server_offers_to_browser.dart) | Server creates the offer, browser answers (sendonly server). |
| 04 | [bin/ex04_server_answers_browser.dart](bin/ex04_server_answers_browser.dart) | Browser publishes (camera + mic), server answers as recvonly and prints inbound RTP stats. |

## Setup

```powershell
cd example/rtc_peer_connection_examples
dart pub get
```

## 01 — Minimal offer

Smallest possible API call sequence. Useful as a smoke test.

```powershell
dart run bin/ex01_minimal_offer.dart
```

You should see a complete SDP printed to stdout, ending with
`signalingState=haveLocalOffer`.

The four lines that matter:

```dart
final pc = RTCPeerConnection(RTCConfiguration(
  defaultVideoCodecs: [Vp8Codec()],
  defaultAudioCodecs: [PcmuCodec()],
));
pc.addTransceiver(trackOrKind: MediaKind.video);
pc.addTransceiver(trackOrKind: MediaKind.audio);
final offer = await pc.createOffer();
await pc.setLocalDescription(offer);
```

## 02 — Loopback offer/answer (server ↔ server)

Two `RTCPeerConnection`s in the same Dart process, bound to
`127.0.0.1:51000` and `127.0.0.1:51001`, complete the full SDP
offer/answer exchange against each other.

```powershell
dart run bin/ex02_loopback_offer_answer.dart
```

Expected output (abridged):

```
[offerer]  candidate candidate:1 1 udp ... 127.0.0.1 51000 typ host
[answerer] candidate candidate:1 1 udp ... 127.0.0.1 51001 typ host
[offerer]  signaling=haveLocalOffer
[answerer] signaling=haveRemoteOffer
[answerer] signaling=stable
[offerer]  signaling=stable
[offerer]  ice=checking
[loopback] negotiation complete.
  offerer:  signaling=stable ice=checking conn=connecting
  answerer: signaling=stable ice=newState conn=newState
  offerer transceivers: video:sendrecv, audio:sendrecv
```

> **Note.** Server ↔ server media is **not yet wired up** in this
> library. `RTCPeerConnection.bind()` listens for incoming STUN
> binding requests but does not actively send them, so two servers
> facing each other reach `iceConnectionState=checking` and stop
> there. To complete DTLS you need a real ICE *controller* on at
> least one side — typically a browser (examples 03 / 04). Use this
> example as a copy/paste template for the SDP exchange itself.

## 03 — Server offers, browser answers

The Dart process creates the offer and pushes it down a WebSocket; the
browser answers. This is the "play-from-disk" / "IVR / bot calls in"
shape.

```powershell
# Pick your LAN IPv4 (e.g. ipconfig | Select-String IPv4).
dart run bin/ex03_server_offers_to_browser.dart --ip 192.168.1.42
```

Then open `http://192.168.1.42:8080/` and click **Connect**. The
browser console should show `ice connected` / `conn connected`. The
example does not pump any media — see
[`example/play_from_disk`](../play_from_disk) for a version that adds a
VP8 RTP pump on top of this skeleton.

Flags:

| Flag | Default | Purpose |
|------|---------|---------|
| `--ip` | `127.0.0.1` | Address advertised in ICE candidates (use your LAN IPv4). |
| `--http-port` | `8080` | HTTP/WS port. |
| `--rtp-base` | `52000` | First UDP port; each new tab gets `rtp-base + N`. |

## 04 — Browser publishes, server answers (WHIP-shaped)

The browser captures camera + mic, creates the offer, and the Dart
server answers as a `recvonly` sink. Every 2 s the server prints an
inbound RTP stats snapshot so you can confirm packets are arriving.

```powershell
dart run bin/ex04_server_answers_browser.dart --ip 192.168.1.42
```

Open `http://192.168.1.42:8081/`, click **Publish**, accept the camera
prompt. Server log will look like:

```
[srv:53000] conn=connecting
[srv:53000] conn=connected
[srv:53000] ontrack kind=video
[srv:53000] ontrack kind=audio
[srv:53000] inbound packets=147 bytes=132450
[srv:53000] inbound packets=304 bytes=275110
```

This is the minimum useful WHIP ingest — see
[`example/whip_server`](../whip_server) for one that adds the actual
HTTP WHIP endpoint and authentication.

## Operational notes

- **127.0.0.1 vs LAN IP on Windows + Chrome.** Chrome does not
  reliably pick the loopback adapter for ICE, even when both browser
  and server are on the same machine. For browser examples (03, 04),
  always pass `--ip <your-LAN-IPv4>`. Loopback works fine for
  server ↔ server (example 02).
- **One UDP port per peer.** `RTCPeerConnection.bind()` claims one
  socket per call. The browser examples allocate `rtp-base + N` for
  each new WebSocket client — open a firewall hole if needed.
- **Codecs.** The defaults baked into these examples are `Vp8Codec()`
  for video and `PcmuCodec()` for audio. Swap in `Vp9Codec()`,
  `H264Codec()`, or `PcmaCodec()` as needed; that's the entire codec
  surface today (no Opus / AV1).
- **No trickle ICE.** `bind()` emits exactly one `host` candidate and
  inlines it into the SDP, so you do not strictly need to relay
  candidates over the WebSocket — examples 03/04 do it anyway because
  real browsers expect to be able to send theirs.

## See also

- [`lib/webrtc/peer_connection.dart`](../../lib/webrtc/peer_connection.dart) — the `RTCPeerConnection` source, the canonical reference for the API surface.
- [`example/play_from_disk`](../play_from_disk) — full media pump on top of the example-03 skeleton.
- [`example/whip_publisher`](../whip_publisher) and [`example/whip_server`](../whip_server) — WHIP variants of example 04.
- [`example/ion_style_sfu`](../ion_style_sfu) — full SFU built on the same primitives.
