# rtsp_camera_to_webrtc

Bridge live RTSP H.264 cameras to a browser via WebRTC — **pure Dart, no
native dependencies**. Uses `pure_dart_webrtc` for the WebRTC side and a
built-in RTSP/1.0 client for the camera side.

H.264 is forwarded end-to-end with **zero transcoding**. The browser
receives the camera's exact NAL units, just re-packetized into WebRTC
SRTP.

## Binaries

| Binary | Cameras | Use when |
|---|---|---|
| [bin/multicam_pure_to_webrtc.dart](bin/multicam_pure_to_webrtc.dart) | N | You want a grid of cameras in one tab |
| [bin/rtsp_camera_to_webrtc.dart](bin/rtsp_camera_to_webrtc.dart)     | 1 | One camera, simplest setup |

---

## Prerequisites

- Dart SDK ≥ 3.6.2
- Network reachability from this PC to the camera on TCP/554
- An H.264 RTSP camera (most IP cameras: Hikvision, Dahua, Axis, Reolink,
  Amcrest, generic ONVIF)

### Verify reachability *first*

A vast majority of "it doesn't work" reports are network-routing issues,
not code bugs. Always check this before debugging Dart:

```powershell
Test-NetConnection 192.168.1.50 -Port 554
# TcpTestSucceeded : True   <-- you want this
```

If `TcpTestSucceeded : False`, you have a routing/firewall problem
(often: PC bound to a different subnet such as `192.168.56.x` from
VirtualBox/WSL, while the camera is on `192.168.1.x` with no route
between them). Fix the network first; the Dart code cannot help.

---

## Camera URL cheat-sheet

| Vendor    | Typical main-stream URL                                                       |
|-----------|-------------------------------------------------------------------------------|
| Hikvision | `rtsp://user:pw@HOST:554/Streaming/Channels/101`                              |
| Dahua     | `rtsp://user:pw@HOST:554/cam/realmonitor?channel=1&subtype=0`                 |
| Axis      | `rtsp://user:pw@HOST:554/axis-media/media.amp`                                |
| Reolink   | `rtsp://user:pw@HOST:554/h264Preview_01_main`                                 |
| Amcrest   | `rtsp://user:pw@HOST:554/cam/realmonitor?channel=1&subtype=0`                 |
| ONVIF     | URL exposed by the device's ONVIF Media service (use ONVIF Device Manager)    |

Use `subtype=1` / `Channels/102` / `h264Preview_01_sub` to request the
sub-stream (lower resolution, lighter load).

---

## Install

```powershell
cd C:\www\dart\dart-webrtc\example\rtsp_camera_to_webrtc
dart pub get
```

---

## Multi-camera viewer

```powershell
dart run bin\multicam_pure_to_webrtc.dart `
  --ip 192.168.56.1 `
  --cam Front=rtsp://admin:pw@192.168.1.50/Streaming/Channels/101 `
  --cam Back=rtsp://admin:pw@192.168.1.51/Streaming/Channels/101 `
  --cam Side=rtsp://admin:pw@192.168.1.52/Streaming/Channels/101
```

Then open `http://192.168.56.1:8080/` in a browser and click **Connect**.
You will see one `<video>` tile per camera.

### Flags

| Flag | Default | Meaning |
|---|---|---|
| `--ip`               | `127.0.0.1` | Address the HTTP server **and** WebRTC ICE candidate bind to. Use the LAN IP your browser will reach. |
| `--http-port`        | `8080`      | HTTP / WebSocket signalling port |
| `--rtp-port`         | `50000`     | First UDP port for WebRTC; each viewer takes the next one |
| `--profile-level-id` | `42e01f`    | H.264 profile-level-id offered to the browser (Constrained Baseline 3.1) |
| `--cam NAME=URL` (`-c`) | —        | Add a camera. Repeat for more. The NAME shows up as the tile label. |

You can also pass URLs as bare positional arguments — they get auto-named
`cam0`, `cam1`, …:

```powershell
dart run bin\multicam_pure_to_webrtc.dart --ip 192.168.56.1 `
  rtsp://.../1 rtsp://.../2
```

### What it does

1. Spawns one `RtspClient` per camera, each with its own `AuHub`
   broadcast bus and a 3-second reconnect back-off (`runForever`).
2. Each `RtspClient` does `OPTIONS → DESCRIBE → SETUP → PLAY` over a
   single TCP connection (RFC 7826 §14 interleaved transport,
   `RTP/AVP/TCP;interleaved=0-1`), supports Basic + Digest auth, and
   sends `GET_PARAMETER` every 30 s as keepalive.
3. RTP H.264 (RFC 6184: Single-NAL, FU-A, STAP-A) is depacketized and
   reassembled into Access Units.
4. For each browser viewer, one `RTCPeerConnection` is created with N
   sendonly H.264 transceivers — one per camera — each carrying its own
   SSRC + msid so the browser fires `ontrack` once per camera and
   `e.streams[0].id` matches the tile name.
5. Per-viewer fan-out: each `AuHub` `subscribe()` immediately replays
   the latest cached SPS/PPS + keyframe so the browser decoder syncs
   without waiting for the next IDR.

---

## Single-camera viewer

```powershell
dart run bin\rtsp_camera_to_webrtc.dart `
  --ip 192.168.56.1 `
  rtsp://admin:password@192.168.1.50/Streaming/Channels/101
```

Same flags as above except no `--cam`; the camera URL is positional.

---

## Architecture

```
camera ─ RTSP/TCP ─► RtspClient ─► AuHub ─► subscribe() ─► H264 RTP
   (one per camera)                              (one per browser viewer)
                                                          │
                                                          ▼
                                                    RTCPeerConnection
                                                          │
                                                          ▼
                                                       browser
```

Reusable pieces live in [lib/rtsp_pure.dart](lib/rtsp_pure.dart):

- `AccessUnit`           — H.264 access unit (list of NALUs + IDR flag)
- `AuHub`                — broadcast bus, caches SPS/PPS + last keyframe
- `RtspClient`           — RTSP/1.0 over interleaved TCP, Basic/Digest auth

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `OS Error: A connection attempt failed ... 121` ("semaphore timeout") | Camera unreachable on TCP/554 | `Test-NetConnection`. Fix routing/firewall/subnet. |
| `Connection refused` | Wrong port or RTSP disabled on camera | Enable RTSP in the camera's web UI; confirm port. |
| `DESCRIBE failed: 401` after retry | Wrong username/password or unsupported auth | Re-check creds in the URL (URL-encode special chars). |
| `DESCRIBE failed: 404` | Wrong stream path | See the URL cheat-sheet above for your vendor. |
| Browser shows tiles but they stay black | DTLS not connected, or H.264 profile mismatch | Watch the server log for `DTLS connected`; try `--profile-level-id 42001f`. |
| One camera dies, others stop | Should not happen — each camera has its own client | File a bug with the `[<camName>]`-tagged log lines. |
| Browser `ontrack` fires but no video, others fine | That camera is not delivering an IDR | Ask the camera to send IDR (Hikvision: lower GOP; Dahua: enable I-frame interval ≤ 2s). |

---

## Limitations

- H.264 only. (No H.265, no audio.)
- Synthetic 30 fps timestamps are emitted to the browser. RTCP-SR-based
  wall-clock sync is not implemented — fine for live viewing, not for
  precise A/V sync.
- One-way (camera → browser). No PTZ, no two-way audio, no recording.
- Each viewer gets its own re-packetization; CPU scales linearly with
  `viewers × cameras`.
