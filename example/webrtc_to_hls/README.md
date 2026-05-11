# webrtc_to_hls

Pull a **WHEP** H.264 stream and republish it as **HLS** (`.m3u8` +
`.ts` segments) over plain HTTP.

```
WHEP source ──RTP H.264──▶ depacketizer ──Access Units──▶
   MPEG-TS muxer ──188B packets──▶ segmenter ──▶ stream.m3u8 + segNNN.ts
                                                    ▲
                              any number of HLS players over HTTP
```

WebRTC scales to ~50 viewers per SFU instance. HLS scales to thousands
behind a CDN with nothing but cached HTTP. This bridge gives you both:
ingest live via WebRTC (low latency, browser/OBS friendly), distribute
via HLS (massive fan-out, every player in existence supports it).

## Run

You need a WHEP source delivering **H.264**. The sibling `whip_server`
example forwards VP8 by default — to use it as a source, change its
`defaultVideoCodecs` to `[H264Codec()]` and feed it from an H.264 WHIP
publisher (OBS Studio's WHIP output, GStreamer's `whipclientsink`, or a
modified `whip_publisher`).

```powershell
cd C:\www\dart\dart-webrtc\example\webrtc_to_hls
dart pub get
dart run bin\webrtc_to_hls.dart `
  --whep http://192.168.56.1:8080/whep `
  --bind-ip 192.168.56.1 `
  --out ./hls --segment 4 --window 6
```

Then play:

```powershell
ffplay http://localhost:9090/stream.m3u8
# or browse to http://localhost:9090/  for the built-in hls.js player
```

Latency is typically `2 × segment` seconds (≈ 8–10 s with the defaults).
Use `--segment 2` for ~4 s glass-to-glass; smaller segments increase
HTTP overhead.

## Flags

| Flag | Default | Meaning |
|---|---|---|
| `--whep`        | *(required)* | WHEP source URL |
| `--token`       | empty        | Bearer token for the WHEP server |
| `--bind-ip`     | `0.0.0.0`    | Local UDP bind for ICE |
| `--announce-ip` | = bind-ip    | Public IP advertised in candidates |
| `--rtp-port`    | `50400`      | Local UDP port for the receiver |
| `--http-port`   | `9090`       | HTTP server for the playlist + segments |
| `--out`         | `./hls`      | Directory for segments + playlist |
| `--segment`     | `4`          | Target segment seconds (rotate on next keyframe ≥ this) |
| `--window`      | `6`          | Live playlist window (segments kept) |

## How it works

1. **WHEP receive.** Build an `RTCPeerConnection` with one `recvonly`
   H.264 transceiver. Wait for ICE gathering, POST the offer to the
   WHEP URL, set the answer.
2. **RTP → AU.** Subscribe to `transceiver.receiver.onRtp`, strip the
   RTP header, push payloads through `H264RtpDepacketizer`, group NALUs
   into Access Units by RTP timestamp / marker bit.
3. **MPEG-TS mux.** A from-scratch single-program TS muxer:
   - PAT (PID 0) + PMT (PID 4096) re-emitted every ~10 PES packets.
   - One PES packet per access unit on PID 256, `stream_type=0x1B` (H.264).
   - PCR (27 MHz) injected on every keyframe packet.
   - Annex-B start codes between NALUs; AUD prefix (NAL 9).
   - 188-byte TS packets with adaptation-field stuffing on the tail
     packet of each PES.
4. **HLS segmenter.** Open a new `.ts` only on a keyframe AU when at
   least `--segment` seconds have elapsed. Cache SPS+PPS so every
   keyframe AU is preceded by them (mid-rollover decoder resync).
5. **Playlist.** Atomic write of `stream.m3u8` after each segment closes
   (write `.tmp` + rename). Sliding window of the last `--window`
   segments; older ones are deleted.

## Limitations

- Video only. (Audio would slot in as a second PID; not implemented.)
- H.264 only. HEVC needs `stream_type=0x24` plus `hvc1` HLS hints.
- Single source → single playlist. No ABR / multi-bitrate.
- Player latency = `~2 × segment` seconds at minimum. For sub-second
  delivery use **LL-HLS** (much more complex playlist structure) or
  stay on plain WebRTC.
- The TS muxer is intentionally minimal (~250 lines): no PSI version
  bumping, no continuity counter recovery on errors, no PCR jitter
  smoothing. Sufficient for VLC / ffplay / hls.js / mpv / Safari.
