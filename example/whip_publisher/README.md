# whip_publisher

A pure-Dart **WHIP** ([RFC 9725 — WebRTC-HTTP Ingestion Protocol](https://datatracker.ietf.org/doc/html/rfc9725))
publisher. Reads a VP8 `.ivf` file and pushes it to any WHIP-compatible
ingest server using only HTTP + WebRTC.

## What is WHIP?

WHIP is the IETF-standard way to **publish** a live stream into a WebRTC
server using nothing but plain HTTP signalling. No WebSocket, no custom
protocol, no SDK.

The full protocol is essentially three HTTP verbs:

```
POST   /whip/endpoint    Content-Type: application/sdp
                         Authorization: Bearer <token>
                         <SDP offer with ICE candidates>

       201 Created
       Location: /whip/resource/abc123
       Content-Type: application/sdp
       <SDP answer>

PATCH  /whip/resource/abc123    (optional — trickle ICE)

DELETE /whip/resource/abc123    (tear down)
```

That's it. Once the answer is exchanged, normal WebRTC media flows.

### Why it matters

Before WHIP, every WebRTC server (Janus, Jitsi, mediasoup, …) had its own
custom signalling protocol. Pushing a single live stream from OBS, a
hardware encoder, or a Dart program required an SDK per server. WHIP
made publishing **interchangeable**:

| Publisher                    | Server                  |
|------------------------------|-------------------------|
| OBS Studio (built-in)        | Cloudflare Stream Live  |
| GStreamer `whipsink`         | Broadcast Box           |
| Larix (mobile)               | OvenMediaEngine         |
| **this Dart example**        | **any WHIP server**     |

WHEP (RFC 9725's twin) is the same idea for **playback**.

### Use cases

- Push a Dart-managed camera/file to a public CDN that fans out to
  thousands of viewers (Cloudflare, Mux, Daily, etc.).
- Bridge a non-WebRTC source (RTSP camera, file, generated content) into
  a WebRTC-native conferencing server.
- Build a CLI / headless ingester that survives restarts of the server
  side without rewriting signalling code.

## Run

You need a WHIP server. Easiest local option:

```powershell
docker run --rm --network host -e UDP_MUX_PORT=4001 -e NAT_1_TO_1_IP=127.0.0.1 `
  seaduboi/broadcast-box
```

Then from this folder:

```powershell
cd C:\www\dart\dart-webrtc\example\whip_publisher
dart pub get

dart run bin\whip_publisher.dart `
  --url   http://localhost/api/whip `
  --token streamkey-anything `
  --file  ..\..\example.ivf
```

Open the Broadcast Box web UI (`http://localhost`), enter the same
stream key, and you should see the looping video.

### Cloudflare Stream Live

```powershell
dart run bin\whip_publisher.dart `
  --url   "https://customer-<id>.cloudflarestream.com/<input-id>/webRTC/publish" `
  --file  ..\..\example.ivf
```

(Cloudflare doesn't need a bearer token — the secret is in the URL.)

## Flags

| Flag | Default | Meaning |
|---|---|---|
| `--url`         | *(required)* | WHIP endpoint to POST to |
| `--token`       | empty | Bearer token, if the server requires one |
| `--file`        | `../../example.ivf` | VP8 IVF source file |
| `--bind-ip`     | `0.0.0.0` | Local UDP bind for ICE |
| `--announce-ip` | = bind-ip | Public IP to advertise in `a=candidate` |
| `--rtp-port`    | `50100` | Local UDP port |
| `--loop` / `--no-loop` | on | Restart file at EOF |

## How it works

1. Open the IVF file (`IvfReader` from `package:pure_dart_webrtc/vpx.dart`).
2. Build a `RTCPeerConnection` with one **sendonly** VP8 video transceiver.
3. `createOffer` + `setLocalDescription`, then **wait for ICE gathering**
   (3 s timeout). WHIP servers historically don't speak trickle, so we
   inject all `a=candidate:` lines into the offer before sending.
4. `POST` the offer SDP. Read `Location:` and the answer SDP from the
   201 response. `setRemoteDescription(answer)`.
5. Once `RTCPeerConnectionState.connected`, packetize each VP8 frame
   with `packetizeVp8Frame` (RFC 7741) and send via the transceiver's
   sender, paced at the file's frame rate.
6. On Ctrl-C, `DELETE` the resource so the server tears down cleanly.

## Limitations

- VP8 only in this example (the library also supports VP9 and H.264 —
  swap the codec list and packetizer).
- No trickle ICE PATCH; offer is sent after gathering completes.
- Audio not implemented (Opus would slot in symmetrically).
- No bandwidth estimation / sender-side adaptation — frames go out at
  their file-encoded rate.
