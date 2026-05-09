# Live browser interop — repro recipe

The pure_dart_webrtc SFU has been hardened in isolation (45 unit + integration
tests). This document is the procedure for actually exercising it against
real browsers (Chrome, Firefox, Safari) and capturing enough state to fix
whatever breaks.

## Known limitations *before* you start

These are confirmed by code inspection — no need to re-discover:

1. **Audio codec is PCMU only.** No `OpusCodec` exists in
   `lib/signal/sdp/sdp_codec.dart`. Browsers offer Opus first; the SFU
   answers PCMU. Chrome accepts this but audio quality will be poor and
   bandwidth will be high (~64 kbps mono). Firefox should also accept.
   This is by design for now — Opus support is its own milestone.

2. **Video codec is VP8 only.** No VP9/H264/AV1. Modern Chrome offers
   VP8 in its codec list, so this should negotiate.

3. **One m-section per kind** (one audio, one video). The SFU does *not*
   yet do "m-section-per-producer" — multiple remote producers are
   multiplexed onto the same m-line via SSRC rewriting. Browsers should
   render each remote SSRC as a separate `MediaStreamTrack` via `ontrack`
   firing once per inbound SSRC.

4. **No DataChannel.** If a browser offers `m=application` (SCTP), the
   SFU's answer-builder does not generate a matching m-line. Browser will
   probably reject the answer with a "different number of m-lines" error.
   Workaround: don't add a DataChannel in the demo (the bundled
   `demoHtml` already avoids this).

5. **ICE-Lite responder only.** SFU advertises one host candidate
   (the address it bound to). If you bind to `0.0.0.0`, the browser
   sees `0.0.0.0` as a candidate which is not connectable. Bind to
   the actual LAN IP (e.g. `--ip 192.168.1.42`).

## Run

```powershell
# From repo root, on the machine the browser will reach:
cd example/sfu
# Replace 192.168.1.42 with the actual LAN IP you want browsers to dial.
dart run bin/sfu_server.dart --ip 192.168.1.42 --ws-port 8080
```

You should see:

```
SFU signaling listening on ws://192.168.1.42:8080/ws
Browser demo:               http://192.168.1.42:8080/
Health probe:               http://192.168.1.42:8080/health
Live stats:                 http://192.168.1.42:8080/stats
```

## Drive a browser

1. Open `http://<lan-ip>:8080/` in **two different browser windows**
   (or two devices on the same network).
2. Set the `id` field to `alice` in window 1 and `bob` in window 2.
3. Click **Join** in alice first, then in bob.
4. Browser will prompt for camera + mic. Accept.
5. Within a few seconds you should see:
   - alice's window shows alice's local preview + bob's remote video
   - bob's window shows bob's local preview + alice's remote video

## Capture state when something breaks

Three endpoints. Hit them all and paste output verbatim.

### `/health` — sanity

```powershell
curl http://192.168.1.42:8080/health
# expect: {"status":"ok","participants":2}
```

### `/sdp` — last offer/answer pair per participant + connection state

```powershell
curl http://192.168.1.42:8080/sdp > sdp.json
```

This is the most useful artifact. `connectionState` will tell you whether
DTLS completed:

- `new` / `connecting` — handshake in progress or never started
- `connected` — DTLS done, SRTP keyed
- `failed` — handshake failed (look at server stderr for the DTLS alert)

`offer` is what the browser sent. `answer` is what the SFU sent back
(post-augmentation with FID/cname/msid lines). Compare them line-by-line:
mids must match, fingerprints must be present, ssrc-group lines must
reference declared SSRCs.

### `/stats` — runtime forwarding counters

```powershell
curl http://192.168.1.42:8080/stats > stats.json
```

Per participant:
- `traffic.rtpReceived` — packets the SFU got from this peer (should
  climb steadily once `connectionState=connected`)
- `traffic.rtpSent` — packets the SFU forwarded to this peer
- `traffic.recvBps` / `sendBps` — rolling 2-second bitrate

Aggregate (`forwarding`):
- `pliSent` — keyframe requests the SFU made
- `nackSent` — generic NACKs sent (only if `--enable-server-nack`)
- `rtpDropped` — drops on the outbound path (peer not yet keyed)

### Browser-side

In the demo, the bottom of each tab shows the live `/stats` JSON polled
every 2s. The text log above it shows ICE / connection / renegotiate
events. Open browser DevTools → Console for `getStats()` and any
`InvalidAccessError` exceptions when applying the answer.

## Common failures and what to look for

| Symptom | Where to look |
| --- | --- |
| Browser console: "Failed to set remote answer sdp" | `/sdp` → answer field. Compare m-line count & order to offer. |
| `iceConnectionState` stuck on `checking` | LAN IP bind issue; SFU bound to `0.0.0.0` advertises `0.0.0.0` as candidate. Re-run with `--ip <real-ip>`. |
| `connectionState=connected` but no remote video | `/stats` → `traffic.rtpSent` is incrementing for the receiver? If yes, browser-side decode issue (check Console / `chrome://webrtc-internals`). If no, SSRC ownership or rewriting bug. |
| Audio works but video doesn't | Browser offered a video codec the SFU doesn't support. Check answer SDP for `m=video 0` (rejected). |
| Server log "DTLS alert" | DTLS handshake mismatch. Most often: cipher suite or curve. Capture wireshark on the SFU port. |

## When you hit something

Paste these in a follow-up:
1. Browser name + version
2. The LAN command line you used to start the SFU
3. Server stderr from the moment you clicked Join
4. `sdp.json` and `stats.json` from the failing moment
5. Browser DevTools console output (Errors tab)
6. (Optional but very useful) `chrome://webrtc-internals` dump for that pc
