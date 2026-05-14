# ion-style SFU example

A re-engineering of [`example/sfu`](../sfu) that adopts the architecture
of [pion/ion-sfu](../ion-sfu): per-peer **Publisher + Subscriber**
PeerConnections, a [`Session`](lib/src/session.dart) abstraction, per-publisher
[`Router`](lib/src/router.dart) with [`Receiver`](lib/src/receiver.dart) →
[`DownTrack`](lib/src/down_track.dart) wiring, and pluggable subsystems for
NACK / jitter buffering, simulcast layer selection, TWCC + REMB
bandwidth estimation, an audio level observer, SFU-to-SFU relay,
per-session isolate sharding, and Prometheus-style stats.

This example is built directly on `pure_dart_webrtc`. It shares no code
with `example/sfu`; the two demos are intentionally side-by-side so the
single-PC and split-PC topologies can be compared.

## Running the demo

The split-PC browser client lives in [`web/index.html`](web/index.html)
and talks to the SFU over WebSocket on port 9091 (the HTTP page itself
is served separately on port 8000).

### 1. Find your LAN IPv4 address

The SFU has to advertise an ICE host candidate that the browser can
actually route to. On Windows / PowerShell:

```powershell
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.PrefixOrigin -ne 'WellKnown' } |
  Select-Object IPAddress, InterfaceAlias | Format-Table -AutoSize
```

Pick your Wi-Fi or Ethernet IP (e.g. `10.100.53.178`). Avoid any
`vEthernet (WSL …)` / `Default Switch` / Hyper-V interfaces — those
are virtual adapters the browser cannot reach.

### 2. Start the SFU

```powershell
cd example/ion_style_sfu
dart run bin/sfu_server.dart `
  --ip 0.0.0.0 `
  --ws-port 9091 `
  --rtp-base 51000 `
  --announce-ip 10.100.53.178
```

Flags:

* `--ip 0.0.0.0` — bind UDP/TCP on every interface (so traffic from any
  network adapter can reach it).
* `--ws-port 9091` — HTTP/WebSocket port (`/ws/<sid>`, `/stats`,
  `/metrics`, `/healthz`, `/admin/drain`).
* `--rtp-base 51000` — first UDP port for media transports. Each
  session reserves a 64-port slice (`51000–51063`, `51064–51127`, …).
* `--announce-ip <your-LAN-IP>` — the IP put into the SDP host
  candidate. **Use the LAN IP from step 1**, not `127.0.0.1`. Loopback
  works only when both tabs and the SFU are on the same machine *and*
  the browser happens to choose its loopback adapter for ICE — most
  Windows + Chrome combinations don't, which is why localhost ICE
  often hangs at `checking → disconnected`.

You should see:

```
INFO  sfu listening {wsUrl=ws://10.100.53.178:9091/ws/<sessionId>, ...}
```

If Windows Firewall pops up the first time, allow `dart.exe` on
private networks (port 9091 + the UDP range starting at 51000).

### 3. Serve the browser client

In a second terminal:

```powershell
cd example/ion_style_sfu/web
python -m http.server 8000
```

(Any static file server works — `dart pub global run dhttpd`,
`npx serve`, etc.)

### 4. Open the demo in the browser

Open one tab per peer (any number — the SFU fans out everyone to
everyone). Use the **same LAN IP** for both the page and the WS so
`getUserMedia` and the WebRTC ICE candidates agree:

```
http://10.100.53.178:8000/?server=ws://10.100.53.178:9091&sid=room1&uid=alice
http://10.100.53.178:8000/?server=ws://10.100.53.178:9091&sid=room1&uid=bob
http://10.100.53.178:8000/?server=ws://10.100.53.178:9091&sid=room1&uid=carol
http://10.100.53.178:8000/?server=ws://10.100.53.178:9091&sid=room1&uid=dave
```

Each tab will:

