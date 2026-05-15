// Subscriber — server-side wrapper around the client's "subscribe"
// PeerConnection. The server is the *offerer*: every time a new
// producer joins (or an existing one stops) the subscriber emits a
// negotiation-needed event so the signaling layer can reissue an offer.
//
// Mirrors `pkg/sfu/subscriber.go`.

import 'dart:async';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

import 'down_track.dart';
import 'bwe.dart';
import 'producer_stream.dart';
import 'receiver.dart';
import 'rtcp.dart';
import 'sdp_helpers.dart';
import 'session.dart';
import 'ssrc_allocator.dart';
import 'twcc/twcc_stamper.dart';

class Subscriber {
  final String peerId;
  final Session session;
  final RTCPeerConnection pc;
  final RtcUdpTransport transport;

  /// Per-subscriber SSRC remapper. Stable for the lifetime of the
  /// subscriber.
  final SsrcAllocator allocator = SsrcAllocator();

  /// Phase 5 — downlink bandwidth estimator. Fed by REMB / TWCC from
  /// the subscriber side. Drives [layerSelector].
  final BandwidthEstimator bwe = BandwidthEstimator();

  /// Phase 7 — transport-wide congestion-control sequence stamper.
  /// One per subscriber PC; every outbound primary RTP packet whose
  /// receiver negotiated `twccExtId` is stamped with a monotonic
  /// 16-bit seq before being shipped to the browser.
  final TwccStamper twccStamper = TwccStamper();

  /// Phase 5 — chooses the simulcast layer for each receiver. Fires
  /// [Subscriber.setPreferredLayer] on every layer change.
  late final LayerSelector layerSelector = LayerSelector(estimator: bwe)
    ..onLayerChange = (receiverId, rid) {
      setPreferredLayer(receiverId, rid);
    };

  /// Cumulative payload bytes seen since the last TWCC update — used
  /// as the byte budget when [BandwidthEstimator.onTwcc] runs.
  int _lastBytesForwardedSnapshot = 0;

  /// Recompute the byte budget delta since the previous TWCC.
  int _consumeBytesBudget() {
    var total = 0;
    for (final dt in _downTracks.values) {
      total += dt.bytesForwarded;
    }
    final delta = total - _lastBytesForwardedSnapshot;
    _lastBytesForwardedSnapshot = total;
    return delta < 0 ? 0 : delta;
  }

  /// receiverId → DownTrack. There's one DownTrack per (subscriber,
  /// producer-track) pair.
  final Map<String, DownTrack> _downTracks = {};

  /// rewrittenSsrc → DownTrack. Used to reverse-map subscriber feedback
  /// back to the producer.
  final Map<int, DownTrack> _byRewrittenSsrc = {};

  /// When true (per `JoinConfig.noAutoSubscribe`), [addReceiver] is a
  /// no-op until callers explicitly request a track.
  bool noAutoSubscribe = false;

  /// Fires when the subscriber needs to renegotiate (a new producer
  /// joined, or one left). The signaling layer must call
  /// [createOffer] and ship the result with `target:"sub"`.
  void Function()? onNegotiationNeeded;

  void Function(RTCIceCandidate? candidate)? onIceCandidate;
  void Function(RTCIceConnectionState state)? onIceConnectionStateChange;

  bool _closed = false;
  bool _negotiationScheduled = false;

  Subscriber._({
    required this.peerId,
    required this.session,
    required this.pc,
    required this.transport,
  }) {
    pc.onIceCandidate = (c) => onIceCandidate?.call(c);
    pc.onIceConnectionStateChange = (s) => onIceConnectionStateChange?.call(s);

    // Subscriber-side feedback: NACK / PLI from the browser. Routed to
    // the right DownTrack / publisher.
    transport.onRtcp = (peer, rtcp) => _onSubscriberRtcp(rtcp);
  }

  static Future<Subscriber> create({
    required String peerId,
    required Session session,
  }) async {
    final cfg = session.sfu.config;
    final pc = RTCPeerConnection(RTCConfiguration(
      iceServers: [
        for (final url in cfg.iceServerUrls) RTCIceServer(urls: [url]),
      ],
      defaultVideoCodecs: cfg.defaultVideoCodecs,
      defaultAudioCodecs: cfg.defaultAudioCodecs,
    ));
    final port = session.sfu.allocatePort();
    final transport = await pc.bind(
      cfg.bindAddress,
      port,
      announceAddress: cfg.announceAddress,
    );
    return Subscriber._(
      peerId: peerId,
      session: session,
      pc: pc,
      transport: transport,
    );
  }

  /// Snapshot of the DownTracks currently attached to this subscriber.
  Iterable<DownTrack> get downTracks => _downTracks.values;

