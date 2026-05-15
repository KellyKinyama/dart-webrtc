# 10. Observability and testing

The last chapter. How to look inside the running SFU, and how to
break it on purpose.

---

## 10.1. Endpoints

[`runIonStyleSfuServer`](../../example/ion_style_sfu/lib/src/sfu_server.dart)
exposes three HTTP endpoints alongside `/ws/<sid>`:

| Path | Returns | Use case |
|---|---|---|
| `GET /healthz` | 200 OK / 503 (while draining) | Load balancer health probe |
| `GET /stats` | JSON snapshot of `SfuStatsSnapshot` | Ops dashboard, debugging |
| `GET /metrics` | Prometheus text exposition | Scrape into Prometheus / Grafana |

`/stats` and `/metrics` aggregate **across all shards** — the main
isolate RPCs each `SessionShard`, then merges the results.

---

## 10.2. The stats snapshot

File: [`lib/src/stats/stats.dart`](../../example/ion_style_sfu/lib/src/stats/stats.dart).

```dart
class SfuStatsSnapshot {
  int sessions, peers, routers, downTracks;
  int totalBytesForwarded, totalPacketsForwarded;
  List<DownTrackStats> tracks;
  List<SubscriberBweStats> subscriberBwe;
}

class DownTrackStats {
  String trackId, sessionId, peerId, kind, trackType, currentLayer;
  int layerSwitches, packetsForwarded, bytesForwarded;
  int packetsDroppedWrongLayer, packetsTwccStamped;
  int nackRetransmits, nackUpstreamRequested;
  double publisherJitterMs;
  int publisherPacketsReceived, publisherPacketsLost;
}

class SubscriberBweStats {
  String sessionId, peerId;
  int currentBps;
}
```

The most useful counters in production:

* `nackRetransmits` vs `nackUpstreamRequested` — how often the
  local cache satisfies a subscriber's NACK. If
  `upstreamRequested >> retransmits`, your jitter buffer is too
  small.
* `packetsDroppedWrongLayer` — how often a layer switch waited for
  a keyframe. Spikes here mean your encoder isn't emitting
  keyframes on PLI, or your hysteresis is too aggressive.
* `layerSwitches / minute` — should be steady, not flappy. If
  >5/min for a single subscriber on a stable link, tighten BWE
  hysteresis.
* `currentBps` per subscriber — the headline. Plot over time.
* `publisherJitterMs` — if it spikes, the *publisher* is having
  network issues, not the subscriber.

---

## 10.3. Prometheus format

`formatPrometheus(snapshot)` renders:

```text
# HELP sfu_sessions Number of active sessions
# TYPE sfu_sessions gauge
sfu_sessions 12

# HELP sfu_peers Number of active peers across all sessions
# TYPE sfu_peers gauge
sfu_peers 47

# HELP sfu_downtrack_packets_forwarded_total Packets forwarded by a DownTrack
# TYPE sfu_downtrack_packets_forwarded_total counter
sfu_downtrack_packets_forwarded_total{session="r1",peer="alice",track="bob:0",kind="video",rid="h"} 12345
...

# HELP sfu_subscriber_bwe_bps Current bandwidth estimate per subscriber
# TYPE sfu_subscriber_bwe_bps gauge
sfu_subscriber_bwe_bps{session="r1",peer="alice"} 1500000
```

Standard Prometheus scrape configuration applies — the endpoint is
unauthenticated by default; put it behind your reverse proxy if
you want auth.

---

## 10.4. The audio observer

File: [`lib/src/audio_observer.dart`](../../example/ion_style_sfu/lib/src/audio_observer.dart).

```dart
class AudioObserver {
  AudioObserver({
    Duration interval = const Duration(seconds: 1),
    int threshold = 40,        // dBoV floor for "active"
    int filter = 3,             // top-K speakers to surface
    double smoothing = 0.5,     // EMA factor
  });

  Stream<AudioObserverEvent> get events;
  void deliverAudioLevel(String trackId, int level, bool voice);
  void start(); void stop(); void forget(String trackId);
}

class AudioObserverEvent {
  List<String> speakers;   // trackIds, loudest first
  List<double> scores;     // matched EMA loudness
}
```

How it works:

1. Every `Receiver` for an audio track parses the RFC 6464
   `audio-level` extension (negotiated in SDP) on every RTP packet
   and calls `audioObserver.deliverAudioLevel(trackId, level,
   voice)`.
2. The observer maintains an EMA of `level` per track.
3. Every `interval`, it takes the top-K tracks (where `score >
   threshold`) and emits an `AudioObserverEvent`.

Applications consume `audioObserver.events` to drive UI like
"highlight the active speaker" or to make video-routing decisions
("stop sending muted speakers' video at full layer").

---

## 10.5. Cascade events for ops

File: [`lib/src/cascade_event.dart`](../../example/ion_style_sfu/lib/src/cascade_event.dart).

When cluster mode is on, every shard emits `CascadeBridgeEvent`s
back to the main isolate via the `onEvent` callback:

* `bridgeOpened(sessionId, peerSfuId, role)`
* `bridgeClosed(sessionId, peerSfuId, role, reason)`
* `relayDropped(sessionId, count, reason)`

Wire these to your alerting: a healthy cluster sees `bridgeClosed`
only on graceful "bye"; sudden bursts of `idle-timeout` or
`hmac-mismatch` mean trouble.

---

## 10.6. The load test

Files:
* CLI: [`bin/load_test.dart`](../../example/ion_style_sfu/bin/load_test.dart)
* Harness: [`lib/src/load_test.dart`](../../example/ion_style_sfu/lib/src/load_test.dart)

