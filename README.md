
# dart_webrtc

**dart_webrtc** (**We**b**r**TC **I**mplementation **f**or **T**he Dart language)

A pure Dart implementation of WebRTC, including support for ICE, STUN, TURN, DTLS, TLS, SRTP, RTP, RTCP, and SDP.

> Inspired by [werift-webrtc (Node.js)](https://github.com/adalkiran/webrtc-nuts-and-bolts)

---

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  dart_webrtc: ^0.1.0 # Replace with the latest version
```

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

### MediaChannel

```bash
dart run example/media_channel.dart
```

Open in browser:

```
http://localhost:8080/mediachannel
```

View logs in console and browser at `chrome://webrtc-internals`.

### DataChannel

```bash
dart run example/data_channel.dart
```

Open:

```
http://localhost:8080/datachannel
```

---

## 🎯 Roadmap

### ✅ Version 1.0 Goals

#### Signaling & NAT traversal

- [x] STUN
- [x] TURN (UDP)

#### ICE

- [x] Vanilla ICE
- [x] Trickle ICE
- [x] ICE Restart
- [x] ICE-Lite (Client-side)
- [ ] ICE-Lite (Server-side)

#### Security

- [x] DTLS
  - [x] DTLS-SRTP
  - [x] Curve25519
  - [x] P-256
- [x] TLS 1.2

#### Channels

- [x] DataChannel
- [x] MediaChannel
  - [x] sendonly
  - [x] recvonly
  - [x] sendrecv
  - [x] Multi-track
  - [x] RTX
  - [x] RED

#### RTP/RTCP

- [x] RFC 3550 (RTP base)
- [x] RTP Payload Formats:
  - [x] VP8
  - [x] VP9
  - [x] H264
  - [x] AV1
  - [x] RED (RFC 2198)
- [x] RTCP:
  - [x] SR/RR
  - [x] PLI
  - [x] REMB
  - [x] NACK
  - [x] TransportWideCC

#### SDP / PeerConnection

- [x] SDP parsing and generation
  - [x] Reuse inactive m-line
- [x] PeerConnection API
- [x] Simulcast (recv only)
- [x] Bandwidth Estimation (sender-side)

#### Media Recorder

- [x] OPUS
- [x] VP8
- [x] VP9
- [x] H264
- [x] AV1

#### Compatibility & Interop

- [x] Chrome / Safari / Firefox
- [x] Pion
- [x] aiortc
- [x] sipsorcery
- [x] webrtc-rs
- [x] Interop E2E testing

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
