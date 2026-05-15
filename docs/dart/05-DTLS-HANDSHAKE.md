# **5. DTLS HANDSHAKE**

ICE has nominated a pair, the SFU has answered the browser's STUN
checks, and the next inbound UDP datagram on the publisher PC's
socket starts with a `ContentType` byte in `[20, 63]` — a **DTLS
record**. The browser is opening Flight 1 of an RFC 6347 DTLS 1.2
handshake.

Where the Go original kept all DTLS state machine code under
`backend/src/dtls/`, the Dart port lives under
[lib/src/dtls/](../../lib/src/dtls/). The same record/handshake split
applies, but the file layout is much finer-grained — every handshake
message gets its own file.

This chapter is intentionally lighter than its 1500-line Go
counterpart. We don't recapitulate the bit-level layout of every
record (the original does that beautifully); instead we map each
concept onto the Dart file that owns it.

## **5.1. The flight diagram (recap)**

```text
Client                                  Server
------                                  ------
ClientHello (no cookie) -->                                    Flight 1
                        <-- HelloVerifyRequest                 Flight 2
ClientHello (cookie)    -->                                    Flight 3
                                            ServerHello       \
                                           Certificate         \
                                     ServerKeyExchange          Flight 4
                                    CertificateRequest         /
                        <--          ServerHelloDone          /
Certificate              \
ClientKeyExchange         \
CertificateVerify          Flight 5
[ChangeCipherSpec]        /
Finished                 /  -->
                        <-- [ChangeCipherSpec]                 \ Flight 6
                            Finished                           /
```

The SFU is the **DTLS server** for the publisher PC (the client
sent `a=setup:active`) and the **DTLS server** for the subscriber PC
as well in the typical browser flow. Both directions use the same
state machine, just with different transcripts.

## **5.2. Record layer**

Defined in [lib/src/dtls/record_layer_header.dart](../../lib/src/dtls/record_layer_header.dart)
and used by `record_io.dart`. A record header is 13 bytes:

```text
struct {
  ContentType  type;             // 1 byte (handshake=22, change_cipher_spec=20,
                                 //         alert=21, application_data=23)
  ProtocolVersion version;       // 2 bytes (DTLS 1.2 = 0xFEFD)
  uint16  epoch;                 // 2 bytes (incremented on ChangeCipherSpec)
  uint48  sequence_number;       // 6 bytes
  uint16  length;                // 2 bytes (of fragment)
} DTLSPlaintext;
```

When `epoch == 0` the record body is plaintext; once both sides have
sent `ChangeCipherSpec`, subsequent records are encrypted by the
chosen cipher suite (see §5.7).

Helpers:

* `RecordLayerHeader` (parser/encoder).
* `RecordIO` in [lib/src/dtls/server/record_io.dart](../../lib/src/dtls/server/record_io.dart) —
  reassembly + sequence number bookkeeping.

## **5.3. Handshake header**

[lib/src/dtls/handshake/handshake_header.dart](../../lib/src/dtls/handshake/handshake_header.dart)
defines the 12-byte handshake header that prefixes each message:

```text
HandshakeType   msg_type;          // 1 byte
uint24          length;            // total length of message body
uint16          message_seq;       // monotonic per side
uint24          fragment_offset;   // for DTLS fragmentation
uint24          fragment_length;
```

DTLS handshake messages can exceed the path MTU (e.g. a ~1500 byte
certificate); the protocol therefore supports fragmenting them
across multiple records. The Dart implementation handles inbound
fragmentation in `RecordIO` and **does not currently fragment
outbound messages** — relying on the path MTU being large enough for
its own short messages (it sends a single self-signed leaf cert).

## **5.4. The handshake messages, file by file**

| Flight | Message | File |
|---|---|---|
| 1, 3 | `ClientHello` | [client_hello.dart](../../lib/src/dtls/handshake/client_hello.dart) |
| 2 | `HelloVerifyRequest` | [hello_verify_request.dart](../../lib/src/dtls/handshake/hello_verify_request.dart) |
| 4 | `ServerHello` | [server_hello.dart](../../lib/src/dtls/handshake/server_hello.dart) |
| 4 | `Certificate` | [certificate.dart](../../lib/src/dtls/handshake/certificate.dart) |
| 4 | `ServerKeyExchange` | [server_key_exchange.dart](../../lib/src/dtls/handshake/server_key_exchange.dart) |
| 4 | `ServerHelloDone` | [server_hello_done.dart](../../lib/src/dtls/handshake/server_hello_done.dart) |
| 5 | `ClientKeyExchange` | [client_key_exchange.dart](../../lib/src/dtls/handshake/client_key_exchange.dart) |
| 5 | `CertificateVerify` | [certificate_verify.dart](../../lib/src/dtls/handshake/certificate_verify.dart) |
| 5, 6 | `ChangeCipherSpec` | [change_cipher_spec.dart](../../lib/src/dtls/handshake/change_cipher_spec.dart) |
| 5, 6 | `Finished` | [finished.dart](../../lib/src/dtls/handshake/finished.dart) |
| any | `Alert` | [alert.dart](../../lib/src/dtls/handshake/alert.dart) |

