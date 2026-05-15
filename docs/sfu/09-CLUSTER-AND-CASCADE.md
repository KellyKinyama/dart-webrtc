# 9. Cluster and cascade

A single Dart isolate is one CPU core. To scale beyond that you
need to either (a) shard sessions across isolates within one
process, or (b) cascade across processes / machines. This SFU does
both.

> Skip this chapter if you only run one process and one room. The
> default single-isolate path covers thousands of packets per
> second on modern hardware.

---

## 9.1. Two orthogonal axes

| Axis | Mechanism | When you need it |
|---|---|---|
| **Sharding** (within process) | One `SessionShard` worker isolate per session | Multiple rooms on one box; isolates avoid GC and CPU contention |
| **Cascading** (across processes / hosts) | UDP relay between SFU instances | Geographic distribution; failure isolation; >1 box of capacity |

You can use either, or both. The owner of a session is determined
by a `RoomLocator` which can implement any consistent-hashing
strategy.

---

## 9.2. Sharding: `ShardedSfu` and `SessionShard`

Files:
* [`lib/src/sharded_sfu.dart`](../../example/ion_style_sfu/lib/src/sharded_sfu.dart)
* [`lib/src/session_shard.dart`](../../example/ion_style_sfu/lib/src/session_shard.dart)

```dart
class ShardedSfu {
  ShardedSfu(ShardConfigTemplate template);

  Future<SessionShard> getOrCreate(String sessionId);
  void Function(String sessionId, ShardEvent ev)? onEvent;
  void Function(String sessionId)? onShardClosed;
  void Function(String sessionId, SessionShard)? onShardCreated;
  Future<void> close();
}
```

Lifecycle:

1. WebSocket arrives for `/ws/room1`.
2. `_SessionRouter` calls `sharded.getOrCreate('room1')`.
3. If a shard exists, return its handle. Else:
    * Build a `ShardConfig` from the template (allocate a disjoint
      RTP port range — `rtpBasePort + slot * portsPerShard`).
    * `Isolate.spawn(SessionShard.entrypoint, config)`.
    * Wait for the worker's "ready" message (it sets up its own
      `Sfu` instance and SendPort).
    * Insert into `_shards` and return the handle.
4. Subsequent WS frames RPC the worker via SendPort.

Each shard owns:

* Its own `Sfu` (one Session, since each shard is a single room).
* Its own range of UDP ports.
* Its own `Logger` (sharing stdout/stderr with the parent).

When the session's last peer leaves, the worker idle-times-out and
sends a `closed` message back. `ShardedSfu` removes the shard and
fires `onShardClosed`.

### Why isolate-per-session?

Dart isolates have separate heaps, so:

* GC pauses in one room don't affect another.
* CPU work in one room can scale to multiple cores trivially.
* A bug or panic in one room isolates the blast radius.

The downside is that messages between isolates are copied (or sent
via `TransferableTypedData` for `Uint8List`). The signalling layer
sends only JSON-serialisable things across the boundary, so the
hot path (RTP/RTCP) never crosses an isolate boundary.

---

## 9.3. Cascade — when one SFU isn't enough

Suppose you have three SFU nodes (`sfu-eu`, `sfu-us`, `sfu-asia`)
and a room `room1` is *owned* by `sfu-eu`. A client in Asia connects
to `sfu-asia` (better RTT) but wants to participate in `room1`.

Two options:

* **Tunnel the client** to `sfu-eu`: bad RTT, bad UX.
* **Cascade**: `sfu-asia` accepts the client, then relays the
  client's RTP to `sfu-eu`, and relays `sfu-eu`'s output back to
  the client.

This SFU implements option 2 over **UDP unicast between SFU nodes**.

### Components

| File | Class | Role |
|---|---|---|
| [`cluster/locator.dart`](../../example/ion_style_sfu/lib/src/cluster/locator.dart) | `RoomLocator` | "Who owns sessionId?" — defaults to consistent hash on `(peers, sid)` |
| [`cluster/udp_relay_transport.dart`](../../example/ion_style_sfu/lib/src/cluster/udp_relay_transport.dart) | `UdpRelayHub` | One UDP socket per node carrying inter-SFU traffic; framing + optional HMAC |
| [`cluster/cluster_coordinator.dart`](../../example/ion_style_sfu/lib/src/cluster/cluster_coordinator.dart) | `ClusterCoordinator` | Glue: routes shard `CascadeOutboundEvent`s into the hub; routes hub-inbound traffic into the right shard |
| [`relay/relay.dart`](../../example/ion_style_sfu/lib/src/relay/relay.dart) | `RelayPeer`, `RelayStreamDescriptor` | The "remote half" of a peer that's actually somewhere else |
| [`cascade_event.dart`](../../example/ion_style_sfu/lib/src/cascade_event.dart) | `CascadeRelayKind`, `CascadeBridgeRole` | Enums for routing: `control` / `rtp` / `rtcp`; `outbound` / `inbound` |

### Wire framing

Every UDP datagram between SFUs has a small framing header:

```
+--+--+--+--+----+----+--------------------+
|magic|ver|kind|brId|sid|... payload ...   |
+--+--+--+--+----+----+--------------------+
```

