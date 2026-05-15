
# dart_webrtc

**dart_webrtc** (**We**b**r**TC **I**mplementation **f**or **T**he Dart language)

A pure Dart implementation of WebRTC — ICE, STUN, TURN, DTLS, TLS, SRTP, RTP, RTCP, SDP — with **no native dependencies**. Includes a full ion-style SFU (`example/ion_style_sfu/`) with sharding, clustering, simulcast, TWCC/REMB, NACK/RTX, audio observer, and Prometheus stats.

> Inspired by [webrtc-nuts-and-bolts](https://github.com/adalkiran/webrtc-nuts-and-bolts)

---

## ✨ Highlights

- **Pure Dart** end-to-end stack — no libwebrtc / libsrtp / libnice. Easy to embed and audit.
- **Ion-style SFU** with isolate-based sharding, cluster coordinator, UDP relay transport, leaky-bucket pacer, BWE, jitter buffer, simulcast layer rewriter, and audio-level observer.
- **516 unit tests** in the SFU package, **93–100 % line coverage** across major files.
- **VP8 / VP9 / Opus / PCMA / PCMU**, RTX (RFC 4588), NACK, PLI, FIR, REMB, TWCC, audio level (RFC 6464), playout-delay codec.
- Built-in **load-test harness** and synthetic loss simulator.
- Prometheus metrics + JSON `/stats` endpoint.

---

## 📦 Installation

clone the repo


Then run:

```bash
dart pub get
```

Requires Dart 3.x or later.

---

## 📚 Documentation (WIP)

- [API Reference](https://pub.dev/documentation/webrtc_dart/latest/)
- Example usage in the `/bin` directory

---

## 💡 Examples

GitHub: [examples](https://github.com/KellyKinyama/dart-webrtc/tree/master/example)

### Ion-style SFU server

```bash
dart run example/ion_style_sfu/bin/sfu_server.dart \
  --ip 0.0.0.0 \
  --ws-port 9091 \
  --rtp-base 51000 \
  --announce-ip <your-public-ip> \
  --ice-server stun:stun.l.google.com:19302
```

Browser demo client:

```bash
cd example/ion_style_sfu/web
python -m http.server 8000 --bind 0.0.0.0
# open http://localhost:8000/meet.html
```

Run the SFU test suite:

```bash
cd example/ion_style_sfu
dart test
```



### DTLS server

```bash
dart bin/srtp_webrtc.dart
dart bin/dart_webrtc.dart
dart lib/src/dtls/examples/server/psk_ccm8.dart
dart lib/src/dtls/examples/server/psk_ccm.dart
```


### SRTP/DTLS server

```bash
dart bin/srtp_webrtc.dart
```


### DTLS client

```bash
dart lib/src/dtls3/handshaker/client/dtls_client.dart
```



### STUN Server

```bash
dart lib/src/stun3/stun_server7.dart
```



### STUN client

```bash
dart lib/src/stun3/stun_client.dart
```



---

### STUN/DTLS/SRTP/RTCP multiplexing 

This example recieves stun, dtls, rtp packets. It decrypts, encrypts and sends the packets back to the sender.
copy the sdp offer from this file:

lib\src\sdp8\sdp_test.dart

Adjust the the fingerprint and ice candidate

```bash
cd WebRTC-Simple-SDP-Handshake-Demo
php -S localhost:3000
```
Navigate to the link in your browser=> localhost:3000
Paste the sdp in the sdp offer box

Run this command
```bash
dart bin\srtp_webrtc.dart
```

In your browser, click create answer



---



## 🎯 Roadmap

### ✅ Shipped

#### Signaling & NAT traversal
- [x] STUN (client + server)
- [x] SIP
- [ ] TURN (UDP)

#### ICE
- [x] Vanilla ICE
- [x] Trickle ICE
- [x] ICE-Lite (client + server)
- [ ] ICE Restart

#### Security
- [x] DTLS 1.2 + DTLS-SRTP
  - [x] Curve25519, P-256
  - [x] PSK (CCM, CCM-8)
- [ ] TLS 1.2

#### RTP / RTCP
- [x] RFC 3550 RTP base + header extensions (audio level, playout delay, abs-send-time, TWCC)
- [x] Payload formats: VP8, VP9, Opus, PCMA, PCMU
- [x] RTX (RFC 4588), RED scaffolding
- [x] RTCP: SR/RR, NACK, PLI, FIR, REMB, TWCC
- [ ] H264, AV1, SVC

#### SDP / PeerConnection
- [x] SDP parsing + generation, m-line reuse
- [x] PeerConnection API
- [x] Simulcast (RID + SIM SSRC group, recv + forward)
- [x] Bandwidth estimation (sender-side TWCC + REMB)

#### SFU (`example/ion_style_sfu/`)
- [x] Session / Peer / Publisher / Subscriber / Router / Receiver / DownTrack
- [x] Isolate-based session sharding (`SessionShard`, `ShardedSfu`)
- [x] Cluster coordinator + UDP relay transport (cascade between SFUs)
- [x] Audio observer (RFC 6464) + audio-level forwarding policy
- [x] Leaky-bucket pacer, byte budget, NACK buffer, RTCP rewrite
- [x] Synthetic loss simulator + load-test harness
- [x] Prometheus stats + JSON snapshot, `/streams` aggregator (Phase B11)
- [x] WebSocket signalling server (`runIonStyleSfuServer`)
- [x] Multi-room cluster snapshot rehydration

#### Compatibility
- [x] Chrome / Edge / Firefox
- [x] webrtc-rs interop
- [ ] Pion / aiortc / sipsorcery interop suite

---

### 🔜 Roadmap

- [ ] VP9 SVC layer selector
- [ ] H264 forwarding
- [ ] Insertable streams / SFrame (E2EE)
- [ ] Recording (OPUS / VP8 / VP9)
- [ ] Published throughput benchmarks + Helm chart
- [ ] DataChannel (SCTP)
- [ ] TURN (UDP + TCP)
- [ ] `getStats()` browser-compatible API
- [ ] ICE Restart

---

## 🔗 References

- [aiortc (Python)](https://github.com/aiortc/aiortc)
- [pion/webrtc (Go)](https://github.com/pion/webrtc)
- [sipsorcery (C#)](https://github.com/sipsorcery/sipsorcery)
- [webrtc-rs (Rust)](https://github.com/webrtc-rs/webrtc)
