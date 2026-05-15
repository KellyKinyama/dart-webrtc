# **3. FIRST CLIENT COMES IN**

The Go original orchestrated everything from a hand-written
`RTC` + `Signaling` pair in TypeScript and used a project-specific
JSON envelope (`Welcome`, `JoinConference`, `SdpOffer`,
`SdpOfferAnswer`).

The Dart SFU speaks a much smaller, **ion-style** wire format
inspired by `pion/ion-sfu`. The client side can be any browser
WebRTC app — there is no bundled UI in this repo.

This chapter walks through what happens when the first client opens
the WebSocket, joins a session, and hands the SFU its SDP offer.

## **3.1. The signalling wire format**

Every signalling frame is a JSON object with a `type` field. The full
list of message types accepted by the server lives in
[`_onMessage()`](../../example/ion_style_sfu/lib/src/sfu_server.dart)
inside `_PeerConnection._onMessage`, which switches on:

| Direction | `type`     | Purpose                                                                |
|-----------|------------|------------------------------------------------------------------------|
| client→server | `join`     | Join a session as a peer with a given `uid`                       |
| client→server | `offer`    | Publish an SDP offer (publisher)                                  |
| client→server | `answer`   | Answer an SDP offer the server sent (subscriber)                  |
| client→server | `trickle`  | Send an ICE candidate                                             |
| client→server | `leave`    | Voluntarily leave                                                 |
| server→client | `offer`    | Subscriber-side offer (server initiates the down-track PC)        |
| server→client | `answer`   | Publisher-side answer to the client's `offer`                     |
| server→client | `trickle`  | Server ICE candidate                                              |
| server→client | `peer-join` / `peer-leave` | Room membership notifications                     |
| server→client | `error`    | `reason` field carries the failure code                           |

URL routing: a client connects to **`ws://<host>:<ws-port>/ws/<sessionId>`**.
The path component identifies the room; everything else flows over the
single WebSocket.

There is no separate `Welcome` handshake. The first message the
client sends is `join`.

## **3.2. The browser side (sketch)**

The Dart repo does not ship a full UI, but a minimal client looks
like this in browser JavaScript:

```js
// Two PeerConnections — one for publishing (we send), one for receiving.
const pub = new RTCPeerConnection({iceServers: [...]});
const sub = new RTCPeerConnection({iceServers: [...]});

const stream = await navigator.mediaDevices.getUserMedia({video: true, audio: true});
stream.getTracks().forEach(t => pub.addTrack(t, stream));

const ws = new WebSocket(`ws://${HOST}:9090/ws/${sessionId}`);
ws.onopen = async () => {
  ws.send(JSON.stringify({type: 'join', uid: 'alice'}));

  // Standard WebRTC negotiation — we only show the server-bound side.
  const offer = await pub.createOffer();
  await pub.setLocalDescription(offer);
  ws.send(JSON.stringify({type: 'offer', target: 'pub', sdp: offer.sdp}));
};
pub.onicecandidate = e => e.candidate &&
  ws.send(JSON.stringify({type: 'trickle', target: 'pub', candidate: e.candidate}));
sub.onicecandidate = e => e.candidate &&
  ws.send(JSON.stringify({type: 'trickle', target: 'sub', candidate: e.candidate}));

ws.onmessage = ev => {
  const m = JSON.parse(ev.data);
  if (m.type === 'answer' && m.target === 'pub') pub.setRemoteDescription({type:'answer', sdp:m.sdp});
  if (m.type === 'offer'  && m.target === 'sub') (async () => {
    await sub.setRemoteDescription({type:'offer', sdp:m.sdp});
    const a = await sub.createAnswer();
    await sub.setLocalDescription(a);
    ws.send(JSON.stringify({type: 'answer', target: 'sub', sdp: a.sdp}));
  })();
  if (m.type === 'trickle') {
    (m.target === 'pub' ? pub : sub).addIceCandidate(m.candidate);
  }
};
```

Two PCs ("publisher" and "subscriber") is the ion-SFU convention: the
client *uploads* on `pub` and *downloads* on `sub`. The SFU mirrors
this with a `Publisher` and `Subscriber`
[`RTCPeerConnection`](../../lib/webrtc/peer_connection.dart) per peer.

## **3.3. The server accepts the WebSocket**

Inside `runIonStyleSfuServer()`
([example/ion_style_sfu/lib/src/sfu_server.dart](../../example/ion_style_sfu/lib/src/sfu_server.dart)):

```dart
http.listen((req) {
  // … CORS / health / drain checks …
  if (WebSocketTransformer.isUpgradeRequest(req)) {
    final sid = req.uri.pathSegments[1];          // /ws/<sid>
    WebSocketTransformer.upgrade(req).then((ws) {
      _PeerConnection(/* sharded, sid, ws, … */);
    });
  }
});
```

Each upgraded socket is wrapped in a `_PeerConnection` (private to
`sfu_server.dart`) which owns:

* the `WebSocket`,
* the room id (`sid`) and per-peer `uid`,
* the `SessionShard` it belongs to,
* a small rate-limit window over inbound signalling frames.

## **3.4. `join` — wiring the peer into a `Session`**

The first frame must be `join`:

```dart
case 'join':
  await _onJoin(msg);