1. Prompt for camera/mic.
2. Open `/ws/room1` and send `{type:"join"}`.
3. Negotiate the publisher PC (its tracks → SFU).
4. Negotiate the subscriber PC (every other peer's tracks → it).
5. Show its local preview plus one remote `<video>` per other peer.

Healthy console output ends with `pub ice: connected` and
`sub ice: connected` for every joined tab. The `<pre>` panel below
the videos polls `/stats` every 2 seconds.

> If the tab logs `pub ice: disconnected` immediately after
> `checking`, your browser couldn't reach the announced host
> candidate. Re-check `--announce-ip` (it must match a real adapter
> the browser can route to) and confirm the firewall rule.
> If your laptop roams between Wi-Fi networks, the IP changes — stop
> the SFU and restart with the new `--announce-ip`.

### 5. Useful endpoints while the SFU is running

```powershell
# Live snapshot (counts, peers, RTP/RTCP totals)
curl http://10.100.53.178:9091/stats | ConvertFrom-Json

# Prometheus exposition
curl http://10.100.53.178:9091/metrics

# Liveness (returns 503 once draining)
curl http://10.100.53.178:9091/healthz

# Trigger graceful drain (no new sessions; existing peers keep going)
curl -X POST http://10.100.53.178:9091/admin/drain
```

### Cluster mode (optional)

To run two SFUs that cascade media across hosts:

```powershell
# Node A
dart run bin/sfu_server.dart --ip 0.0.0.0 --ws-port 9091 --rtp-base 51000 `
  --announce-ip 10.100.53.178 `
  --self-id a:9091 `
  --relay-port 9092 `
  --relay-secret hunter2 `
  --peers a:9091:9092@10.100.53.178,b:9091:9092@10.100.53.179

# Node B (mirror; --self-id b:9091)
```

Sessions are owned by exactly one node (consistent hash on the sid);
peers that hit a non-owner node are bridged via UDP relay. See
[`docs/`](../../docs/) for the full design notes.

## Status

The original "stub" phases have all landed. Each subsystem has its own
unit tests under [`test/`](test/) and is wired into the live SFU.

| # | Subsystem | Code | Tests |
|---|-----------|------|-------|
| 1 | Scaffold, Pub/Sub split PCs, Session, Router, Receiver, DownTrack, WS+JSON signaling, two-PC web client | [`lib/src/`](lib/src/), [`bin/sfu_server.dart`](bin/sfu_server.dart), [`web/index.html`](web/index.html) | — |
| 2 | Per-receiver jitter buffer + NACK responder | [`lib/src/buffer/`](lib/src/buffer/) | [`test/jitter_nack_test.dart`](test/jitter_nack_test.dart) |
| 3 | Simulcast parsing, layer selection (`q`/`h`/`f`), SN/TS rewrite on layer switch, auto PLI | [`lib/src/simulcast.dart`](lib/src/simulcast.dart), [`lib/src/simulcast_rewriter.dart`](lib/src/simulcast_rewriter.dart) | [`test/simulcast_parse_test.dart`](test/simulcast_parse_test.dart), [`test/simulcast_rewriter_test.dart`](test/simulcast_rewriter_test.dart), [`test/modern_simulcast_test.dart`](test/modern_simulcast_test.dart) |
| 4 | RFC 6464 audio level observer | [`lib/src/audio_observer.dart`](lib/src/audio_observer.dart) | [`test/audio_observer_test.dart`](test/audio_observer_test.dart), [`test/audio_observer_wiring_test.dart`](test/audio_observer_wiring_test.dart) |
| 5 | TWCC + REMB feedback, EMA bandwidth estimator, layer selector | [`lib/src/twcc/`](lib/src/twcc/), [`lib/src/bwe.dart`](lib/src/bwe.dart) | [`test/twcc_remb_test.dart`](test/twcc_remb_test.dart), [`test/twcc_stamper_test.dart`](test/twcc_stamper_test.dart), [`test/bwe_test.dart`](test/bwe_test.dart) |
| 6 | SFU-to-SFU relay (compact JSON descriptor, no SDP renegotiation) | [`lib/src/relay/`](lib/src/relay/) | [`test/relay_test.dart`](test/relay_test.dart), [`test/relay_export_test.dart`](test/relay_export_test.dart) |
| 7a | Sender Reports / Receiver Reports + RTCP rewrite into the rewritten SSRC timeline | [`lib/src/rtcp.dart`](lib/src/rtcp.dart), [`lib/src/rtcp_rewrite.dart`](lib/src/rtcp_rewrite.dart) | [`test/rtcp_test.dart`](test/rtcp_test.dart), [`test/rtcp_rewrite_test.dart`](test/rtcp_rewrite_test.dart) |
| 7b | Delay-gradient (GCC-style) controller fed by TWCC arrival times | [`lib/src/bwe.dart`](lib/src/bwe.dart) | [`test/bwe_delay_test.dart`](test/bwe_delay_test.dart) |
| 8 | SSRC allocator, RTP header extension plumbing, SDP helpers | [`lib/src/ssrc_allocator.dart`](lib/src/ssrc_allocator.dart), [`lib/src/rtp_header.dart`](lib/src/rtp_header.dart), [`lib/src/sdp_helpers.dart`](lib/src/sdp_helpers.dart) | [`test/ssrc_allocator_test.dart`](test/ssrc_allocator_test.dart), [`test/rtp_extensions_test.dart`](test/rtp_extensions_test.dart), [`test/sdp_helpers_test.dart`](test/sdp_helpers_test.dart) |
| 8.2 | Per-session isolate sharding (`SessionShard` + `ShardedSfu` with RPC over `SendPort`) | [`lib/src/session_shard.dart`](lib/src/session_shard.dart), [`lib/src/sharded_sfu.dart`](lib/src/sharded_sfu.dart) | [`test/session_shard_test.dart`](test/session_shard_test.dart) |
| 9 | Per-DownTrack / per-Subscriber stats snapshot, JSON `/stats`, Prometheus `/metrics` | [`lib/src/stats/`](lib/src/stats/) | [`test/prometheus_test.dart`](test/prometheus_test.dart) |

## Architectural mapping

| ion-sfu (Go) | this example (Dart) |
|---|---|
| `pkg/sfu/sfu.go` `SFU` | [`Sfu`](lib/src/sfu.dart) |
| `pkg/sfu/session.go` `SessionLocal` | [`Session`](lib/src/session.dart) |
| `pkg/sfu/peer.go` `PeerLocal` | [`Peer`](lib/src/peer.dart) |
| `pkg/sfu/publisher.go` `Publisher` | [`Publisher`](lib/src/publisher.dart) |
| `pkg/sfu/subscriber.go` `Subscriber` | [`Subscriber`](lib/src/subscriber.dart) |
| `pkg/sfu/router.go` `Router` | [`Router`](lib/src/router.dart) |
| `pkg/sfu/receiver.go` `Receiver` | [`Receiver`](lib/src/receiver.dart) |
| `pkg/sfu/downtrack.go` `DownTrack` | [`DownTrack`](lib/src/down_track.dart) |
| `pkg/sfu/audioobserver.go` | [`AudioObserver`](lib/src/audio_observer.dart) |
| `pkg/buffer/` | [`lib/src/buffer/`](lib/src/buffer/) |
| `pkg/twcc/` | [`lib/src/twcc/`](lib/src/twcc/) |
| `pkg/relay/` | [`lib/src/relay/`](lib/src/relay/) |
| `pkg/stats/` | [`lib/src/stats/`](lib/src/stats/) |
| `cmd/signal/json-rpc` | [`bin/sfu_server.dart`](bin/sfu_server.dart) (WS+JSON) |
| (no equivalent — pion is goroutine-per-room) | [`SessionShard`](lib/src/session_shard.dart) / [`ShardedSfu`](lib/src/sharded_sfu.dart) |

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

The full message set is documented at the top of
[`lib/src/sfu_server.dart`](lib/src/sfu_server.dart) and includes
`join`, `offer`, `answer`, `trickle`, `leave`, plus server-pushed
`peer-joined` / `peer-left` events.

## Run

```powershell
cd example\ion_style_sfu
dart pub get
dart run bin\sfu_server.dart --ip 0.0.0.0 --ws-port 9090 --rtp-base 51000
```

CLI flags exposed by [`bin/sfu_server.dart`](bin/sfu_server.dart):

| Flag | Default | Description |
|---|---|---|
| `--ip` | `0.0.0.0` | Bind address for the WS listener and every UDP transport |
| `--ws-port` | `9090` | TCP port for HTTP/WebSocket signaling |
| `--rtp-base` | `51000` | First UDP port for media transports; each PC consumes one |
| `--announce-ip` | first non-loopback IPv4 | Host candidate IP advertised in SDP (override for NAT) |
| `--auth-token` | _(unset)_ | If set, every WS upgrade and HTTP control endpoint must present `Authorization: Bearer <token>` (or `?token=` query) |
| `--max-peers-per-room` | `0` (unlimited) | Hard cap; the (N+1)-th `join` is rejected with a control error |
| `--max-rooms` | `0` (unlimited) | Hard cap on concurrent active sessions |
| `--peers` | _(unset)_ | Comma-separated `id@host:wsPort[:relayPort]` list of sibling SFUs for cluster mode |
| `--self-id` | _(unset)_ | This node's id in the `--peers` list; required when clustering |
| `--relay-port` | `0` (auto) | UDP port for the SFU-to-SFU relay hub |
| `--relay-secret` | _(unset)_ | Shared secret for HMAC-SHA256 relay framing (mandatory in cluster mode) |

The static client at [`web/index.html`](web/index.html) auto-targets
`ws://<page-host>:9090` and accepts `?server=`, `?sid=`, and `?uid=`
overrides — open it from any HTTP server, or just `file://` it for a
quick local test.

### HTTP endpoints

In addition to `/ws/<sessionId>`, the server exposes:

| Path | Format | Purpose |
|---|---|---|
| `/stats` | JSON ([`SfuSnapshot.toJson`](lib/src/stats/stats.dart)) | Per-session, per-peer, per-DownTrack counters and BWE gauges |
| `/metrics` | Prometheus text exposition v0.0.4 | The same snapshot rendered for scrapers |
| `/healthz` | `text/plain` | Liveness probe (returns `ok` and the active session/peer count) |
| `/locate?sid=<id>` | JSON | Returns `{owner, self, host, wsPort}` so an L7 router can hand a join straight to the owning SFU |

CORS is permissive on both, so a static page served from a different
origin can poll them.

## Public API

Everything intended to be reusable is re-exported from
[`lib/ion_style_sfu.dart`](lib/ion_style_sfu.dart):
`Sfu`, `Session`, `Peer`, `Publisher`, `Subscriber`, `Router`,
`Receiver`, `DownTrack`, `SsrcAllocator`, `AudioObserver`,
`SimulcastRewriter`, `BandwidthEstimator`, `LayerBitrateThresholds`,
`TwccStamper`, the `RelayPeer` family, `SessionShard` / `ShardedSfu`,
the stats snapshot helpers, and `runIonStyleSfuServer`.

## Tests

```powershell
cd example\ion_style_sfu
dart test
```

Each subsystem has its own focused suite (see the table at the top);
none of them require a live network or browser.

## Comparison vs upstream pion/ion-sfu

The Go reference lives at [`example/ion-sfu`](../ion-sfu) and the file
layout below is relative to it.

### Same shape, ported

| Concern | ion-sfu (Go) | this example (Dart) |
|---|---|---|
| Two-PC peer model | `pkg/sfu/peer.go`, `publisher.go`, `subscriber.go` | [`peer.dart`](lib/src/peer.dart), [`publisher.dart`](lib/src/publisher.dart), [`subscriber.dart`](lib/src/subscriber.dart) |
| Session / Router / Receiver / DownTrack | `pkg/sfu/{session,router,receiver,downtrack}.go` | [`session.dart`](lib/src/session.dart), [`router.dart`](lib/src/router.dart), [`receiver.dart`](lib/src/receiver.dart), [`down_track.dart`](lib/src/down_track.dart) |
| Jitter buffer + NACK responder | `pkg/buffer/{buffer,bucket,nack}.go` | [`lib/src/buffer/`](lib/src/buffer/) |
| Simulcast layer selection (`q`/`h`/`f`) | `pkg/sfu/simulcast.go`, plumbing in `downtrack.go` | [`simulcast.dart`](lib/src/simulcast.dart), [`simulcast_rewriter.dart`](lib/src/simulcast_rewriter.dart) |
| RFC 6464 audio observer | `pkg/sfu/audioobserver.go` | [`audio_observer.dart`](lib/src/audio_observer.dart) |
| TWCC feedback parser | `pkg/twcc/twcc.go` | [`lib/src/twcc/`](lib/src/twcc/) |
| TWCC + REMB → BWE → layer pick | (delay-based GCC inside pion/webrtc) | [`bwe.dart`](lib/src/bwe.dart) (EMA + Phase 7b delay-gradient controller) |
| SFU-to-SFU relay | `pkg/relay/relay.go`, `pkg/sfu/relaypeer.go` | [`lib/src/relay/`](lib/src/relay/) |
| RTX sequence rewrite | `pkg/sfu/sequencer.go` (+ `downtrack.go`) | folded into [`simulcast_rewriter.dart`](lib/src/simulcast_rewriter.dart) |
| SDP / media-engine helpers | `pkg/sfu/{helpers,mediaengine}.go` | [`sdp_helpers.dart`](lib/src/sdp_helpers.dart), [`ssrc_allocator.dart`](lib/src/ssrc_allocator.dart), [`rtp_header.dart`](lib/src/rtp_header.dart) |
| Signaling entry point | `cmd/signal/json-rpc/`, `grpc/`, `allrpc/` | [`bin/sfu_server.dart`](bin/sfu_server.dart) (WS+JSON only) |

### Only in pion/ion-sfu

| Subsystem | Where in ion-sfu | Notes |
|---|---|---|
| Embedded TURN server | `pkg/sfu/turn.go` (~157 LOC) | Not ported. Run `coturn` (or any TURN) externally if required. |
| DataChannel control plane (`activeLayer`, layer pinning, mute, etc.) | `pkg/middlewares/datachannel/{keepalive,subscriberapi}.go` | Not ported. The Dart example only uses media transceivers; layer selection is automatic from BWE. |
| gRPC + JSON-RPC signaling variants | `cmd/signal/{grpc,json-rpc,allrpc}/` | Only the WebSocket+JSON path is implemented. |
| Per-receiver Prometheus histograms (RTP drift, expected vs received) | `pkg/stats/stream.go` | Different stats model — see below. |
| Sequencer as a standalone unit (RTX history of every forwarded packet) | `pkg/sfu/sequencer.go` | Equivalent SN/TS bookkeeping is inlined in [`simulcast_rewriter.dart`](lib/src/simulcast_rewriter.dart); a dedicated RTX history buffer is **not** kept (so we cannot fulfil arbitrary NACKs as a sender — only the receiver-side NACK responder runs). |
| Logging façade with structured levels | `pkg/logger/zerologr.go` | Plain `stdout`/`stderr`. |

### Only in this example

| Subsystem | Where | Notes |
|---|---|---|
| Per-session isolate sharding | [`session_shard.dart`](lib/src/session_shard.dart), [`sharded_sfu.dart`](lib/src/sharded_sfu.dart) | Dart's single-threaded isolates motivate explicit sharding; goroutines made this implicit in Go. |
| Prometheus `/metrics` endpoint baked into the signaling server | [`stats/stats.dart`](lib/src/stats/stats.dart), [`sfu_server.dart`](lib/src/sfu_server.dart) | ion-sfu exposes Prometheus collectors but leaves serving them to the host process. |
| Bundled browser client | [`web/index.html`](web/index.html) | ion-sfu ships separate JS demos under [`examples/`](../ion-sfu/examples/). |
| RTCP SR/RR rewrite into the rewritten SSRC timeline as its own unit | [`rtcp.dart`](lib/src/rtcp.dart), [`rtcp_rewrite.dart`](lib/src/rtcp_rewrite.dart) | Equivalent logic in ion-sfu lives inside `downtrack.go` / `receiver.go`. |

### Code-size sanity check

Counting only non-test source:

| | LOC |
|---|---|
| ion-sfu `pkg/sfu` + `pkg/buffer` + `pkg/twcc` + `pkg/relay` + `pkg/stats` | ≈ 5 130 |
| this example `lib/src/**` | ≈ 4 250 |

Roughly the same order of magnitude, with the gap mostly explained by
TURN, datachannel middleware, and the extra signaling transports listed
above.

## Scaling out (multi-host clusters)

A single SFU process is bounded by one Dart isolate's CPU budget. To
push past it, run several `bin/sfu_server.dart` instances and front
them with a thin L7 router (or have clients query `/locate` directly).
The pieces that make this work in-tree:

| Subsystem | File | Responsibility |
|---|---|---|
| Consistent-hash room locator | [`cluster/locator.dart`](lib/src/cluster/locator.dart) | SHA256-based ring with 64 vnodes/peer; `RoomLocator.ownerOf(sid)` deterministically picks an owner. |
| HMAC-framed UDP relay | [`cluster/udp_relay_transport.dart`](lib/src/cluster/udp_relay_transport.dart) | 12-byte header (`'ionr'` magic / version / type / BE length) + payload + 16-byte HMAC-SHA256 tag. Implements the same `RelayTransport` interface used by the in-process relay tests. |
| Auto-cascade orchestrator | [`cluster/cluster_coordinator.dart`](lib/src/cluster/cluster_coordinator.dart) | Bridges the main-isolate `UdpRelayHub` to the per-session worker shards. When a non-owner shard is born, the coordinator opens an upstream `RelayPeer` inside the worker (over a synthetic shard↔main transport) and exchanges a `cascade-hello` envelope so the owner lazily materialises a matching inbound bridge. Receivers fan out across nodes without operator intervention. |
| Pooled RTP buffers | [`byte_pool.dart`](lib/src/byte_pool.dart) | Per-isolate power-of-two `Uint8List` recycler that the simulcast rewriter and jitter buffer feed; eliminates the per-packet `Uint8List.fromList` allocation on the fan-out hot path. |

Loop prevention is handled by tagging cluster-originated peer ids with
the `cluster:` prefix; the cascade refuses to re-cascade those.

### Run a 2-node cluster locally

```powershell
# node A
dart run bin\sfu_server.dart --self-id A --ws-port 9090 --rtp-base 51000 `
  --relay-port 60000 --relay-secret super-secret `
  --peers "A@127.0.0.1:9090:60000,B@127.0.0.1:9091:60001"

# node B
dart run bin\sfu_server.dart --self-id B --ws-port 9091 --rtp-base 52000 `
  --relay-port 60001 --relay-secret super-secret `
  --peers "A@127.0.0.1:9090:60000,B@127.0.0.1:9091:60001"
```

Either node accepts joins for any session; non-owners cascade their
local receivers to the owner over the relay socket. `/healthz`
reports `mode: 'cluster'`, the `self` id, and a snapshot of every
active cascade bridge; `/locate?sid=<id>` resolves the owning peer
(using the same SHA256 vnode ring both nodes agree on).

## Load test driver

The "test drive" requested in the original brief lives at
[`bin/load_test.dart`](bin/load_test.dart) and exercises the
fan-out + jitter + pool path **without** running real PeerConnections,
so the harness can saturate a developer laptop with hundreds of
simulated subscribers in seconds.

```powershell
cd example\ion_style_sfu
dart run bin\load_test.dart --rooms 1 --pubs 4 --subs 4 --pps 200 --duration 5s --jitter 64
```

| Flag | Default | Description |
|---|---|---|
| `--rooms` | `1` | Number of independent sessions |
| `--pubs` | `1` | Publishers per room |
| `--subs` | `4` | Subscribers per publisher |
| `--pps` | `30` | Packet rate per publisher |
| `--payload` | `1100` | RTP payload bytes (header is added) |
| `--duration` | `3s` | Measurement window after warm-up |
| `--warmup` | `500ms` | Discarded preamble (lets timers settle) |
| `--jitter` | `512` | Per-edge jitter buffer capacity (lower → more pool churn) |
| `--no-pool` | _(off)_ | Disables `BytePool`, baseline for A/B |
| `--json` | _(off)_ | Emits machine-readable [`LoadTestReport.toJson`](lib/src/load_test.dart) instead of the human report |

Sample human-readable report (`--pubs 4 --subs 4 --pps 200 --duration 5s --jitter 64`):

```
== load test report ==
config:        rooms=1 pubs=4 subs/pub=4 pps/pub=200
target:        800 gen-pps, 3200 fan-out pps, 16 edges
duration:      5008 ms (warmup excluded)
generated:     1305 pkts (deficit 540 pps vs target)
forwarded:     5220 pkts (1042 pps, 9.3 Mbps)
fan-out cov:   100.00% (1.00 = no drops)
dropped:       0 pkts
pool:          hit-rate 82.3% (4755h/1025m/4756r, parked 1)
latency:       p50=50us p95=50us p99=50us max=1003us mean=1us
```

Rerunning the same command with `--no-pool` drops hit-rate to `0.0%`
and forces ~5 800 fresh `Uint8List` allocations — the A/B baseline.

> The "deficit … pps vs target" line reflects Dart `Timer.periodic`
> resolution under heavy concurrent timers; raise `--pps` only as far
> as `generated` actually keeps up, then scale `--rooms` × `--pubs` to
> add load instead.

## Known limitations

- The bundled signaling server now spawns one worker isolate per
  session ([`SessionShard`](lib/src/session_shard.dart) +
  [`ShardedSfu`](lib/src/sharded_sfu.dart)); each shard owns its own
  `Sfu`, PCs, and a 64-port UDP slice carved out of `--rtp-base`.
  This changes operational characteristics: stats are aggregated
  across shards, and there is no longer a single in-process
  `Session` you can poke at from main-isolate code (use
  [`SessionShard`](lib/src/session_shard.dart) RPCs instead).
- TWCC stamping requires the publisher to have already negotiated the
  one-byte transport-cc extension (every recent Chrome does);
  inserting a fresh extension block when the upstream omitted it is
  not implemented — see the header comment in
  [`lib/src/twcc/twcc_stamper.dart`](lib/src/twcc/twcc_stamper.dart).
- The bearer token (`--auth-token`) is a static shared secret. There
  is no per-room ACL, no JWT verification, and no per-IP rate
  limiting; pair the SFU with a reverse proxy when exposing it
  publicly.
- The load-test driver bypasses real PeerConnections and DTLS/SRTP,
  so it measures the rewriter / jitter / pool / fan-out path only.
  End-to-end CPU and bandwidth in production will be higher.