  /// Producer streams currently being forwarded, in DownTrack insertion
  /// order. Drives SDP augmentation in [createOffer].
  List<ProducerStream> _producerStreamsForOffer() =>
      [for (final dt in _downTracks.values) dt.receiver.stream];

  /// Wire [receiver] to a new [DownTrack] on this subscriber. Adds a
  /// sendonly transceiver to the PC and schedules a renegotiation.
  ///
  /// No-op if [noAutoSubscribe] is true (callers must call
  /// `addReceiverForced` explicitly in that case).
  void addReceiver(Receiver receiver) {
    if (noAutoSubscribe) return;
    addReceiverForced(receiver);
  }

  /// Like [addReceiver] but ignores [noAutoSubscribe]. Use this from
  /// custom signaling that lets the client pick streams.
  void addReceiverForced(Receiver receiver) {
    if (_closed) return;
    if (_downTracks.containsKey(receiver.id)) return;

    final transceiver = pc.addTransceiver(
      trackOrKind: receiver.kind,
      direction: RTCRtpTransceiverDirection.sendonly,
    );

    final rwPrimary = allocator.rewrite(peerId, receiver.primarySsrc);
    int? rwRtx;
    if (receiver.rtxSsrc != null) {
      rwRtx = allocator.rewriteRtx(
        peerId,
        receiver.primarySsrc,
        receiver.rtxSsrc!,
      );
    }

    final dt = DownTrack(
      id: receiver.id,
      receiver: receiver,
      transceiver: transceiver,
      subscriberPc: pc,
      rewrittenPrimarySsrc: rwPrimary,
      rewrittenRtxSsrc: rwRtx,
      twccStamper: twccStamper,
    );
    _downTracks[receiver.id] = dt;
    _byRewrittenSsrc[rwPrimary] = dt;
    if (rwRtx != null) _byRewrittenSsrc[rwRtx] = dt;
    receiver.attachDownTrack(dt);
    if (receiver.isSimulcast) {
      layerSelector.register(
        receiver.id,
        [for (final l in receiver.layers) l.rid],
        initialRid: receiver.stream.defaultLayer.rid,
      );
    }
    _scheduleNegotiation();
  }

  /// Tear the DownTrack for [receiver] down and renegotiate.
  void removeReceiver(Receiver receiver) {
    final dt = _downTracks.remove(receiver.id);
    if (dt == null) return;
    _byRewrittenSsrc.remove(dt.rewrittenPrimarySsrc);
    if (dt.rewrittenRtxSsrc != null) {
      _byRewrittenSsrc.remove(dt.rewrittenRtxSsrc);
    }
    layerSelector.unregister(receiver.id);
    receiver.detachDownTrack(dt);
    dt.close();
    _scheduleNegotiation();
  }

  /// Switch the simulcast layer being forwarded for [receiverId] to
  /// [rid] (`'q'`/`'h'`/`'f'` by convention). Returns true when the
  /// layer changed. Triggers an upstream PLI so the new layer's next
  /// keyframe arrives quickly.
  bool setPreferredLayer(String receiverId, String rid) {
    final dt = _downTracks[receiverId];
    if (dt == null) return false;
    if (!dt.setCurrentLayer(rid)) return false;
    _sendUpstreamPli(dt);
    return true;
  }

  /// Generate the server-side offer for this subscriber PC. The raw
  /// offer from `pc.createOffer` does not declare the per-subscriber
  /// rewritten SSRCs; we inject them via [augmentSubscriberOffer] so
  /// the browser can pair primary + RTX before any RTP arrives.
  ///
  /// IMPORTANT: the augmented SDP is what we both ship to the browser
  /// AND apply via `pc.setLocalDescription`. Earlier versions stored
  /// the raw offer locally and shipped the augmented one — on a
  /// renegotiation Chrome cross-validates the answer against the
  /// PC-cached local description and aborts with `LevelFatal /
  /// InternalError` because the SSRC sets diverge. Keeping the two in
  /// sync makes subscriber renegotiation safe.
  Future<RTCSessionDescription> createOffer() async {
    final raw = await pc.createOffer();
    final augmentedSdp = augmentSubscriberOffer(
      subscriberId: peerId,
      allocator: allocator,
      streams: _producerStreamsForOffer(),
      offerSdp: raw.sdp,
    );
    final augmented = RTCSessionDescription(RTCSdpType.offer, augmentedSdp);
    await pc.setLocalDescription(augmented);
    return augmented;
  }

  /// Apply the client's answer.
  Future<void> setAnswer(String answerSdp) {
    return pc.setRemoteDescription(
      RTCSessionDescription(RTCSdpType.answer, answerSdp),
    );
  }