* `magic` — 4 bytes, identifies relay traffic vs random UDP noise.
* `kind` — control (handshake / hello / bye / ping), rtp, or rtcp.
* `brId` — bridge id; one per (sessionId, sourcePeerId) pair.
* `sid` — session id (string, length-prefixed in control frames).
* If a `relaySecret` was configured, the trailer carries
  HMAC-SHA256 over the rest. Frames with bad HMAC are dropped.

### Bridge lifecycle

1. **Discovery**: `sfu-asia` receives a `join` for `room1`. The
   locator says `room1` is owned by `sfu-eu`. The shard is started
   with `upstreamSfuId=sfu-eu, upstreamHost=...`.
2. **Hello**: shard emits `cascade-hello` (control frame). The
   coordinator forwards via the UDP hub to `sfu-eu`.
3. **Owner accepts**: `sfu-eu`'s coordinator routes the hello to
   the right session shard, which marks the bridge "established"
   and replies with `cascade-hello-ack`.
4. **Media**: `sfu-asia`'s shard taps every Receiver and emits
   `CascadeOutboundEvent(kind: rtp, ssrc, rtp)`. Coordinator → hub
   → `sfu-eu`. `sfu-eu`'s coordinator routes inbound rtp to the
   shard, which calls a `RelayPeer.deliverRtp(rtp)` that *acts
   like a Publisher* — feeding the `room1` Router exactly as if
   the client were local.
5. **Reverse direction**: when `sfu-eu`'s `room1` has a new
   producer, the bridge to `sfu-asia` gets DownTracks added that
   pump into the bridge instead of a real Subscriber's transport.
6. **Liveness**: every `bridgeKeepaliveMs` (typically 5–10 s),
   the established bridge emits a relay-level ping. The receiving
   end resets its idle timer. If no traffic (data or ping) for
   `bridgeIdleTimeoutMs` (e.g. 30 s), the bridge is torn down and
   the coordinator emits a `bridgeClosed` event.

### Reconnect logic

If a bridge dies (transient packet loss, brief network outage),
the coordinator's `_attemptUpstreamReconnect` re-establishes it
with exponential back-off. Capped at
`upstreamReconnectMaxAttempts` (null = retry forever, the default).

---

## 9.4. The locator

```dart
abstract class RoomLocator {
  ClusterPeer ownerOf(String sessionId);
}
```

The default implementation is a **rendezvous-hash** (HRW) over the
configured cluster peers:

```dart
class HrwRoomLocator implements RoomLocator {
  final List<ClusterPeer> peers;
  ClusterPeer ownerOf(String sid) {
    var bestScore = -1;
    ClusterPeer? best;
    for (final p in peers) {
      final score = _hash(p.id + ':' + sid);
      if (score > bestScore) { bestScore = score; best = p; }
    }
    return best!;
  }
}
```

Properties:

* **Stable**: removing or adding a peer reshuffles only ~1/N of
  sessions, not all of them.
* **Stateless**: every node computes the same answer without
  coordination.
* **No quorum**: if a peer is partitioned, traffic to its sessions
  fails — there's no automatic failover. Add monitoring around the
  hub for this.

You can swap in a custom `RoomLocator` (e.g. one that respects
geographic affinity or operator overrides) by passing it to
`runIonStyleSfuServer`.

---

## 9.5. Shard config knobs that matter for cluster mode

From `ShardConfig`:

| Field | Purpose |
|---|---|
| `selfSfuId` | This node's id (must match a `peers` entry) |
| `upstreamSfuId` / `upstreamHost` / `upstreamPort` | Set when this node is *not* the owner of the session — points at who is |
| `bridgeIdleTimeoutMs` | When to consider a silent bridge dead |
| `bridgeKeepaliveMs` | How often to ping (must be < idle / 2) |
| `upstreamReconnectMaxAttempts` | Cap on retries before giving up |

---

## 9.6. Failure modes

* **Owner unreachable**: clients connecting to a non-owner can't
  participate (their bridge fails to establish). Fix: monitor
  hub-level connectivity; rotate ownership via a control plane.
* **Asymmetric NAT between SFUs**: every SFU node must be
  reachable on its `relay-port` from every other. Cascade does not
  do STUN/TURN between SFUs — they're assumed to live in
  reachable network space.
* **Bridge thrashing**: if `bridgeIdleTimeoutMs` is too low and
  media is paused (e.g. audio-only meeting where everyone's
  muted), the bridge gets torn down and rebuilt. Pair with
  `bridgeKeepaliveMs < idle/2`.
* **HMAC mismatch**: if `relaySecret` differs across nodes, every
  packet is silently dropped. There's no "wrong key" log; check
  the relay drops counter on `/stats`.

---

## 9.7. Operating the cluster

A small example: three nodes, all peers, EU owns most sessions:

```pwsh
# on sfu-eu (10.0.1.10)
dart run bin/sfu_server.dart --self-id sfu-eu --relay-port 9091 `
  --peers "sfu-eu@10.0.1.10:9091,sfu-us@10.0.2.10:9091,sfu-asia@10.0.3.10:9091" `
  --relay-secret "shared-hmac-secret"

# on sfu-us (10.0.2.10) — same flags, change --self-id
# on sfu-asia (10.0.3.10) — same flags, change --self-id
```

Now any client can connect to any node; they'll be relayed to the
session's owner transparently.

---

Next: [Chapter 10 — Observability and testing](./10-OBSERVABILITY-AND-TESTING.md).
