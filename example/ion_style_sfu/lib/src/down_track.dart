// DownTrack — one outbound stream from the SFU to a single subscriber,
// pairing a `Receiver` (the producer side) with the subscriber's
// PeerConnection (the consumer side).
//
// Mirrors `pkg/sfu/downtrack.go`. Phase 2 introduces SSRC rewriting and
// the per-track jitter buffer that backs NACK retransmission. Phase 3a
// adds simulcast layer filtering — packets from layers other than
// [currentLayer] are dropped, so the subscriber only ever sees one
// continuous SSRC stream regardless of how many the publisher sends.
// Phase 3b adds SN/TS continuity across layer switches plus RFC 4588
// OSN rewriting so RTX still resolves into the rewritten primary
// sequence-number space.

import 'dart:typed_data';
import 'dart:math' show Random;

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

import 'buffer/buffer.dart';
import 'buffer/nack.dart';
import 'byte_pool.dart';
import 'pacer/leaky_bucket.dart';
import 'producer_layer.dart';
import 'receiver.dart';
import 'rtcp_rewrite.dart';
import 'simulcast_rewriter.dart';
import 'vp8.dart';
import 'vp9.dart';
import 'h264.dart';
import 'twcc/twcc_stamper.dart';

enum DownTrackType { simple, simulcast }

class DownTrack {
  /// Same id as the source [Receiver].
  final String id;

  final Receiver receiver;
  final RTCRtpTransceiver transceiver;

  /// PC owning the subscriber transport. Used to resolve the secured
  /// peer (DTLS-keyed) we should send to.
  final RTCPeerConnection subscriberPc;

  /// Per-subscriber rewritten primary SSRC.
  final int rewrittenPrimarySsrc;

  /// Per-subscriber rewritten RTX SSRC. Null when the publisher didn't
  /// negotiate RTX.
  final int? rewrittenRtxSsrc;

  /// `simple` for non-simulcast receivers, `simulcast` when the
  /// receiver carries multiple layers.
  final DownTrackType trackType;

  /// SSRC + SN/TS rewrite engine. Holds per-layer offsets so a layer
  /// switch produces a continuous outbound stream.
  final SimulcastRewriter _rewriter;

  /// Counters surfaced via [Stats].
  int packetsForwarded = 0;
  int bytesForwarded = 0;
  int packetsDroppedWrongLayer = 0;

  /// Phase 7 — number of outbound primary packets that were
  /// successfully stamped with a TWCC sequence number.
  int packetsTwccStamped = 0;

  /// Phase 7 — subscriber-wide transport-cc seq stamper. Null when
  /// the subscriber did not negotiate the transport-cc extension.
  final TwccStamper? twccStamper;

  /// Phase 10 — buffer pool used for the rewritten copy. Defaults to
  /// the per-isolate [BytePool.instance].
  final BytePool pool;

  /// Phase B8 — optional per-subscriber leaky-bucket pacer. When set,
  /// every outbound primary + RTX packet that would otherwise have
  /// gone directly through the SRTP transport is enqueued here
  /// instead. Drains on the pacer's own [Timer.periodic]. The
  /// load-test [rtpSink] fast path bypasses the pacer entirely — it
  /// already replaces the transport, and load tests want a tight
  /// loop with no smoothing.
  final LeakyBucketPacer? pacer;

  /// Phase G — synthetic packet-loss simulator. When set to a value
  /// in (0, 1] the DownTrack drops each *primary* outbound packet
  /// with this probability before handing it to the transport / sink,
  /// independently of any real-network conditions. RTX packets are
  /// never dropped — they're already retransmits, and dropping them
  /// would defeat the test setup. Defaults to 0 (no synthetic loss).
  ///
  /// Used by chaos / loss-recovery tests; should remain 0 in prod.
  double dropProbability = 0.0;

  /// Counter incremented every time the loss simulator dropped a
  /// packet. Surfaced via stats so tests can assert on it.
  int packetsDroppedSimulator = 0;

  /// PRNG backing [dropProbability]. Override in tests for
  /// deterministic drops; defaults to a freshly-seeded [Random].
  Random lossRng = Random();

  /// Phase 10 — optional injected sink used **instead of** the real
  /// SRTP transport. The load-test harness sets this to a counting
  /// closure so the forward path can be exercised without a live
  /// PeerConnection. When set, [rtcpSink] should usually be set too.
  void Function(Uint8List rtp)? rtpSink;
  void Function(Uint8List rtcp)? rtcpSink;

