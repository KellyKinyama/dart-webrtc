# ion-style SFU example

A re-engineering of [`example/sfu`](../sfu) that adopts the architecture
of [pion/ion-sfu](../ion-sfu): per-peer **Publisher + Subscriber**
PeerConnections, a `Session` abstraction, per-publisher `Router` with
`Receiver` → `DownTrack` wiring, and pluggable subsystems for
NACK/jitter, simulcast layer selection, TWCC/REMB, an audio observer,
SFU-to-SFU relay, and isolate sharding.

This example is built directly on `pure_dart_webrtc`. It shares no code
with `example/sfu`; the two demos are intentionally side-by-side so the
single-PC and split-PC topologies can be compared.

## Status: phased delivery

This codebase is shipped in phases. Phase 1 establishes the
architecture; subsequent phases fill in the heavy machinery without
disturbing the public API.

| Phase | Scope | State |
|------|-------|-------|
| **1** | Scaffold, Pub/Sub split PCs, Session, Router, Receiver, DownTrack, WS+JSON signaling, two-PC web client | **Done** |
| 2 | Per-receiver jitter buffer + NACK responder ([`lib/buffer/`](lib/buffer/)) | Stub |
| 3 | Simulcast layer selection (q/h/f) + auto PLI on switch ([`lib/simulcast.dart`](lib/simulcast.dart)) | Stub |
| 4 | Audio observer (RFC 6464) ([`lib/audio_observer.dart`](lib/audio_observer.dart)) | Stub |
| 5 | TWCC + REMB + SR/RR ([`lib/twcc/`](lib/twcc/)) | Stub |
| 6 | SFU-to-SFU relay ([`lib/relay/`](lib/relay/)) | Stub |
| 7 | Stats package + `/metrics` ([`lib/stats/`](lib/stats/)) | Stub (basic counters wired) |
| 8 | Isolate sharding (room workers), HTTP discovery (`/room/:id/locate`) | Not started |

Each stub file documents the API it intends to expose so the wiring
points are visible from day one.

## Architectural mapping

| ion-sfu (Go) | this example (Dart) |
|---|---|
| `pkg/sfu/sfu.go` `SFU` | [`lib/sfu.dart`](lib/sfu.dart) `Sfu` |
| `pkg/sfu/session.go` `SessionLocal` | [`lib/session.dart`](lib/session.dart) `Session` |
| `pkg/sfu/peer.go` `PeerLocal` | [`lib/peer.dart`](lib/peer.dart) `Peer` |
| `pkg/sfu/publisher.go` `Publisher` | [`lib/publisher.dart`](lib/publisher.dart) `Publisher` |
| `pkg/sfu/subscriber.go` `Subscriber` | [`lib/subscriber.dart`](lib/subscriber.dart) `Subscriber` |
| `pkg/sfu/router.go` `Router` | [`lib/router.dart`](lib/router.dart) `Router` |
| `pkg/sfu/receiver.go` `Receiver` | [`lib/receiver.dart`](lib/receiver.dart) `Receiver` |
| `pkg/sfu/downtrack.go` `DownTrack` | [`lib/down_track.dart`](lib/down_track.dart) `DownTrack` |
| `pkg/sfu/audioobserver.go` | [`lib/audio_observer.dart`](lib/audio_observer.dart) (stub) |
| `pkg/buffer/` | [`lib/buffer/`](lib/buffer/) (stub) |
| `pkg/twcc/` | [`lib/twcc/`](lib/twcc/) (stub) |
| `pkg/relay/` | [`lib/relay/`](lib/relay/) (stub) |
| `pkg/stats/` | [`lib/stats/`](lib/stats/) |
| `cmd/signal/json-rpc` | [`bin/sfu_server.dart`](bin/sfu_server.dart) (WS+JSON) |

## Pub/Sub split signaling

Unlike `example/sfu` (one PC per participant), every peer here owns two
PeerConnections. The signaling protocol carries explicit `target`
fields so the client and server can address each one independently.

```
client                                    server
  │                                          │
  │  {type:"join", sid, uid}                 │
  │ ───────────────────────────────────────► │
  │                                          │
  │  PUBLISHER PC (client → server)          │
  │  {type:"offer",  target:"pub", sdp}      │
  │ ───────────────────────────────────────► │
  │  {type:"answer", target:"pub", sdp}      │
  │ ◄─────────────────────────────────────── │
  │                                          │
  │  SUBSCRIBER PC (server → client)         │
  │  {type:"offer",  target:"sub", sdp}      │
  │ ◄─────────────────────────────────────── │
  │  {type:"answer", target:"sub", sdp}      │
  │ ───────────────────────────────────────► │
  │                                          │
  │  ICE for either PC:                      │
  │  {type:"trickle", target:"pub|sub", ...} │
  │ ◄────────────────────────────────────►   │
  │                                          │
  │  (when a peer publishes, server          │
  │   re-offers the subscriber PC)           │
  │  {type:"offer",  target:"sub", sdp}      │
  │ ◄─────────────────────────────────────── │
```

`target: "pub"` is the client's publisher PC (the one carrying its
camera/mic up to the server). `target: "sub"` is the server's
subscriber PC pushing remote tracks down to the client.

## Run

```powershell
cd example\ion_style_sfu
dart pub get
dart run bin\sfu_server.dart --ip 0.0.0.0 --ws-port 9090 --rtp-base 51000
```

Open [`web/index.html`](web/index.html) in a browser pointed at the
server's WebSocket (`ws://<host>:9090/ws/<sessionId>`).

## What this Phase 1 does NOT yet do

- No SSRC / sequence-number / timestamp rewrite on `DownTrack` — the
  publisher's original SSRCs are advertised verbatim in the
  subscriber-PC SDP. (Phase 2 introduces a `SsrcAllocator`.)
- No NACK / RTX / jitter buffer.
- No simulcast layer selection.
- No congestion control.
- No multi-isolate sharding.
- No auth / rate limiting.

These are tracked above and wired into stubs so the public API doesn't
shift when they land.

## Tests

```powershell
dart test
```

(Tests will land alongside each subsystem as it ships out of stub.)
