# Basic SFU example

A minimal Selective Forwarding Unit (SFU) for multi-party video conferencing,
built on the [`pure_dart_webrtc`](../../) `RTCPeerConnection` API.

Each participant gets their own `RTCPeerConnection` bound to its own UDP port.
The SFU does no transcoding — it just decrypts inbound RTP/RTCP from one
participant and re-encrypts it for every other participant.

## Run

```powershell
cd example\sfu
dart pub get
dart run bin\sfu_server.dart --ip 0.0.0.0 --ws-port 8080 --rtp-base 50000
```

Browsers connect to `ws://<host>:8080/ws`.

## Wire protocol (JSON over WebSocket)

| Direction | Message |
|-----------|---------|
| client → server | `{"type":"join","id":"alice","name":"Alice"}` |
| server → client | `{"type":"offer","sdp":"..."}` |
| client → server | `{"type":"answer","sdp":"..."}` |
| both directions | `{"type":"candidate","candidate":"...","sdpMid":"0","sdpMLineIndex":0}` |
| client → server | `{"type":"leave"}` |
| server → broadcast | `{"type":"peer-joined","id":"...","name":"..."}` |
| server → broadcast | `{"type":"peer-left","id":"..."}` |

## Library API

```dart
import 'package:pure_dart_webrtc_sfu_example/basic_sfu.dart';

final sfu = BasicSfu(address: InternetAddress.anyIPv4, basePort: 50000);
sfu.onParticipantConnected = (p) => print('${p.id} connected');

final alice = await sfu.addParticipant('alice');
final offer = await alice.pc.createOffer();
await alice.pc.setLocalDescription(offer);
// ... ship offer.sdp through your signaling channel ...
await alice.pc.setRemoteDescription(remoteAnswer);
```

## What this SFU does NOT do

- Simulcast / SVC layer selection (forwards every packet as-is)
- RTCP rewriting (NACK, PLI, REMB are forwarded blindly)
- SSRC remapping — every receiver sees the original sender SSRC
- Bandwidth estimation
- Authentication
- TURN fallback for symmetric NAT clients

It exists to demonstrate how the `RTCPeerConnection` + `RtcUdpTransport`
APIs compose into a real conferencing topology.

## Scaling one big room

See [SCALING.md](SCALING.md) for the architecture notes covering the
hot-path optimizations the SFU uses to push more participants through a
single isolate:

- Parallel SRTP fan-out via `Future.wait` over a snapshot of receivers.
- Cached top-K active-speaker set (recomputed on a timer rather than
  per-packet sort).
- Optional top-K *video* forwarding via `maxVideoForwarded`, mirroring
  `maxAudioForwarded`. Only the loudest speakers' video is forwarded;
  newly-active speakers automatically receive a PLI on switch.
- Coalesced join-time PLI bursts: a flock of joiners costs one PLI per
  producer instead of one per (producer × newcomer).

## Scaling many rooms

See [MULTI_ROOM_ARCHITECTURE.md](MULTI_ROOM_ARCHITECTURE.md) for the
worker-pool design that shards rooms across N isolates:

```powershell
dart run bin\multi_room_server.dart --workers 4 --max-participants-per-room 25
```

Clients first hit `GET /room/<id>/locate` to discover which worker
owns a room, then open `ws://host:<workerPort>/ws/<id>` directly. RTP
never crosses an isolate boundary.

## Tests

```powershell
dart test
```
