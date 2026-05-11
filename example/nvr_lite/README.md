# nvr_lite

Mini Network Video Recorder. For each RTSP camera:

- pull H.264 over RTSP (reuses the `rtsp_pure` library from the
  `rtsp_camera_to_webrtc` example),
- write a rolling series of Annex-B `.h264` segments to disk,
- delete segments older than the retention window,
- fan the same stream out to a browser viewer over WebRTC (one tile per
  camera) and expose recordings for download.

```
camera ─RTSP─► RtspClient ─► AuHub ─┬─► segment recorder ─► <storage>/<cam>/<ts>.h264
                                    └─► WebRTC sender    ─► browser tile
```

## Run

```powershell
cd C:\www\dart\dart-webrtc\example\nvr_lite
dart pub get
dart run bin\nvr_lite.dart `
  --ip 192.168.56.1 `
  --storage ./recordings `
  --segment 60 --retain 24 `
  --cam Front=rtsp://admin:pw@192.168.1.50/Streaming/Channels/101 `
  --cam Back=rtsp://admin:pw@192.168.1.51/Streaming/Channels/101
```

Open `http://192.168.56.1:8080/`:

- click **Connect live** to start the WebRTC viewer (one tile per camera),
- expand **recordings** under any tile to download `.h264` segments.

## Flags

| Flag | Default | Meaning |
|---|---|---|
| `--ip`               | `127.0.0.1`  | HTTP + WebRTC ICE bind address |
| `--http-port`        | `8080`       | HTTP / WebSocket port |
| `--rtp-port`         | `50300`      | First UDP port for WebRTC viewers |
| `--storage`          | `./recordings` | Root directory for segments |
| `--segment`          | `60`         | Segment length in seconds |
| `--retain`           | `24`         | Retention window in hours |
| `--profile-level-id` | `42e01f`     | H.264 profile-level-id offered to browser |
| `--cam NAME=URL` (`-c`) | —         | Camera, repeatable |

## Recording format

Each segment is a raw Annex-B H.264 file. Every segment **starts with
SPS + PPS + IDR** so it decodes standalone. Mux to MP4 with:

```powershell
ffmpeg -framerate 30 -i recordings\Front\2026-05-10T18-00-00-000Z.h264 `
  -c copy recordings\Front\2026-05-10T18-00-00.mp4
```

## How segmentation works

1. The recorder subscribes to the camera's `AuHub` and only opens a new
   file on a **keyframe access unit** — guarantees the file is decodable
   from byte 0.
2. The current segment closes when (a) the camera delivers another
   keyframe **and** (b) at least `--segment` seconds have elapsed. If
   the camera's GOP is longer than `--segment`, segments will be longer
   too — that's intentional; truncating mid-GOP would produce
   undecodable files.
3. Every 5 minutes a janitor walks `<storage>/<cam>/` and deletes files
   with `mtime < now - --retain hours`.

## HTTP API

| Method / path | Description |
|---|---|
| `GET /`                  | HTML viewer + recordings index |
| `GET /api/recordings`    | JSON: `{cam: [{name,size,mtime}, ...]}` |
| `GET /recordings/<cam>/<file>.h264` | Download a segment |
| `WS  /ws`                | WebRTC signalling (one PC per browser tab) |

## Limitations

- H.264 only. No audio. No transcoding.
- No index/database — the file system *is* the index.
- No authentication. Put it behind a reverse proxy with auth if you
  expose it outside localhost.
- Browser playback of downloaded `.h264` files requires VLC/mpv/ffplay.
  Mux to MP4 first if you want native browser playback.
