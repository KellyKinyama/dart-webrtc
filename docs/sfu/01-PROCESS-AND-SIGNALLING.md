# 1. Process and signalling

How a client gets from "double-clicking the page" to "talking to the
SFU over a WebSocket". This chapter covers the entry point and the
JSON protocol; the SDP/ICE negotiation that follows is left to
chapter 2.

---

## 1.1. Entry point

[`bin/sfu_server.dart`](../../example/ion_style_sfu/bin/sfu_server.dart)
is a tiny CLI flag parser that calls `runIonStyleSfuServer(...)`.
Run it with no flags to bind defaults:

```pwsh
cd c:\www\dart\dart-webrtc\example\ion_style_sfu
dart run bin/sfu_server.dart --ip 0.0.0.0 --ws-port 9090 --rtp-base 51000
```

Useful flags (full list with `--help`):

| Flag | Purpose |
|---|---|
| `--ip` / `--ws-port` | What to bind |
| `--rtp-base` | First UDP port for RTP transports; subsequent transports take `rtp-base + n` |
| `--announce-ip` | What to put in ICE candidates (use this when the bind IP is `0.0.0.0` and you have a real public IP) |
| `--auth-token` | Bearer token required on the WebSocket upgrade |
| `--max-rooms` / `--max-peers-per-room` | Soft caps |
| `--ice-server stun:host:port` | Forwarded into PCs so server-reflexive candidates are gathered |
| `--peers id@host:port,...` + `--self-id` + `--relay-port` | Enable cluster mode (see chapter 9) |

The CLI just calls
[`runIonStyleSfuServer()`](../../example/ion_style_sfu/lib/src/sfu_server.dart)
which is the actual public entry point — you can embed the SFU in
your own app by calling that function directly.

---

## 1.2. What `runIonStyleSfuServer` constructs

In order:

1. A **`Logger`** (or silent if `quiet`).
2. The **announced IP** — explicit `--announce-ip` else first
   non-loopback IPv4 (if bound to `0.0.0.0`).
3. **`ShardedSfu`** with a `ShardConfigTemplate` that captures all
   per-session knobs (bind address, RTP base port, ICE servers, idle
   timeouts, peer caps).
4. (optional) **Cluster wiring**: `RoomLocator`, `UdpRelayHub`,
   `ClusterCoordinator` — see chapter 9.
5. An **`HttpServer`** bound to `(ip, ws-port)`.
6. A **request router** dispatching:
    * `GET /healthz` → 200 OK (or 503 while draining)
    * `GET /stats` → JSON snapshot
    * `GET /metrics` → Prometheus text
    * `GET /ws/<sessionId>` → WebSocket upgrade

Returns an
[`IonSfuServerHandle`](../../example/ion_style_sfu/lib/src/sfu_server.dart)
holding `(http, sharded, cluster?)` and exposing `drain()` and
`close()`.

If `installSignalHandlers: true`, SIGINT/SIGTERM are wired:
first signal → `drain()`, second → `close()`. Off by default so
tests don't fight the process-wide listeners.

---

## 1.3. The signalling protocol

One message per JSON object, sent as WebSocket TEXT frames. The
protocol is intentionally minimal — there's no room for in-band
configuration or capability negotiation; everything goes through SDP.

### Client → Server

```jsonc
{"type":"join", "sid":"room1", "uid":"alice"}

// publisher offer (the client wants to publish)
{"type":"offer", "target":"pub", "sdp":"..."}

// subscriber answer (the client received our offer for downstream tracks)
{"type":"answer", "target":"sub", "sdp":"..."}

// ICE candidate, either side
{"type":"trickle", "target":"pub|sub",
 "candidate":"...", "sdpMid":"0", "sdpMLineIndex":0}

{"type":"leave"}
```

### Server → Client

```jsonc
// answer to the publisher offer
{"type":"answer", "target":"pub", "sdp":"..."}

// the SFU wants to send tracks; client must answer
{"type":"offer", "target":"sub", "sdp":"..."}

// our ICE candidates
{"type":"trickle", "target":"sub", "candidate":"..."}

// presence
{"type":"peer-joined", "uid":"bob"}
{"type":"peer-left",   "uid":"bob"}
```