The base class `Handshake` in
[handshake.dart](../../lib/src/dtls/handshake/handshake.dart) handles
the framing; per-message subclasses just describe their fields.

`TlsRandom` (32 bytes — 4 byte unix time + 28 bytes of entropy) sits
in [tls_random.dart](../../lib/src/dtls/handshake/tls_random.dart).

## **5.5. Extensions (TLS hello extensions)**

The browser's `ClientHello` carries a stack of extensions. The Dart
implementation parses the ones WebRTC actually relies on; the rest
are ignored.

| Extension | File |
|---|---|
| `extended_master_secret` | [extensions/extende_master_secret.dart](../../lib/src/dtls/handshake/extensions/extende_master_secret.dart) |
| `supported_elliptic_curves` (`P-256` etc.) | [extensions/supported_elliptic_curves.dart](../../lib/src/dtls/handshake/extensions/supported_elliptic_curves.dart) |
| `ec_point_formats` | [extensions/supported_point_formats.dart](../../lib/src/dtls/handshake/extensions/supported_point_formats.dart) |
| `signature_algorithms` | [extensions/supported_signature_agorithms.dart](../../lib/src/dtls/handshake/extensions/supported_signature_agorithms.dart) |
| `use_srtp` (RFC 5764 — SRTP profile negotiation) | [extensions/use_srtp.dart](../../lib/src/dtls/handshake/extensions/use_srtp.dart) |
| `server_name` (SNI) | [extensions/server_name.dart](../../lib/src/dtls/handshake/extensions/server_name.dart) |

The `use_srtp` extension is the one that links chapter 5 to chapter 6:
it's how the two peers agree on which **SRTP protection profile**
(e.g. `SRTP_AEAD_AES_128_GCM`) to use once the handshake completes.

## **5.6. The state machine**

The per-peer state lives in
[`HandshakeContext`](../../lib/src/dtls/handshake/handshake_context.dart).
It tracks:

* The local and remote `TlsRandom` values.
* The negotiated `CipherSuite` and `UseSrtpProfile`.
* The handshake **transcript** (every handshake message, in wire
  order, used to compute `verify_data` for `Finished` and the
  signature input for `CertificateVerify`).
* `epoch`, `client_message_seq`, `server_message_seq`.
* The ECDHE keypair (server side: a fresh P-256 key generated for
  `ServerKeyExchange`).
* The pre-master secret → master secret derivation outputs.

The driver around it is
[`DtlsSession`](../../lib/src/dtls/server/dtls_session.dart) — one
per peer, owned by the `RtcPeerTransport` (chapter 4) and woken up
by inbound DTLS records in `RtcUdpTransport`. It dispatches each
handshake message to the right handler in
[`handshake_builders.dart`](../../lib/src/dtls/server/handshake_builders.dart),
which produces the next outbound flight.

[`DtlsServer`](../../lib/src/dtls/server/dtls_server.dart) is a
multi-peer wrapper around `DtlsSession` used by some of the standalone
examples in [bin/](../../bin/) (e.g.
[bin/dart_webrtc.dart](../../bin/dart_webrtc.dart),
[bin/srtp_webrtc2.dart](../../bin/srtp_webrtc2.dart)) where there is
no `RtcUdpTransport` to host per-peer state.

## **5.7. The cipher suite**

WebRTC peers in 2025 negotiate one of:

* `TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256` (most common with Chrome)
* `TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384`
* `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256` (RSA certs only)

The Dart server speaks the first one. The cipher suite implementation
sits in
[lib/src/dtls/handshaker/aes_gcm_128_sha_256.dart](../../lib/src/dtls/handshaker/aes_gcm_128_sha_256.dart):

* PRF = HMAC-SHA-256 (with `extended_master_secret` mixing the
  handshake transcript hash into the master secret derivation).
* AEAD = AES-128-GCM with explicit nonce.
* MAC key length = 0 (AEAD ciphers carry their own integrity).

Three PSK variants (`psk_aes_ccm`, `psk_aes_ccm8`,
`psk_aes_gcm_128_256`) live alongside it for IoT use cases — they're
not used by browsers.

## **5.8. The cookie exchange (Flights 1–3)**

DTLS uses the `HelloVerifyRequest` cookie dance to make denial-of-
service amplification harder: the server doesn't allocate per-peer
cryptographic state until the client proves it can receive at the
source IP it claims. The Dart implementation generates and verifies
the cookie in
[lib/src/dtls/server/cookie.dart](../../lib/src/dtls/server/cookie.dart).

Sequence:

1. `ClientHello` arrives with an empty `cookie` field.
2. The server replies with `HelloVerifyRequest` containing a freshly
   minted cookie (HMAC of `(client_addr, secret)`).
3. The client retransmits `ClientHello` with that cookie.
4. The server verifies the cookie, **then** allocates the full
   `HandshakeContext` and proceeds to Flight 4.

## **5.9. Flight 4 — the heavy server response**

