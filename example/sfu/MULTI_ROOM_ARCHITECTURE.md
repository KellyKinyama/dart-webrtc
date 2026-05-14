# Multi-room SFU: worker-pool architecture

This document describes how the basic SFU is sharded across isolates so
one Dart process can host many concurrent rooms — each running on its
own isolate's event loop, with rooms hashed across a fixed-size worker
pool.

The single-room hot-path optimisations from [SCALING.md](SCALING.md)
still apply *inside* each worker. This doc only covers the inter-room
topology.

## Why isolates and not threads

Dart's concurrency model is single-isolate / single-event-loop. CPU
work (SRTP encrypt/decrypt, SDP parsing, packet routing) cannot be
parallelised across cores within one isolate. To use more than one
core we have to spawn additional isolates and route work between them.

The room is the natural unit of parallelism: every RTP packet stays
inside a single room, so cross-isolate SendPort traffic is limited to
control-plane messages (`/health` aggregation, graceful shutdown). The
RTP fast path never crosses an isolate boundary.

## Topology

```
                  ┌─────────────────────────┐
                  │  Main isolate           │
                  │  (RoomRouter)           │
                  │                         │
client ─HTTP────► │  HTTP :8080             │
                  │  GET /room/:id/locate   │
                  │    → { port: 8082 }     │
                  │  GET /                  │
                  │    → demo HTML          │
                  │  GET /health            │
                  │    → aggregate          │
                  └──────┬──────────────────┘
                         │ SendPort
                         │ (control plane only)
       ┌─────────────────┼──────────────────┬──────────────────┐
       ▼                 ▼                  ▼                  ▼
┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│ Worker 0    │  │ Worker 1    │  │ Worker 2    │  │ Worker N-1  │
│ Isolate     │  │ Isolate     │  │ Isolate     │  │ Isolate     │
│ HTTP :8081  │  │ HTTP :8082  │  │ HTTP :8083  │  │ HTTP :80*N  │
│             │  │             │  │             │  │             │
│ rooms:      │  │ rooms:      │  │ rooms:      │  │ rooms:      │
│  alpha      │  │  bravo      │  │  charlie    │  │  november   │
│  echo       │  │  foxtrot    │  │  golf       │  │  oscar      │
│             │  │             │  │             │  │             │
│ each room   │  │ each room   │  │ each room   │  │ each room   │
│ = BasicSfu  │  │ = BasicSfu  │  │ = BasicSfu  │  │ = BasicSfu  │
└─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘
   UDP RTP         UDP RTP           UDP RTP           UDP RTP
   (OS-picked      (OS-picked        (OS-picked        (OS-picked
    ports per       ports)            ports)            ports)
    participant)
```

## Routing

### Step 1 — Discovery (HTTP, main isolate)

```
GET /room/alpha/locate
→ 200 OK
  { "host": "203.0.113.10", "port": 8082, "ws": "ws://203.0.113.10:8082/ws/alpha" }
```

The router computes `worker = hash(roomId) % workerCount` and returns the
worker's WebSocket URL. The client then connects directly to that worker
— no proxying through main isolate.

