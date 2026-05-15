# ion-style SFU — open issues to revisit

Snapshot of where multi-tab debugging left off. Pick this up when the SFU
is running on a real (non-loopback) host so we can isolate browser-vs-
network-vs-server bugs.

## 1. Late-joining peer never publishes RTP to the SFU

**Symptom.** With two tabs joined to the same room on the same machine,
`/stats` shows fan-out is one-way: one peer's `packetsForwarded` grows,
the other's stays at 0. The "broken" peer's subscriber side is fine
(`subscriberBwe` is non-zero), but the SFU never sees inbound RTP from
that peer's publisher PC.

**Confirmed.** DTLS handshake completes for both peers (4× "Exporting
keying material" lines for the 2×2 PCs). ICE iceConnectionState reaches
`connected` on both pub PCs in Chrome. So this is *not* a handshake or
candidate-selection failure.

**Diagnostic instrumentation (already in tree).**
[`Publisher`](lib/src/publisher.dart) logs
`[pub:<peerId>] inbound RTP #<N> ssrc=<hex> len=<bytes>` at the first
packet and every 500 packets. On the next session, look for whether the
"#1" line appears for **both** peers or only one.

**Hypotheses, in order of likelihood.**
1. Same-machine UDP loopback artifact — two `RtcUdpTransport`s sharing
   the host's loopback path may be silently misrouting SRTP between
   peers. Should disappear when peers run from different machines.
2. SRTP context cross-talk in [`RtcUdpTransport`](../../lib/webrtc/rtc_udp_transport.dart)
   — if the context lookup keys on something not unique-per-PC (e.g.
   announce-IP only), packets from peer-B may be decrypted with peer-A's
   key and silently dropped.
3. Browser-side: `meet.html`'s publisher PC isn't actually being fed
   the camera track on the second tab. Check
   `chrome://webrtc-internals` `outbound-rtp(video).bytesSent` on the
   "broken" tab — if zero, the bug is in `setupPubPc()`.

**Next step.** Reproduce on a deployed host with one peer per machine.
If it goes away, hypothesis (1) is confirmed and we add a guard. If it
persists, instrument `RtcUdpTransport.handleDatagram` with per-context
demux logging.

## 2. DTLS `InternalError` alerts on subscriber renegotiation

**Symptom.** SFU log shows `[dtls] <- Alert level=LevelFatal
description=InternalError` immediately after the SFU sends a
renegotiation offer to add a freshly-arrived producer's tracks to an
already-running subscriber PC.

**Hypothesis.**
[`Subscriber.createOffer`](lib/src/subscriber.dart) calls
`pc.setLocalDescription(raw)` with the **un-augmented** offer, then ships
the **augmented** SDP (with rewritten SSRCs and FID groups) to Chrome.
On the first offer the divergence is benign; on a renegotiation Chrome
cross-validates against the cached local description and rejects.

**Fix sketch.** Either:
- Set the local description to the augmented SDP too (round-trip the
  augmented string through `setLocalDescription`), or
- Don't augment on renegotiation when the SSRC set hasn't changed (skip
  the rewrite for already-attached DownTracks).

The first option is cleaner if `pc.setLocalDescription` will accept the
augmented form.

## 3. Same-uid silent overwrite at the SFU

**Symptom.** Two clients joining the same room with the same uid — the
second's WebSocket silently replaces the first's in
[`_SessionRouter.register`](lib/src/sfu_server.dart) (`sockets[uid] =
ws`); the worker `_join` sees the uid already present and silently
no-ops, leaving an orphan PC pair.

**Sidestep already in place.** `meet.html` auto-suffixes uid per tab
(`<slug>-<rand5>`).

**Server-side options.**
1. Reject duplicate join with `{type:'error', reason:'uidInUse'}`
   (recommended).
2. Auto-suffix server-side and echo the effective uid back in `joined`.
3. Kick the old peer.

## 4. Cosmetic: encrypted DTLS alert mis-decoded

```
decripted data: [21, 254, 253, 0, 1, 0, 0, 0, 0, 0, 1, 0, 26, 1, 0]
[dtls] <- Alert level=Invalid alert level description=Invalid alert description
```

The DTLS layer is parsing an *encrypted* alert (epoch=1) as if it were
plaintext. Always fires on a normal browser disconnect. Suppress when
`epoch > 0` and we don't have the inbound key, or decrypt first then
parse.

---

## Diagnostic instrumentation currently in tree

- [`Publisher`](lib/src/publisher.dart) — inbound RTP/RTCP packet logger.
- [`meet.html`](web/meet.html) — per-tile HUD reading
  `RTCRtpReceiver.getStats()`, color-coded:
  - red `bytes 0` → no SRTP arriving
  - yellow `dec 0` → arriving but not decoding
  - green `WxH @ kbps · fps` → decoding fine
  - autoplay-recovery overlay if `play()` is rejected

## Operational reminders

- WS endpoint: `ws://<host>:9091/ws/<sid>`. HTTP: `/stats`, `/metrics`.
- Client URL: `http://<host>:8000/meet.html?server=ws://<host>:9091&sid=<room>`.
- Detached launch (PowerShell) with file logging:
  ```powershell
  Start-Process dart -ArgumentList @(
    'run','example/ion_style_sfu/bin/sfu_server.dart',
    '--ip','0.0.0.0','--ws-port','9091','--rtp-base','51000',
    '--announce-ip','<PUBLIC_IP>',
    '--ice-server','stun:stun.l.google.com:19302'
  ) -RedirectStandardOutput sfu.log -RedirectStandardError sfu.err -NoNewWindow
  ```
- Open UDP `51000-51999` (or whatever range RTP needs) on the firewall
  in addition to TCP `9091`.