Triggered by a cookie-verified `ClientHello`. `handshake_builders.dart`
emits, in transcript order:

1. **`ServerHello`** — picks the cipher suite, echoes the chosen
   extensions, sends the server's `TlsRandom`.
2. **`Certificate`** — the per-PC self-signed P-256 cert from
   chapter 2 §2.3.
3. **`ServerKeyExchange`** — generates an ephemeral P-256 ECDHE
   keypair, signs `(client_random || server_random || curve_id || pubkey)`
   with the certificate's private key (ECDSA over SHA-256), sends
   the public key + signature.
4. *(Skipped for WebRTC.)* `CertificateRequest` — most browsers don't
   send a client certificate by default, but the Dart server
   tolerates either path.
5. **`ServerHelloDone`** — empty marker.

All five are packed into a single UDP datagram if they fit under the
MTU; otherwise they are split across records (still in transcript
order).

## **5.10. Flight 5 — the client locks in the keys**

* **`Certificate`** — the browser's self-signed cert. The SFU verifies
  it later by comparing its SHA-256 fingerprint against the value in
  the `a=fingerprint:` line of the SDP (chapter 3 §3.6). If the
  fingerprints don't match, the session is killed.
* **`ClientKeyExchange`** — carries the client's ECDHE public key.
  Combined with the server's private key from Flight 4 this yields
  the **pre-master secret**.
* **`CertificateVerify`** — ECDSA signature over the entire transcript
  so far, signed with the *client's* certificate private key. Proves
  the client possesses the key matching the cert it just sent.
* **`ChangeCipherSpec`** — bumps `epoch` from 0 to 1; from now on the
  client sends encrypted records.
* **`Finished`** — first encrypted message. Contains
  `verify_data = PRF(master_secret, "client finished", hash(transcript))`.
  The server checks the PRF output bit-for-bit.

## **5.11. Flight 6 — the server seals the deal**

* **`ChangeCipherSpec`** — server epoch flips to 1.
* **`Finished`** — `verify_data` bound to `"server finished"`.

Once both `Finished` messages verify, the handshake is complete and
both sides hold:

* A 48-byte `master_secret` (extended-master-secret-ified).
* The handshake transcript hash.
* Symmetric AES-GCM keys + IVs derived from the master secret via
  the PRF.

## **5.12. The handoff to SRTP**

The reason WebRTC bothers with DTLS isn't TLS-style application data —
it's the **DTLS-SRTP key extractor** (RFC 5705 / RFC 5764). After
`Finished`, the SFU calls into
[lib/src/dtls/server/cipher_suite_init.dart](../../lib/src/dtls/server/cipher_suite_init.dart)
with the label `"EXTRACTOR-dtls_srtp"` and pulls out enough bytes to
seed the negotiated SRTP profile:

| Profile | Total exporter bytes |
|---|---|
| `SRTP_AES128_CM_HMAC_SHA1_80` | 60 (2×16 keys + 2×14 salts) |
| `SRTP_AEAD_AES_128_GCM` | 56 (2×16 keys + 2×12 salts) |

These bytes are split into `(client_write_key, server_write_key,
client_write_salt, server_write_salt)` and passed straight to the
SRTP layer. That's the topic of chapter 6.

## **5.13. Useful breakpoints**

| Behaviour | File / symbol |
|---|---|
| First DTLS byte hits the wire | `RtcUdpTransport._handleDatagram` (DTLS branch) |
| Cookie verification | `verifyCookie()` in [cookie.dart](../../lib/src/dtls/server/cookie.dart) |
| Cipher suite negotiation | `pickCipherSuite()` in [server_hello.dart](../../lib/src/dtls/handshake/server_hello.dart) |
| `Finished` PRF computation | `computeVerifyData()` in [finished.dart](../../lib/src/dtls/handshake/finished.dart) |
| Exporter into SRTP keying | `extractSrtpKeyingMaterial()` in [cipher_suite_init.dart](../../lib/src/dtls/server/cipher_suite_init.dart) |

## **5.14. Standalone DTLS examples**

If you want to drive DTLS without the rest of the SFU, two minimal
servers exist in [bin/](../../bin/):

* [bin/dart_webrtc.dart](../../bin/dart_webrtc.dart) — bare DTLS
  server that logs each handshake message.
* [bin/srtp_webrtc2.dart](../../bin/srtp_webrtc2.dart) — the same
  server but plumbed all the way through SRTP, so you can echo
  encrypted media back to a Chrome tab.

A matching client lives at
[bin/srtp_client.dart](../../bin/srtp_client.dart) — it negotiates
DTLS as a client and then sends a VP8 file as SRTP.

<br>

---

<div align="right">

[&lt;&nbsp;&nbsp;Previous chapter: STUN BINDING REQUEST FROM CLIENT](./04-STUN-BINDING-REQUEST-FROM-CLIENT.md)&nbsp;&nbsp;|&nbsp;&nbsp;[Next chapter: SRTP INITIALIZATION&nbsp;&nbsp;&gt;](./06-SRTP-INITIALIZATION.md)

</div>
