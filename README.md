
# dart_webrtc

**dart_webrtc** (**We**b**r**TC **I**mplementation **f**or **T**he Dart language)

A pure Dart implementation of WebRTC, including support for ICE, STUN, TURN, DTLS, TLS, SRTP, RTP, RTCP, and SDP.

> Inspired by [webrtc-nuts-and-bolts](https://github.com/adalkiran/webrtc-nuts-and-bolts)

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
- Example usage in the `/example` directory

---

## 💡 Examples

GitHub: [examples](https://github.com/your-repo/webrtc_dart/tree/main/example)

### DTLS server

```bash
dart lib/src/dtls/examples/server/tls_ecdh_aes_128.dart
dart lib/src/dtls/examples/server/psk_ccm8.dart
dart lib/src/dtls/crypto/crypto_ccm.dart
```


View logs in console and browser at `chrome://webrtc-internals`.

### STUN Server

```bash
dart lib/src/stun3/stun_server5.dart
```



---

## 🎯 Roadmap

### ✅ Version 1.0 Goals

#### Signaling & NAT traversal

- [x] SIP
- [x] STUN
- [] TURN (UDP)

#### ICE

- [x] Vanilla ICE
- [x] Trickle ICE
- [] ICE Restart
- [x] ICE-Lite (Client-side)
- [ ] ICE-Lite (Server-side)

#### Security

- [x] DTLS
  - [x] DTLS-SRTP
  - [x] Curve25519
  - [x] P-256
- [ ] TLS 1.2

#### Channels

- [ ] DataChannel
- [ ] MediaChannel
  - [ ] sendonly
  - [ ] recvonly
  - [ ] sendrecv
  - [ ] Multi-track
  - [ ] RTX
  - [ ] RED

#### RTP/RTCP

- [ ] RFC 3550 (RTP base)
- [ ] RTP Payload Formats:
  - [ ] VP8
  - [ ] VP9
  - [ ] H264
  - [ ] AV1
  - [ ] RED (RFC 2198)
- [ ] RTCP:
  - [ ] SR/RR
  - [ ] PLI
  - [ ] REMB
  - [ ] NACK
  - [ ] TransportWideCC

#### SDP / PeerConnection

- [x] SDP parsing and generation
  - [x] Reuse inactive m-line
- [ ] PeerConnection API
- [ ] Simulcast (recv only)
- [ ] Bandwidth Estimation (sender-side)

#### Media Recorder

- [ ] OPUS
- [ ] VP8
- [ ] VP9
- [ ] H264
- [ ] AV1

#### Compatibility & Interop

- [ ] Chrome / Safari / Firefox
- [ ] Pion
- [ ] aiortc
- [ ] sipsorcery
- [ ] webrtc-rs
- [ ] Interop E2E testing

#### Testing

- [ ] Unit tests
- [ ] Web Platform Tests

---

### 🔜 Roadmap for 2.0

- [ ] API compatible with browser RTCPeerConnection
- [ ] Simulcast (send support)
- [ ] TURN over TCP
- [ ] `getStats()` support
- [ ] Support for more cipher suites

---

## 🔗 References

- [aiortc (Python)](https://github.com/aiortc/aiortc)
- [pion/webrtc (Go)](https://github.com/pion/webrtc)
- [sipsorcery (C#)](https://github.com/sipsorcery/sipsorcery)
- [webrtc-rs (Rust)](https://github.com/webrtc-rs/webrtc)
