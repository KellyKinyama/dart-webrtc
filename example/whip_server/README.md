# whip_server

Minimal pure-Dart **WHIP ingest + WHEP playback** server.

- **WHIP** (RFC 9725) — clients (OBS, `whip_publisher`, GStreamer
  `whipsink`, …) push a stream by `POST`ing an SDP offer.
- **WHEP** (RFC 9725) — clients pull a stream the same way: `POST` an
  offer, get an answer, watch.

One publisher, N viewers. The publisher's RTP packets are forwarded to
every viewer's sender, with the SSRC field rewritten so the browser
matches the answer's `a=ssrc:` line.

```
publisher ──POST /whip──► server ──forward RTP──► viewer N ──pulls via POST /whep──► browser
                            ▲                                                          │
                            └── DELETE /resource/<id> ─────────────────────────────────┘
```

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| `POST`   | `/whip`             | Publisher offer in, answer out, `Location:` returned |
| `POST`   | `/whep`             | Viewer offer in, answer out, `Location:` returned |
| `DELETE` | `/resource/<id>`    | Tear down a publisher or viewer session |
| `GET`    | `/`                 | Built-in HTML WHEP player (handy for smoke testing) |

CORS is enabled for all origins so a browser can `fetch('/whep', ...)`.

## Run

```powershell
cd C:\www\dart\dart-webrtc\example\whip_server
dart pub get
dart run bin\whip_server.dart --ip 192.168.56.1
```

In another terminal, push the bundled VP8 sample with the sibling
`whip_publisher`:

```powershell
cd C:\www\dart\dart-webrtc\example\whip_publisher
dart run bin\whip_publisher.dart `
  --url http://192.168.56.1:8080/whip `
  --file ..\..\example.ivf
```

Open `http://192.168.56.1:8080/` in any browser and click **Play**.

You can also push from **OBS Studio 30+**:

- Settings → Stream → Service: **WHIP**
- Server: `http://192.168.56.1:8080/whip`
- Bearer token: leave blank

…or from **GStreamer**:

```bash
gst-launch-1.0 videotestsrc ! videoconvert ! vp8enc deadline=1 ! \
  rtpvp8pay ! whipclientsink signaller::whip-endpoint="http://192.168.56.1:8080/whip"
```

## Flags

| Flag | Default | Meaning |
|---|---|---|
| `--ip`         | `127.0.0.1` | HTTP bind + WebRTC ICE candidate address |
| `--http-port`  | `8080`      | HTTP port |
| `--rtp-port`   | `50200`     | First UDP port; each PC takes the next one |

## Limitations

- VP8 only. (The forwarder is codec-agnostic — extend `defaultVideoCodecs`
  to add VP9 / H.264.)
- One publisher at a time. A second `POST /whip` replaces the first.
- No audio.
- No authentication. Add a `Bearer` check in `_onWhip` / `_onWhep` if
  you expose this anywhere outside localhost.
- No trickle ICE. Both sides gather fully before the SDP answer is
  returned (3 s timeout). Most production WHIP/WHEP clients work this
  way already.
- No retransmission / NACK / PLI handling. If the publisher drops a
  frame, the viewer just sees a glitch.

## See also

- [whip_publisher](../whip_publisher/) — Dart WHIP publisher (pushes a
  VP8 file to any WHIP server, including this one).