  /// Test seam: drop-in replacement for the real-transport egress
  /// path. When set, [writeRtp] / [replay] skip the
  /// `subscriberPc.activePeer` / `subscriberPc.transport` lookup and
  /// route packets through this closure instead. Lets unit tests
  /// exercise the post-guard branches (rewrite/jitter/twcc/pacer
  /// engagement, counter bookkeeping) without standing up a live
  /// DTLS peer. Distinct from [rtpSink], which models the load-test
  /// fast path that bypasses the pacer entirely. Not part of the
  /// public API.
  void Function(Uint8List rtp, bool isRtx)? transportSinkForTest;

  /// Jitter buffer of forwarded primary RTP packets, keyed by the
  /// *rewritten* sequence number. Used by [NackResponder] to satisfy
  /// subscriber retransmit requests without involving the publisher.
  final JitterBuffer _jitter;
  late final NackResponder nack;

  bool _closed = false;

  DownTrack({
    required this.id,
    required this.receiver,
    required this.transceiver,
    required this.subscriberPc,
    required this.rewrittenPrimarySsrc,
    required this.rewrittenRtxSsrc,
    int jitterCapacity = 512,
    this.twccStamper,
    BytePool? pool,
    this.rtpSink,
    this.rtcpSink,
    this.pacer,
  })  : pool = pool ?? BytePool.instance,
        _jitter = JitterBuffer(
          capacity: jitterCapacity,
          onEvict: (buf) => (pool ?? BytePool.instance).release(buf),
        ),
        trackType = receiver.isSimulcast
            ? DownTrackType.simulcast
            : DownTrackType.simple,
        _rewriter = SimulcastRewriter(
          rewrittenPrimarySsrc: rewrittenPrimarySsrc,
          rewrittenRtxSsrc: rewrittenRtxSsrc,
          currentLayer: receiver.stream.defaultLayer.rid,
          pool: pool,
          // Auto-wire a codec-specific keyframe detector when the
          // publisher negotiated a codec we know how to inspect. For
          // other codecs the gate stays off and we fall back to the
          // legacy behavior (offset rebased on first primary
          // regardless of frame type).
          isKeyframe: receiver.codecs.any((c) => c.name == 'VP8')
              ? isVp8Keyframe
              : receiver.codecs.any((c) => c.name == 'VP9')
                  ? isVp9Keyframe
                  : receiver.codecs.any((c) => c.name == 'H264')
                      ? isH264Keyframe
                      : null,
        ) {
    nack = NackResponder(buffer: _jitter);
    // Phase 8 — build the SSRC translation map for RTCP rewriting.
    // Every layer's primary + optional RTX maps to the rewritten
    // SSRC pair, so SRs from any layer translate correctly.
    for (final l in receiver.stream.layers) {
      if (l.primarySsrc != 0) {
        _ssrcMap.primary[l.primarySsrc] = rewrittenPrimarySsrc;
      }
      if (l.rtxSsrc != null && l.rtxSsrc != 0 && rewrittenRtxSsrc != null) {
        _ssrcMap.rtx[l.rtxSsrc!] = rewrittenRtxSsrc!;
      }
    }
    _removeSsrcListener = receiver.addSsrcListener(_onReceiverSsrcLearned);
  }

  /// Phase 8 — publisher→subscriber SSRC translation table for SR/RR
  /// rewriting. Populated at construction; extended at runtime when
  /// RID-discovery binds new SSRCs.
  final RtcpSsrcMap _ssrcMap = RtcpSsrcMap();
  void Function()? _removeSsrcListener;

  void _onReceiverSsrcLearned(int ssrc, ProducerLayer layer,
      {required bool isRtx}) {
    if (isRtx) {
      if (rewrittenRtxSsrc != null) _ssrcMap.rtx[ssrc] = rewrittenRtxSsrc!;
    } else {
      _ssrcMap.primary[ssrc] = rewrittenPrimarySsrc;
    }
  }

  bool get isClosed => _closed;

  /// RID of the layer currently being forwarded.
  String get currentLayer => _rewriter.currentLayer;

  /// Number of times [setCurrentLayer] actually changed the layer.
  int get layerSwitches => _rewriter.layerSwitches;

  /// True while a layer switch requested via [setCurrentLayer] is
  /// still waiting for its first primary packet on the new layer
  /// (the keyframe boundary). Used by the BWE / layer-selector to
  /// avoid queuing a second switch on top of an in-flight one.
  bool get switchInFlight => _rewriter.switchInFlight;