Note the asymmetry: **clients drive `offer/answer` for the
publisher PC**, **the SFU drives it for the subscriber PC**. That's
the consequence of the two-PC model from §0.2 — the client is the
*offerer* in the uplink and the *answerer* in the downlink.

---

## 1.4. Defenses on the WebSocket boundary

[`sfu_server.dart`](../../example/ion_style_sfu/lib/src/sfu_server.dart)
is paranoid about untrusted input. Read the constants near the top:

| Defense | Constant | Why |
|---|---|---|
| Frame size cap | `_maxSignalingFrameBytes = 256 KB` | A malicious client could otherwise stream GBs into `jsonDecode` |
| Per-WS rate limit | `_maxSignalingMsgsPerWindow = 64` per 5 s | Protect against rapid join/leave loops |
| Identifier validation | `_isValidId()` (alnum + `-._:` only, ≤128 chars) | These end up as map keys, JSON keys, sometimes log lines |
| Auth | `_constantTimeEquals()` | Token compare runs in constant time so timing can't leak the token |
| Keepalive | `_wsPingInterval = 20 s` | Detect half-open TCP (laptop lid closed, NAT timeout) |

Every one of these is a defensive layer, not an optimization. Treat
them as load-bearing.

---

## 1.5. The session router

Inside `sfu_server.dart`, the main-isolate piece that takes a
WebSocket and binds it to a `SessionShard` worker:

* `_SessionRouter` — one per session-id. Owns the set of `_ClientWs`
  for that session, plus the SendPort to the worker. On inbound WS
  frames it validates, authenticates, then RPCs the worker. On
  outbound shard events it broadcasts to all clients in the session
  (or just the originating one for direct replies like `answer/sub`).

* `_ClientWs` — wraps one `WebSocket` with the rate-limiter, the
  ping timer, and a `peerId` (`uid`) once `join` is processed.

The worker boundary is important: the WebSocket lives in the **main
isolate**, but everything past `join` runs in the **shard worker
isolate**. Communication is by `SendPort` of JSON-serializable
envelopes, so don't put `Uint8List` in there casually — it'll be
copied.

---

## 1.6. Bringing up a peer end-to-end

The full happy-path sequence, taking it past `join`:

1. Browser opens `wss://sfu.example.com/ws/room1`. WebSocket
   upgrade. `_ClientWs` constructed.
2. Browser sends `{"type":"join","sid":"room1","uid":"alice"}`.
3. `_SessionRouter.handle()` validates ids, hits auth check, RPCs
   the worker.
4. Worker (in `SessionShard`): looks up `Sfu`, calls
   `Sfu.getSession("room1")` (creates if absent). Constructs a
   `Peer("alice")`, registers it on the session.
5. Peer constructs Publisher and Subscriber PCs (chapter 2 §2.4).
6. Browser, having decided to publish a camera, sends
   `{"type":"offer","target":"pub","sdp":"..."}`.
7. Worker calls `peer.answerPublisherOffer(sdp)`. The publisher
   PC's transport opens, ICE/DTLS succeed (uses parent repo's
   stack — see [`docs/dart/`](../dart/)), Router binds to the
   parsed SSRCs.
8. Worker sends `{"type":"answer","target":"pub","sdp":"..."}` back.
9. The Publisher fires `Session.publish()` for each receiver,
   which makes every other Subscriber in the room emit
   `negotiationneeded`. Each emits an `offer/sub` to its client.
10. Each client answers; the answer is RPC'd back to the worker.
11. RTP starts flowing. We are in the hot path now.

The cold-path SDP sequence is the same as ion-sfu Go, just
implemented in Dart. SDP construction lives in
[`lib/src/sdp_helpers.dart`](../../example/ion_style_sfu/lib/src/sdp_helpers.dart)
and the parent repo's
[`lib/signal/sdp_v2.dart`](../../lib/signal/sdp_v2.dart).

---

Next: [Chapter 2 — Sfu, Session, Peer](./02-SFU-SESSION-PEER.md).
