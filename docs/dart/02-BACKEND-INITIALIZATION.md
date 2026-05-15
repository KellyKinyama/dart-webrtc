# **2. SERVER INITIALIZATION**

The entry-point of the SFU is `main()` in
[example/ion_style_sfu/bin/sfu_server.dart](../../example/ion_style_sfu/bin/sfu_server.dart).
Its job is to:

1. Parse the CLI flags.
2. Resolve the announced IP (the address the browser will dial).
3. Construct the **`Sfu`** engine (room registry).
4. Bind the HTTP / WebSocket signalling endpoint.
5. Install graceful-shutdown signal handlers and stay alive.

The Go original kept its main thread alive with `sync.WaitGroup`. In
Dart the main isolate is kept alive automatically by the open
`HttpServer` and the `SIGINT` watcher — there is no explicit wait
group.

## **2.1. The startup function**

`main()` is intentionally thin. All the orchestration lives in
**`runIonStyleSfuServer()`** in
[example/ion_style_sfu/lib/src/sfu_server.dart](../../example/ion_style_sfu/lib/src/sfu_server.dart):

```dart
Future<IonSfuServerHandle> runIonStyleSfuServer({
  String ip = '0.0.0.0',
  int port = 9090,
  int rtpBase = 51000,
  String? announceIp,
  Iterable<String> iceServerUrls = const [],
  // … many production knobs (cluster, drain, idle timeouts, auth) …
}) async { … }
```

It returns an `IonSfuServerHandle` (in the same file) that exposes
`drain()` and `close()` so tests and operators can shut it down
cleanly.

## **2.2. There is no global config file**

The Go server loaded `config.yaml` via Viper. The Dart server takes
**every** knob through CLI flags, parsed in
[bin/sfu_server.dart](../../example/ion_style_sfu/bin/sfu_server.dart).
This keeps the example self-contained; production deployments wrap
the same `runIonStyleSfuServer()` API and read whatever config they
prefer.

The flags that matter for the rest of this tutorial are:

| Flag | Default | Meaning |
|---|---|---|
| `--ip` | `0.0.0.0` | Bind address for HTTP and UDP |
| `--ws-port` | `9090` | WebSocket / signalling port |
| `--rtp-base` | `51000` | First UDP port; later peers get +1, +2… |
| `--announce-ip` | autodetect | The IP put into ICE host candidates |
| `--ice-server` | (none) | STUN URL for `srflx` candidate gathering |

## **2.3. DTLS certificate generation (no global init)**

The Go server eagerly generated a single P-256 ECDSA certificate at
boot time and reused it for the lifetime of the process. The Dart
implementation generates **one self-signed certificate per
`RTCPeerConnection`** when the connection is constructed — there is
no `dtls.Init()` step.

The certificate generation itself is in
[lib/src/dtls/cert_utils.dart](../../lib/src/dtls/cert_utils.dart):

* A random P-256 keypair is produced via the `EccKey` /
  `EllipticCurve` primitives in
  [lib/ecdsa.dart](../../lib/ecdsa.dart) and
  [lib/ecc.dart](../../lib/ecc.dart) (PointyCastle is used for the
  underlying `ECDSASigner`).
* A minimal X.509 certificate is built around the public key and
  self-signed.
* Its DER encoding is hashed with SHA-256, and the 32-byte digest is
  formatted as colon-separated hex pairs by helpers in
  [lib/signal/fingerprint.dart](../../lib/signal/fingerprint.dart).
  That fingerprint string is what eventually goes into the SDP
  `a=fingerprint:` line.

Why per-connection? Because every WebRTC connection in the spec is
independently authenticated. Sharing a certificate is an optimisation
the Go port chose; the Dart code prefers safety-by-default and the
cost of generating a fresh P-256 key in pure Dart is sub-millisecond.

## **2.4. There is no boot-time STUN discovery**

The Go server asked a public STUN server for its WAN IP at boot so it
could embed it as a host candidate. The Dart SFU does **not** do this.
Instead:

* Pure host candidates are gathered from the bind address and any
  network interfaces (see
  [lib/src/ice/ice2.dart](../../lib/src/ice/ice2.dart)).
* If you want a server-reflexive (`srflx`) candidate, pass one or
  more `--ice-server stun:…` flags. Each `RTCPeerConnection` then
  performs its own STUN binding request from its own UDP socket —
  that's what the STUN client code in
  [lib/src/stun/stun_server.dart](../../lib/src/stun/stun_server.dart)
  is for.