  /// Number of [setCurrentLayer] calls that were rejected because a
  /// previously-requested switch was still in flight. Surfaced for
  /// observability — a healthy stream sees this counter at 0.
  int layerSwitchRejected = 0;

  /// Wall-clock of the last upstream PLI / keyframe request emitted
  /// for this DownTrack. The subscriber-side feedback path uses this
  /// to enforce a minimum gap (default 500 ms) so a misbehaving
  /// viewer can't spam PLI and induce a keyframe storm at the
  /// publisher (which costs uplink bitrate at the source AND in every
  /// downstream SFU hop).
  DateTime? lastUpstreamPliAt;

  /// Number of upstream PLI requests suppressed by the throttle.
  int pliRateLimited = 0;

  /// Minimum gap between two upstream PLI requests for this
  /// DownTrack. Mirrors ion-sfu's 500 ms guard
  /// (pkg/sfu/receiver.go#L266). Public for tests / configuration.
  static const Duration minUpstreamPliGap = Duration(milliseconds: 500);

  /// Returns true and updates [lastUpstreamPliAt] iff a new upstream
  /// PLI may be sent at [now] given the throttle. Returns false
  /// (and increments [pliRateLimited]) when the previous PLI is too
  /// recent. Pure helper so the throttle can be unit-tested without
  /// spinning up a Subscriber + publisher transport.
  bool tryConsumePliCredit(DateTime now) {
    if (!_pliThrottleAllow(lastUpstreamPliAt, now, minUpstreamPliGap)) {
      pliRateLimited++;
      return false;
    }
    lastUpstreamPliAt = now;
    return true;
  }

  /// Switch the forwarded simulcast layer to [rid]. No-op when this
  /// track is not simulcast or when the requested layer is unknown.
  /// Returns true if the layer changed.
  bool setCurrentLayer(String rid) {
    if (trackType != DownTrackType.simulcast) return false;
    final exists = receiver.layers.any((l) => l.rid == rid);
    if (!exists) return false;
    if (_rewriter.switchInFlight && _rewriter.currentLayer != rid) {
      // A prior switch hasn't landed its first keyframe yet — forcing
      // another switch now would leave the SN/TS offsets half-applied
      // and the subscriber's decoder would see a glitch on every
      // re-flip. Reject and let the selector retry on the next tick.
      layerSwitchRejected++;
      return false;
    }
    return _rewriter.setCurrentLayer(rid);
  }

  /// Push one publisher RTP packet to this subscriber's transport.
  /// [layer] is the producer-side layer the packet belongs to (resolved
  /// by [Receiver.deliverRtp]); [isRtx] is true for RFC 4588 RTX
  /// packets. Packets from layers other than [currentLayer] are
  /// silently dropped.
  void writeRtp(ProducerLayer layer, bool isRtx, Uint8List rtp) {
    if (_closed || rtp.length < 12) return;
    if (layer.rid != _rewriter.currentLayer) {
      packetsDroppedWrongLayer++;
      return;
    }

    // Phase G — synthetic packet-loss simulator. Applied here so it
    // affects both the load-test sink and the real transport path.
    // RTX retransmits bypass the simulator (dropping them defeats
    // the test setup, since they're already loss-recovery traffic).
    if (!isRtx && dropProbability > 0.0) {
      if (lossRng.nextDouble() < dropProbability) {
        packetsDroppedSimulator++;
        return;
      }
    }

    // Resolve the egress mode. Order:
    //   1. rtpSink (load-test fast path, bypasses pacer)
    //   2. transportSinkForTest (unit-test seam, bypasses guard)
    //   3. real transport (subscriberPc.activePeer / .transport)
    final sink = rtpSink;
    final testSend = transportSinkForTest;
    RtcPeerTransport? peer;
    RtcUdpTransport? transport;
    if (sink == null && testSend == null) {
      peer = subscriberPc.activePeer;
      transport = subscriberPc.transport;
      if (peer == null || transport == null || !peer.isSecure) return;
    }

    final r = _rewriter.rewrite(rid: layer.rid, isRtx: isRtx, rtp: rtp);
    if (r.dropped) {
      packetsDroppedWrongLayer++;
      return;
    }
    final out = r.out!;
    if (!isRtx && r.outSeq != null) {
      _jitter.record(r.outSeq!, out);
    }
    // Phase 7 — stamp the transport-cc seq number on outbound primary
    // packets when the receiver negotiated transport-cc. RTX packets
    // are skipped (the original primary was already stamped, and the
    // browser correlates by the OSN in the RTX payload).
    final twccId = receiver.stream.twccExtId;
    if (!isRtx && twccId != null && twccStamper != null) {
      final seq = twccStamper!.stamp(out, twccId);
      if (seq != null) packetsTwccStamped++;
    }
    if (sink != null) {
      sink(out);
    } else if (pacer != null) {
      // Pacer takes ownership of the buffer; bytesForwarded is
      // accounted at enqueue time so subscriber-level BWE bookkeeping
      // (which deltas off bytesForwarded) stays correct.
      pacer!.enqueue(out, isRtx: isRtx);
    } else if (testSend != null) {
      testSend(out, isRtx);
    } else {
      transport!.sendRtp(peer!, out);
    }
    packetsForwarded++;
    bytesForwarded += out.length;
    // Pool release: RTX buffers aren't retained by the jitter buffer.
    // The pacer takes ownership when engaged, so release only when we
    // bypass it (sink branch always releases on RTX; real branch /
    // test-seam releases only when no pacer).
    if (isRtx && pacer == null) pool.release(out);
  }