Hashing uses a stable variant of FNV-1a so the same `roomId` always
lands on the same worker across reconnects (and across server restarts
as long as the worker count doesn't change).

### Step 2 — Signaling (WebSocket, direct to worker)

```
ws://203.0.113.10:8082/ws/alpha
```

Worker isolate accepts the upgrade, looks up (or creates) the
`BasicSfu` for `roomId="alpha"` in its local `Map<String, BasicSfu>`,
and runs the existing signaling protocol against it. The WS connection
never crosses an isolate boundary again after the upgrade.

### Step 3 — Media (UDP, direct to worker process)

The peer connection's host ICE candidates use the worker's UDP socket
binding. RTP packets travel directly between the browser and the
worker, with no router involvement.

## Why redirect (HTTP discovery) instead of WS proxy

Two viable designs:

| Design | Latency | Throughput | Scaling ceiling |
|--------|---------|------------|-----------------|
| Proxy WS through main isolate to worker via SendPort | +1 hop per signaling msg | Bottlenecked on main isolate's event loop | Hundreds of clients connecting/sec |
| **Discovery hop, direct WS to worker** | +1 HTTP roundtrip on join only | All signaling skips the main isolate | Limited only by worker count and per-worker HTTP server |

We picked the discovery model. Joining costs one extra HTTP request,
but every subsequent signaling message (offer, answer, candidate,
renegotiate) goes straight to the worker. This matters because
renegotiation traffic dominates as room churn rises.

The trade-off: the demo HTML now does `fetch('/room/<id>/locate')`
before opening the WebSocket, and the worker port must be reachable
from the client. In a NAT'd / firewalled deployment the operator must
port-forward the whole worker-port range, not just the router port.

## UDP port allocation

Each `BasicSfu` allocates a UDP socket per participant. With multiple
rooms per worker isolate we cannot statically partition the port
namespace; instead every transport binds to **port 0** and lets the
kernel pick a free port. The actual port is read back from the bound
socket and propagated into ICE candidates.

This means:

- No port-collision possible between rooms or between workers.
- Operators must allow inbound UDP on any high port to the worker
  process (typical for SFU deployments anyway).
- The demo `--rtp-base` flag is ignored in multi-room mode.

## Hashing and rebalancing

Routing is `hash(roomId) % workerCount`. The hash is a small inline
FNV-1a so routing is deterministic across processes without depending
on `Object.hashCode`'s per-isolate randomisation.

This is **fixed shard placement**: changing `workerCount` rehashes
every room. There is no live migration / consistent hashing in this
patch — restart with the new size when capacity needs change.

Rationale: live room migration requires moving SRTP contexts and active
peer connections between isolates, which `pure_dart_webrtc` does not
support. For deployments where rebalancing matters, run a fixed pool
sized for peak load.

## Backpressure and quotas

Per-worker quotas are passed through to every `BasicSfu` the worker
creates:

- `maxRoomsPerWorker` — hard cap on rooms in one isolate. Exceeding it
  rejects new room creation with a 503 from the worker.
- `maxParticipantsPerRoom` — passed as `BasicSfu.maxParticipants`.
- `maxInFlightBytesPerReceiver` — passed through unchanged.

The router doesn't know per-worker load up-front (it only tracks
which worker hashes own which roomIds, not how loaded they are). If
the worker for a room is at capacity, the worker rejects the WS
upgrade with HTTP 503; the client surfaces that to the user.

## Failure isolation

- A panic / unhandled exception in one worker isolate kills only its
  rooms. Other workers (and the router) keep running.
- The router supervises workers with `Isolate.addOnExitListener` and
  respawns dead workers automatically. Rooms hashed to the dead
  worker are gone and clients receive WS close; reconnect lands them
  on the fresh worker (with a new, empty room).
- The router does NOT supervise the rooms inside a worker — that is
  per-worker logic (close on idle, etc.).

## What's deliberately NOT in this patch

- **Live room migration** between workers.
- **Consistent hashing** so that adding a worker only rehashes
  `1/(N+1)` of rooms.
- **Cross-worker presence** (a participant in worker 0 cannot see a
  participant in worker 1 — they're different rooms by definition).
  That's the whole point of room-based sharding; cross-room
  conferencing requires a full mesh of inter-worker SFUs which is a
  different architecture.
- **Authentication / per-tenant isolation**.
- **Metrics export** (Prometheus/StatsD). The aggregated `/health`
  endpoint is the only observability surface.

## File layout

| File | Role |
|------|------|
| `lib/basic_sfu.dart` | Single-room SFU (unchanged contract). |
| `lib/sfu_server.dart` | Single-room HTTP+WS signaling stack (unchanged). |
| `lib/room_worker.dart` | Multi-room signaling stack that runs **inside** a worker isolate. Uses `BasicSfu` directly; one map per isolate. |
| `lib/multi_room_server.dart` | Main-isolate router. Spawns N worker isolates, routes `/room/:id/locate` to the right worker port. |
| `bin/multi_room_server.dart` | CLI entry point. |