The `--announce-ip` flag is the explicit override for the case where
the bind address (`0.0.0.0`) and the reachable address (your LAN IP,
or a NAT'd public IP) differ.

## **2.5. The `Sfu` engine and `Session` registry**

[example/ion_style_sfu/lib/src/sfu.dart](../../example/ion_style_sfu/lib/src/sfu.dart)
defines the top-level **`Sfu`** class. In production it is wrapped by
`ShardedSfu` (also in the same package) so heavy sessions can be
isolated to dedicated worker isolates, but conceptually `Sfu` is just:

```text
Sfu
 └─ Map<String roomId, Session>
        └─ List<Peer>          ← (Publisher PC, Subscriber PC) pair
              ├─ Publisher     ← inbound RTP from the browser
              └─ Subscriber    ← outbound RTP to the browser
```

* [`Session`](../../example/ion_style_sfu/lib/src/session.dart) is the
  room. It owns the peer list and the per-publisher
  [`Router`](../../example/ion_style_sfu/lib/src/router.dart) hubs.
* [`Peer`](../../example/ion_style_sfu/lib/src/peer.dart) is one
  participant. It holds two `RTCPeerConnection`s.
* [`Publisher`](../../example/ion_style_sfu/lib/src/publisher.dart) and
  [`Subscriber`](../../example/ion_style_sfu/lib/src/subscriber.dart)
  are the inbound/outbound halves of the SFU pattern.

Nothing in `Sfu` runs on a background thread the way the Go
`ConferenceManager.Run()` did. Dart is single-threaded per isolate —
incoming WebSocket frames and inbound UDP packets feed into the same
event loop, and Dart's `async`/`await` keeps the code linear.

## **2.6. UDP listener — per-peer, not global**

The Go server bound **one** UDP socket on port `15000` and
demultiplexed by ICE ufrag. The Dart SFU does the opposite: every
`RTCPeerConnection` (on either side of a peer) gets its **own**
[`RtcUdpTransport`](../../lib/webrtc/rtc_udp_transport.dart) bound to
a unique port starting at `--rtp-base`.

The advantages:

* No global ufrag table.
* Each socket already knows which `DtlsSession` and `SRTPContext`
  the bytes belong to.
* The OS does the demultiplexing for us by destination port.

The cost is one UDP port per peer-connection. With thousands of
participants you'd want to switch to the single-port model; the Dart
codebase is structured so that swap is local to `RtcUdpTransport`.

The same `RtcUdpTransport` is responsible for routing packets by
protocol once they arrive — STUN, DTLS, SRTP, SRTCP. We'll meet it
again in chapters 4–7.

## **2.7. Signalling HTTP / WebSocket server**

Inside `runIonStyleSfuServer()`:

```dart
final http = await HttpServer.bind(bindAddr, port);
http.listen((req) {
  // CORS, then route /ws/<sessionId> through WebSocketTransformer.upgrade
});
```

That single `dart:io` `HttpServer` is the entire signalling surface.
Each WebSocket connection is owned by a `_SessionRouter` (also in
[sfu_server.dart](../../example/ion_style_sfu/lib/src/sfu_server.dart))
that maps a peer's `uid` to its `WebSocket` so events emitted by the
shard worker (`onEvent`) can be dispatched to the right client.

The wire format is JSON, documented in detail in chapter 3.

## **2.8. Graceful shutdown**

```dart
ProcessSignal.sigint.watch().listen(shutdown);
if (!Platform.isWindows) {
  ProcessSignal.sigterm.watch().listen(shutdown);
}
```

`shutdown()` calls `IonSfuServerHandle.close()`, which closes the
HTTP server, drains all sessions, and quiesces every `Sfu` worker.
That's the Dart equivalent of "wait for `waitGroup` to reach zero".

---

After this point the SFU is idle:

* WebSocket signalling is up on `--ws-port`.
* No UDP socket is open yet — they're created lazily, one per
  `RTCPeerConnection`, the moment a peer joins.

Now we wait for the first browser to dial in.

<br>

---

<div align="right">

[&lt;&nbsp;&nbsp;Previous chapter: RUNNING IN DEVELOPMENT MODE](./01-RUNNING-IN-DEV-MODE.md)&nbsp;&nbsp;|&nbsp;&nbsp;[Next chapter: FIRST CLIENT COMES IN&nbsp;&nbsp;&gt;](./03-FIRST-CLIENT-COMES-IN.md)

</div>