  /// Forward inbound publisher RTCP. Phase 8 — rewrites SR/RR so the
  /// SSRCs and (for SR) the RTP timestamp match the subscriber's view
  /// of the stream. Other RTCP types pass through unchanged. Compound
  /// packets are walked sub-packet by sub-packet.
  void writeRtcp(Uint8List rtcp) {
    if (_closed) return;
    final sink = rtcpSink;
    RtcPeerTransport? peer;
    RtcUdpTransport? transport;
    if (sink == null) {
      peer = subscriberPc.activePeer;
      transport = subscriberPc.transport;
      if (peer == null || transport == null || !peer.isSecure) return;
    }
    final out = rewriteRtcpForSubscriber(
      rtcp,
      _ssrcMap,
      tsOffsetFor: (publisherSsrc) {
        // Only translate timestamps for the layer we're currently
        // forwarding — SRs for other layers are still SSRC-rewritten
        // (so the browser ignores them gracefully) but their RTP ts
        // is left alone since the rewritten SSRC won't match anyway.
        final off = _rewriter.currentLayerOffset();
        if (off == null) return null;
        // Match only the current layer's primary publisher SSRC. RTX
        // SR is rare in practice and we leave its timestamp alone.
        for (final l in receiver.stream.layers) {
          if (l.rid != _rewriter.currentLayer) continue;
          if (l.primarySsrc == publisherSsrc) return off.tsOffset;
        }
        return null;
      },
    );
    if (sink != null) {
      sink(out);
    } else {
      transport!.sendRtcp(peer!, out);
    }
  }

  /// Replay [packets] (already SSRC-rewritten primary packets fetched
  /// from this DownTrack's jitter buffer) toward the subscriber. Used
  /// by the NACK responder.
  void replay(List<Uint8List> packets) {
    if (_closed) return;
    final testSend = transportSinkForTest;
    RtcPeerTransport? peer;
    RtcUdpTransport? transport;
    if (testSend == null) {
      peer = subscriberPc.activePeer;
      transport = subscriberPc.transport;
      if (peer == null || transport == null || !peer.isSecure) return;
    }
    for (final p in packets) {
      if (pacer != null) {
        pacer!.enqueue(p, isRtx: false);
      } else if (testSend != null) {
        testSend(p, false);
      } else {
        transport!.sendRtp(peer!, p);
      }
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _removeSsrcListener?.call();
  }
}

/// Pure throttle predicate, exported so the rate-limit logic itself
/// can be unit-tested without instantiating a full DownTrack. Returns
/// true iff [now] is at least [minGap] after [lastSentAt] (or
/// [lastSentAt] is null \u2014 i.e. nothing sent yet).
bool _pliThrottleAllow(DateTime? lastSentAt, DateTime now, Duration minGap) {
  if (lastSentAt == null) return true;
  return now.difference(lastSentAt) >= minGap;
}

/// Public re-export of [_pliThrottleAllow] under a stable name. Tests
/// in the package consume this; production code should prefer
/// [DownTrack.tryConsumePliCredit] which carries the per-track state.
bool pliThrottleAllowForTest(
        DateTime? lastSentAt, DateTime now, Duration minGap) =>
    _pliThrottleAllow(lastSentAt, now, minGap);
