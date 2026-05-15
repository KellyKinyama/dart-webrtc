# **6. SRTP INITIALIZATION**

When DTLS finishes (chapter 5), the SFU has a 48-byte master secret
shared with the browser, plus an agreed-upon SRTP profile from the
`use_srtp` extension. SRTP is the layer that takes raw RTP/RTCP and
makes it confidential + integrity-protected on the wire.

## **6.1. The SRTP profile**

The Dart implementation supports the two profiles WebRTC actually
ships:

| Profile (`UseSrtpProfile`) | Cipher | Auth tag | Key | Salt |
|---|---|---|---|---|
| `SRTP_AES128_CM_HMAC_SHA1_80` | AES-128 in counter mode | HMAC-SHA1, 80-bit tag | 128 bit | 112 bit |
| `SRTP_AEAD_AES_128_GCM` | AES-128-GCM (AEAD) | 128-bit tag (GCM) | 128 bit | 96 bit |

Profile constants live in
[lib/src/srtp/protection_profiles.dart](../../lib/src/srtp/protection_profiles.dart),
and the canonical key/salt sizes for each one are in
[lib/src/srtp/constants.dart](../../lib/src/srtp/constants.dart).

The negotiation itself was in
[lib/src/dtls/handshake/extensions/use_srtp.dart](../../lib/src/dtls/handshake/extensions/use_srtp.dart) —
each side advertises a list of profile IDs it supports and the server
picks the first match.

## **6.2. The DTLS-SRTP key extractor**

RFC 5764 §4.2 defines the keying-material extractor. Inputs:

* The DTLS master secret + client/server randoms (already in the
  `HandshakeContext`).
* A label string: `"EXTRACTOR-dtls_srtp"`.
* No context bytes.
* An output length determined by the chosen profile (60 bytes for
  AES-CM, 56 bytes for AES-GCM).

Implementation lives in
[lib/src/dtls/server/cipher_suite_init.dart](../../lib/src/dtls/server/cipher_suite_init.dart).
It runs the same TLS 1.2 PRF (HMAC-SHA-256 in this codebase) the
handshake uses internally.

The output bytes are then split per RFC 5764 §4.2 into:

```text
[ client_write_SRTP_master_key   ][ server_write_SRTP_master_key ]
[ client_write_SRTP_master_salt  ][ server_write_SRTP_master_salt ]
```

Whichever side **was the DTLS client** uses `client_write_*` for its
outbound traffic. The SFU is the DTLS server in the typical browser
flow, so:

* `server_write_*` → SFU's outbound SRTP context (sender).
* `client_write_*` → SFU's inbound SRTP context (receiver).

## **6.3. The SRTP context**

Each peer ends up holding **two** SRTP contexts — one per direction.
The Dart class is
[`SRTPContext`](../../lib/src/srtp/srtp_context.dart). Per-context
state:

* The AEAD cipher (currently `GCM` from
  [lib/src/srtp/crypto_gcm.dart](../../lib/src/srtp/crypto_gcm.dart)).
* The 16-byte master key + 14- or 12-byte master salt.
* Per-SSRC state tables: rollover counter (ROC), highest received
  sequence number, and a 64-entry sliding **replay window**.
* A separate SRTCP index counter per SSRC (31-bit monotonic).

Construction is wrapped by
[`SRTPSession`](../../lib/src/srtp/srtp_session.dart) which is the
object the rest of the SFU sees:

```text
SRTPSession
 ├─ inboundContext  : SRTPContext   (decrypts client→server media)
 └─ outboundContext : SRTPContext   (encrypts server→client media)
```

## **6.4. Per-packet key derivation (AES-CM only)**

For `SRTP_AES128_CM_HMAC_SHA1_80`, RFC 3711 §4.3 derives **session
keys** (per-stream, per-direction) from the master key/salt by running
AES-CM with a label byte (0x00 for cipher, 0x01 for auth, 0x02 for
salt). The Dart implementation does this lazily on first use of an
SSRC and caches the result inside `SRTPContext`.

For `SRTP_AEAD_AES_128_GCM` no auth-key derivation is needed — GCM
provides authentication itself — but the salt-derivation step is the
same.

## **6.5. The handoff from DTLS**

Inside [lib/webrtc/rtc_udp_transport.dart](../../lib/webrtc/rtc_udp_transport.dart),
each `RtcPeerTransport` owns:

```dart
DtlsSession dtlsSession;
SRTPContext? srtp;          // populated at end-of-handshake
```

When `DtlsSession` reaches the `Finished` step, its completion
callback calls `extractSrtpKeyingMaterial()` and stores the resulting
context on the peer. From that moment on, the demultiplexer in
chapter 4 will route any RTP/RTCP packet through the new context
(see the `if (isRtpPacket) … ctx.decryptRtpPacket(pkt)` branch).

## **6.6. SRTP without DTLS — the standalone manager**

[`SRTPManager`](../../lib/src/srtp/srtp_manager.dart) and
[`SRTPClient`](../../lib/src/srtp/srtp_client.dart) wrap the same
contexts for callers that get their keys from outside DTLS — useful
in tests and the
[bin/srtp_*.dart](../../bin/) demos. They do not change anything
about the cipher; only the lifecycle around it.

## **6.7. Tests**

Two focused tests verify the wiring:

* [test/srtp_replay_test.dart](../../test/srtp_replay_test.dart) —
  proves the 64-bit sliding window rejects replays correctly.
* [test/srtcp_test.dart](../../test/srtcp_test.dart) — round-trips
  encrypt/decrypt on RTCP and checks the per-SSRC SRTCP index.

Once both contexts are alive, the SFU is ready to receive its first
**SRTP packet**. That's chapter 7.

<br>

---

<div align="right">

[&lt;&nbsp;&nbsp;Previous chapter: DTLS HANDSHAKE](./05-DTLS-HANDSHAKE.md)&nbsp;&nbsp;|&nbsp;&nbsp;[Next chapter: SRTP PACKETS COME&nbsp;&nbsp;&gt;](./07-SRTP-PACKETS-COME.md)

</div>