```dart
class LoadTestConfig {
  int rooms;
  int publishersPerRoom;
  int subscribersPerPublisher;
  int packetsPerSecondPerPublisher;
  int payloadBytes;
  Duration duration;
  Duration warmup;
  int jitterCapacity;
  bool usePool;
}

class LoadTestReport {
  double packetsPerSecond, bytesPerSecond;
  double latencyP50Ms, latencyP95Ms, latencyP99Ms;
  int poolAllocations, poolReleases;
  double avgPoolSize;
  String renderHuman();
  Map<String, Object?> toJson();
}
```

Runs the **engine** without networking — synthetic RTP packets are
fed directly into the Receivers, fan-out runs in-isolate, output
is timestamped and measured.

Use cases:

* **Throughput baseline**: how many pkts/s a single shard can fan
  out at your hardware spec.
* **BytePool A/B**: `--use-pool` vs `--no-pool` tells you the
  allocation overhead.
* **Pacer overhead**: configure with/without pacer.
* **Jitter buffer sizing**: vary `--jitterCapacity` and watch
  memory.

Examples:

```pwsh
# 10 s smoke test: 1 room × 4 publishers × 3 subscribers × 30 pps
dart run bin/load_test.dart --rooms 1 --pubs 4 --subs 3 --pps 30 --duration 10s

# Saturate one core: many rooms, big payloads
dart run bin/load_test.dart --rooms 50 --pubs 2 --subs 5 --pps 50 `
  --payload 1200 --duration 30s

# Without the BytePool, to measure its impact
dart run bin/load_test.dart --rooms 10 --pubs 4 --subs 3 --pps 30 --no-pool

# JSON report for pipelines
dart run bin/load_test.dart --rooms 1 --pubs 4 --subs 3 --pps 30 --json
```

---

## 10.7. Useful debugging hooks

When something's wrong in production, in order of cheapness:

1. **`/stats` snapshot** — first stop. Look at counters per
   DownTrack; outliers tell you which subscriber is suffering.
2. **Log level** — bump `Logger` to `debug` (or replace with your
   own implementation when calling `runIonStyleSfuServer`).
3. **Per-shard isolation** — single-shard repro: point one
   misbehaving session at a dev SFU and replay traffic.
4. **`Receiver.deliverRtp` breakpoint** — break with a condition
   like `_packetsReceived % 1000 == 0` to sample.
5. **WebSocket frame log** — the simplest "what is the client
   actually saying" check; plumb a hook into `_ClientWs`.
6. **Wireshark on the loopback** — when DTLS / SRTP is suspect.
   Decrypt with the master keys logged from
   `Publisher`/`Subscriber` startup if you've enabled that flag.

---

## 10.8. Test suite layout

The `test/` folder of `example/ion_style_sfu/` covers each
subsystem in isolation:

* `audio_observer_test.dart` — EMA + top-K
* `bwe_test.dart` — TWCC slope, REMB cap, RR loss correction
* `down_track_test.dart` — rewriter integration, NACK loop
* `pacer_test.dart` — leaky-bucket budget arithmetic
* `nack_responder_test.dart` — cache hit / miss
* `simulcast_rewriter_test.dart` — two-phase switch
* `rtcp_rewrite_test.dart` — SR SSRC + ts shift
* `cluster_*_test.dart` — sharding, locator, cascade

A reasonable rule: never edit a subsystem without running
`dart test test/<subsystem>_test.dart` first.

---

## 10.9. What's still missing

Honest list of things this SFU doesn't have observability for yet:

* **Per-bridge byte counters in stats** (cluster mode). The
  `relayDropped` events are there but not aggregated.
* **Histogram metrics** (Prometheus). Everything's a gauge or
  counter; no `_bucket{}` histograms for latency.
* **Tracing**. No OpenTelemetry hooks. Add them at the WebSocket
  router and at `Router.routeRtp` for span propagation if you
  need request-level tracing.
* **Recording**. No write-to-disk path. The `play_from_disk` and
  `webrtc_to_hls` examples in the parent repo show how to add one.

---

## 10.10. End-of-tutorial checklist

If you've read all 11 chapters, you should be able to:

* Trace one RTP packet from `Publisher.transport` through to
  `Subscriber.transport.sendRtp`, naming every class it touches.
* Explain why the Sub PC is the offerer and the Pub PC is the
  answerer.
* Describe how the SFU rewrites SR's RTP timestamp during a
  simulcast layer switch and why.
* Write a 20-line script that constructs a NACK and parses it via
  `parseFeedback()`.
* Configure a 3-node cluster with HMAC-protected cascade.
* Read `/stats`, point at a specific counter, and explain what it
  means.

If any of those feels shaky, jump back to the relevant chapter —
each one is short and focuses on the *exact* file/method names so
you can read source side-by-side.

---

## 10.11. Where to go from here

* The protocol-stack tutorial: [`../dart/`](../dart/) — explains
  the layers *under* this SFU (STUN, ICE, DTLS, SRTP, RTP).
* The RTCP/SRTCP deep-dive: [`../dart/RTCP-AND-SRTCP.md`](../dart/RTCP-AND-SRTCP.md).
* The Go reference: [`../../example/ion-sfu/`](../../example/ion-sfu/) —
  ion-sfu's actual source. This Dart port mirrors its shape,
  divergences are noted in
  [`example/ion_style_sfu/README.md`](../../example/ion_style_sfu/README.md).

That's it. Go forward and forward selectively.
