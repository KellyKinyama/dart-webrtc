# **4. STUN BINDING REQUEST FROM CLIENT**

We left the previous chapter with a freshly-bound publisher PC on the
SFU side, an `ice-ufrag`/`ice-pwd` exchanged through SDP, and the
client busy probing host candidates. The first packet that arrives on
the SFU's UDP socket is a **STUN binding request** carrying the local
end of a candidate pair.

> Note: a full primer on STUN message structure (header, magic
> cookie, transaction id, attributes, MESSAGE-INTEGRITY HMAC,
> FINGERPRINT CRC32) lives in the Go-original chapter
> [../02-BACKEND-INITIALIZATION.md §2.4.2](../02-BACKEND-INITIALIZATION.md).
> The Dart implementation in
> [lib/src/stun/stun_server.dart](../../lib/src/stun/stun_server.dart)
> follows the same RFC 5389 / 8489 layout.

## **4.1. UDP demultiplexing**

In the Dart implementation, the demultiplexer is
[`RtcUdpTransport`](../../lib/webrtc/rtc_udp_transport.dart). One
instance is created per `RTCPeerConnection`, bound to a port from the
`--rtp-base` pool. Its `_handleDatagram()` method classifies each
inbound packet by its first bytes:

```dart
// (inside RtcUdpTransport._handleDatagram, summarised)
if (StunMessage.isStunMessage(data))   { /* STUN  */ … }
if (isDtlsPacket(data, 0, data.length)) { /* DTLS  */ … }
if (isRtcpPacket(data))                { /* SRTCP */ … }
if (isRtpPacket(data))                 { /* SRTP  */ … }
```

The classification helpers are deliberately cheap — each one looks at
two or three bytes. Their definitions:

* `StunMessage.isStunMessage(buf)` — checks length ≥ 20 and that
  bytes 4–7 equal the STUN magic cookie `0x2112A442`. Lives in
  [lib/src/stun/stun_server.dart](../../lib/src/stun/stun_server.dart).
* `isDtlsPacket(buf, off, len)` — first byte (the DTLS record's
  `ContentType`) is in `[20, 63]`. Lives in
  [lib/src/dtls/dtls_message.dart](../../lib/src/dtls/dtls_message.dart).
* `isRtpPacket(buf)` / `isRtcpPacket(buf)` — both check that bits 0–1
  of byte 0 are `10` (RTP version 2) and use the RFC 5761 PT range
  trick (RTCP payload types live in 64–95) to disambiguate. Defined
  at the top of
  [lib/webrtc/rtc_udp_transport.dart](../../lib/webrtc/rtc_udp_transport.dart).

There is no per-packet `if/else` chain spread across the codebase;
the only demultiplexer in the SFU is this one method.

## **4.2. Lazy peer creation — and why STUN gets there first**

The Go server pre-allocated a `UDPClientSocket` for each `(serverUfrag,
clientUfrag)` pair as soon as the SDP offer was processed. The Dart
SFU is more cautious:

```dart
// _handleDatagram, paraphrased
var peer = _peers[key];   // (host, port) → RtcPeerTransport

if (StunMessage.isStunMessage(data)) {
  // … decode + verify MESSAGE-INTEGRITY …
  if (peer == null && _peers.length < _maxPeers) {
    peer = _peers.putIfAbsent(key,
      () => _newPeer(dg.address, dg.port, discoveryMethod: 'prflx'));
  }
  StunServer.handleDatagram(/* … */, requireMessageIntegrity: true);
  _applyIceAttributes(parsed, peer);
  return;
}
```

The interesting bits:

* **MESSAGE-INTEGRITY is checked *before* any per-peer state is
  allocated.** A forged-source-port flood that sends bare STUN
  packets cannot exhaust `_maxPeers`.
* The new peer is tagged `discoveryMethod: 'prflx'` (peer-reflexive,
  RFC 8445 §7.3). When a packet arrives from a transport address we
  did not see in the SDP, that's by definition a peer-reflexive
  candidate.
* DTLS packets *can* legitimately arrive before the first STUN check
  in raw-DTLS / non-ICE flows, so DTLS is allowed to create a peer
  too. RTP/RTCP without a prior STUN/DTLS check-in is dropped — there
  is no key context to decrypt them anyway.

## **4.3. Validating the binding request**

Once classified as STUN, the request goes through:

1. **Pre-decode** via `StunMessage.decode(data)` —
   [lib/src/stun/stun_server.dart](../../lib/src/stun/stun_server.dart).
   Throws on malformed packets; we drop those silently.
2. **MESSAGE-INTEGRITY validation** via
   `parsed.validateAsResponse(passwordForIntegrity: _stunPassword)`,
   which rebuilds the HMAC-SHA1 over the message bytes (with the
   length adjusted to exclude FINGERPRINT) and compares it to the
   attribute value. The password is the *local* `ice-pwd` from the
   server-side SDP — the client signed the request with it.
3. **FINGERPRINT (CRC32) check** done as part of the same validation
   pass.

If either check fails the packet is dropped without sending an error
response. This matches RFC 8445 §7.3.1.1.

## **4.4. ICE attributes that change agent behaviour**

After validation the server inspects three optional STUN attributes
that the browser may attach to the binding request. They drive ICE
state transitions; see `_applyIceAttributes()` in
[rtc_udp_transport.dart](../../lib/webrtc/rtc_udp_transport.dart):

* `USE-CANDIDATE` — RFC 8445 §7.1.3.2.4. The controlling agent (the
  browser; the SFU is the controlled side for the publisher PC)
  marks the pair it has nominated. Receiving this on a valid request
  promotes the pair to **nominated** and the SFU's
  `iceConnectionState` flips toward `connected`.
* `PRIORITY` — recorded for stats / pair ranking.
* `ICE-CONTROLLING` / `ICE-CONTROLLED` — used to detect role
  conflicts (RFC 8445 §7.3.1.1) which would lead to a tie-break.

## **4.5. Sending the binding response**

The actual response is built by `StunServer.handleDatagram(...)`,
also in [stun_server.dart](../../lib/src/stun/stun_server.dart). It:

* Echoes the transaction ID.
* Sets the `XOR-MAPPED-ADDRESS` attribute to the source `(IP, port)`,
  XOR-ed with the magic cookie / transaction id per RFC 5389 §15.2.
* Adds `MESSAGE-INTEGRITY` keyed by the *local* password.
* Adds `FINGERPRINT` last (its CRC is computed over everything
  before it).
* Writes the bytes back through the same UDP socket.

That socket is the very same `RtcUdpTransport.socket` we received
on; STUN, DTLS, and SRTP all share it.

## **4.6. The browser's STUN consistency checks**

Once the binding response lands, the browser knows the candidate
pair works in *one* direction. ICE consistency requires both
directions to validate, so the SFU also issues its own outbound
binding requests against the client's candidates. The same
`RtcUdpTransport` is responsible for tracking those queries — see
`_tryCompleteStunQuery(data)` in
[rtc_udp_transport.dart](../../lib/webrtc/rtc_udp_transport.dart),
which dispatches matching binding *responses* to the originating
gathering coroutine instead of the inbound STUN server.

When at least one candidate pair has succeeded *both ways*, ICE is
established. The very next packet the browser sends on that pair is
typically a **DTLS ClientHello** — and chapter 5 picks up there.

## **4.7. Quick reference: the STUN code**

| Concept | File |
|---|---|
| `StunMessage`, `StunMessageType`, `StunMessageMethod`, `StunMessageClass` | [lib/src/stun/stun_server.dart](../../lib/src/stun/stun_server.dart) |
| Magic cookie / transaction id encoding | same file |
| `XOR-MAPPED-ADDRESS` decode + encode | same file |
| HMAC-SHA1 MESSAGE-INTEGRITY | same file |
| CRC32 FINGERPRINT | same file |
| `StunServer.handleDatagram()` (server side) | same file |
| Outbound binding requests (client side, srflx gathering) | called from `RtcUdpTransport._gatherSrflxCandidates` |
| Per-peer ICE state, `discoveryMethod`, last-packet timestamp | `RtcPeerTransport` in [rtc_udp_transport.dart](../../lib/webrtc/rtc_udp_transport.dart) |

<br>

---

<div align="right">

[&lt;&nbsp;&nbsp;Previous chapter: FIRST CLIENT COMES IN](./03-FIRST-CLIENT-COMES-IN.md)&nbsp;&nbsp;|&nbsp;&nbsp;[Next chapter: DTLS HANDSHAKE&nbsp;&nbsp;&gt;](./05-DTLS-HANDSHAKE.md)

</div>