  // ---- Subscriber feedback -------------------------------------------

  /// Inbound RTCP from the browser. NACK and PLI are reverse-mapped via
  /// the rewritten SSRC and either satisfied locally (NACK from jitter
  /// buffer) or escalated to the publisher (PLI / cache-miss NACK).
  void _onSubscriberRtcp(Uint8List rtcp) {
    if (_closed) return;
    for (final fb in parseFeedback(rtcp)) {
      final dt = _byRewrittenSsrc[fb.mediaSsrc];
      if (fb is NackFeedback) {
        if (dt == null) continue;
        final res = dt.nack.lookup(fb.allMissing());
        if (res.hits.isNotEmpty) dt.replay(res.hits);
        if (res.stillMissing.isNotEmpty) {
          _sendUpstreamNack(dt, res.stillMissing);
        }
      } else if (fb is PliFeedback) {
        if (dt == null) continue;
        _sendUpstreamPli(dt);
      } else if (fb is FirFeedback) {
        // RFC 5104 §4.3.1.1 — some clients (notably iOS / older VoIP
        // stacks) only emit FIR. Resolve each target SSRC against the
        // rewritten-SSRC → DownTrack table and escalate as a PLI to the
        // owning publisher. We translate FIR→PLI on the upstream leg
        // because every browser-side WebRTC stack accepts PLI but the
        // FIR receiver bit is rarely negotiated.
        for (final target in fb.targetSsrcs) {
          final tdt = _byRewrittenSsrc[target];
          if (tdt != null) _sendUpstreamPli(tdt);
        }
      } else if (fb is RembFeedback) {
        // REMB doesn't carry a media SSRC (it's a transport-wide
        // estimate). Feed it unconditionally.
        bwe.onRemb(fb);
        // Update active-video count and re-run layer selection
        // immediately so a sharp drop reacts without waiting for the
        // periodic tick.
        layerSelector.activeVideoDownTracks = _videoDownTrackCount();
        layerSelector.tick();
      } else if (fb is TwccFeedback) {
        final budget = _consumeBytesBudget();
        // Phase 7b — delay-based update first (uses send-time history
        // recorded by the stamper). Falls back to the throughput-only
        // path when we don't have enough history yet.
        if (twccStamper.totalStamped > 0) {
          bwe.onTwccDelay(fb, twccStamper);
        } else {
          bwe.onTwcc(fb, budget);
        }
        layerSelector.activeVideoDownTracks = _videoDownTrackCount();
        layerSelector.tick();
      }
    }
  }

  int _videoDownTrackCount() {
    var n = 0;
    for (final dt in _downTracks.values) {
      if (dt.receiver.kind == MediaKind.video) n++;
    }
    return n == 0 ? 1 : n;
  }

  void _sendUpstreamNack(DownTrack dt, List<int> missing) {
    final pub = _publisherFor(dt);
    if (pub == null) return;
    final pkt = buildNack(1, dt.receiver.primarySsrc, missing);
    pub.transport.sendRtcp(pub.pc.activePeer!, pkt);
  }

  /// Throttle constant lives on [DownTrack.minUpstreamPliGap]; the
  /// per-DownTrack gate is enforced via [DownTrack.tryConsumePliCredit].
  void _sendUpstreamPli(DownTrack dt) {
    if (!dt.tryConsumePliCredit(DateTime.now())) return;
    final pub = _publisherFor(dt);
    if (pub == null) return;
    final pkt = buildPli(1, dt.receiver.primarySsrc);
    pub.transport.sendRtcp(pub.pc.activePeer!, pkt);
  }

  /// Resolve the publisher transport that owns the producer stream
  /// [dt] is mirroring. Returns null when DTLS isn't up yet.
  _PublisherRef? _publisherFor(DownTrack dt) {
    final owner = session.getPeer(dt.receiver.peerId);
    if (owner == null) return null;
    final pub = owner.publisher;
    if (pub == null) return null;
    final peer = pub.pc.activePeer;
    if (peer == null || !peer.isSecure) return null;
    return _PublisherRef(pub.pc, pub.transport);
  }

  void _scheduleNegotiation() {
    if (_negotiationScheduled || onNegotiationNeeded == null) return;
    _negotiationScheduled = true;
    scheduleMicrotask(() {
      _negotiationScheduled = false;
      if (_closed) return;
      onNegotiationNeeded?.call();
    });
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final dt in _downTracks.values) {
      dt.close();
    }
    _downTracks.clear();
    _byRewrittenSsrc.clear();
    allocator.forget(peerId);
    pc.close();
  }
}

class _PublisherRef {
  final RTCPeerConnection pc;
  final RtcUdpTransport transport;
  _PublisherRef(this.pc, this.transport);
}