```

`_onJoin()` (in the same file):

1. Validates the `uid`.
2. Enforces `--max-peers-per-room` and the node-wide `--max-sessions`.
3. Calls `sharded.getOrCreate(sid)` to fetch (or boot) the
   `SessionShard` for that room.
4. Registers the WebSocket with the per-room `_SessionRouter` so
   subsequent server-emitted events for `sid` find their way back to
   this client.
5. Tells the worker isolate to instantiate a `Peer` (publisher PC +
   subscriber PC) inside that `Session`.

There is no "welcome" round trip; success is implicit. If anything
fails, the server replies with `{type: "error", reason: …}` and
closes the socket.

## **3.5. The subscriber-side offer is server-initiated**

Unlike the Go tutorial — where the *server* sent the SDP offer for
the only PC and the client answered — the ion-style SFU runs **two**
PCs per peer and the offer direction differs:

| PC | Offerer | Why |
|---|---|---|
| Publisher (uplink) | client | The client picks codecs / extensions for the media it owns. |
| Subscriber (downlink) | server | The server controls which tracks are forwarded. |

So after `join` the server may emit:

```dart
_sendTo(uid, {'type': 'offer', 'target': 'sub', 'sdp': sdp});
```

…and the client answers via `{type: 'answer', target: 'sub', …}`.

## **3.6. Where the SDP comes from on the server**

The server-built SDP is constructed by the SDP v2 builder in
[lib/signal/sdp_v2.dart](../../lib/signal/sdp_v2.dart) and the more
focused offer/answer helpers in
[lib/signal/sdp/sdp_offer_answer.dart](../../lib/signal/sdp/sdp_offer_answer.dart).
The string the server emits over the WebSocket already contains:

* `a=ice-ufrag:` / `a=ice-pwd:` — generated by the ICE agent
  ([lib/src/ice/ice2.dart](../../lib/src/ice/ice2.dart)).
* `a=fingerprint:sha-256 …` — derived from the per-PC self-signed
  cert (chapter 2 §2.3).
* `a=candidate:` lines — host candidates from `--announce-ip` and any
  `srflx` candidates discovered through `--ice-server`.
* `a=setup:actpass` for the offer, `a=setup:active` or `passive` for
  the answer (DTLS role negotiation, see chapter 5).
* `a=fmtp:` / `a=rtpmap:` — codec descriptions from
  [lib/signal/sdp/sdp_codec.dart](../../lib/signal/sdp/sdp_codec.dart)
  (`Vp8Codec`, `H264Codec`, `Vp9Codec`, `PcmaCodec`, `PcmuCodec`).
* `a=extmap:` — RTP header extensions (audio level RFC 6464,
  RID, repaired-RID, TWCC sequence numbers …).
* `a=mid:` and BUNDLE groups so video and audio share a single ICE
  transport.

## **3.7. Handling the inbound `offer` (publisher path)**

When the client sends `{type: 'offer', target: 'pub', sdp: …}`:

1. The shard worker invokes `Publisher.handleOffer(sdp)` in
   [example/ion_style_sfu/lib/src/publisher.dart](../../example/ion_style_sfu/lib/src/publisher.dart).
2. The `RTCPeerConnection`
   ([lib/webrtc/peer_connection.dart](../../lib/webrtc/peer_connection.dart))
   parses the SDP, extracts the remote ICE ufrag/pwd and DTLS
   fingerprint, sets the remote description, and produces an answer.
3. The server-side answer goes back over the WebSocket as
   `{type: 'answer', target: 'pub', sdp: …}`.
4. The local ICE agent starts gathering candidates. Each gathered
   candidate is shipped as `{type: 'trickle', target: 'pub',
   candidate: …}` — the Dart SFU does *trickle* by default and does
   not wait for ICE gathering to complete before answering.

After the answer is sent, the SFU and the browser have *enough
information* to begin the actual peer-to-peer dialogue: ICE
connectivity checks, then DTLS, then media. Everything from this
point on flows over UDP.

## **3.8. State machines and observability**

Every `RTCPeerConnection` exposes:

* `iceConnectionState` (`new` → `checking` → `connected` →
  `completed` / `failed` / `disconnected` / `closed`)
* `iceGatheringState` (`new` → `gathering` → `complete`)
* `connectionState`
* `signalingState`

Defined in [lib/webrtc/peer_connection.dart](../../lib/webrtc/peer_connection.dart).
The SFU subscribes to these to clean up sessions whose ICE has
collapsed. Useful breakpoints during this chapter:

* `_PeerConnection._onMessage` in
  [sfu_server.dart](../../example/ion_style_sfu/lib/src/sfu_server.dart) —
  see every JSON frame.
* `Publisher.handleOffer` /
  `Subscriber.handleAnswer` in the respective files.

We're now waiting for the first STUN binding request to arrive on
the freshly-bound UDP socket of the publisher PC.

<br>

---

<div align="right">

[&lt;&nbsp;&nbsp;Previous chapter: SERVER INITIALIZATION](./02-BACKEND-INITIALIZATION.md)&nbsp;&nbsp;|&nbsp;&nbsp;[Next chapter: STUN BINDING REQUEST FROM CLIENT&nbsp;&nbsp;&gt;](./04-STUN-BINDING-REQUEST-FROM-CLIENT.md)

</div>
