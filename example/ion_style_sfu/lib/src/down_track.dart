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

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

import 'buffer/buffer.dart';
import 'buffer/nack.dart';
import 'producer_layer.dart';
import 'receiver.dart';
import 'rtcp_rewrite.dart';
import 'simulcast_rewriter.dart';
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
  })  : _jitter = JitterBuffer(capacity: jitterCapacity),
        trackType = receiver.isSimulcast
            ? DownTrackType.simulcast
            : DownTrackType.simple,
        _rewriter = SimulcastRewriter(
          rewrittenPrimarySsrc: rewrittenPrimarySsrc,
          rewrittenRtxSsrc: rewrittenRtxSsrc,
          currentLayer: receiver.stream.defaultLayer.rid,
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

  /// Switch the forwarded simulcast layer to [rid]. No-op when this
  /// track is not simulcast or when the requested layer is unknown.
  /// Returns true if the layer changed.
  bool setCurrentLayer(String rid) {
    if (trackType != DownTrackType.simulcast) return false;
    final exists = receiver.layers.any((l) => l.rid == rid);
    if (!exists) return false;
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
    final peer = subscriberPc.activePeer;
    final transport = subscriberPc.transport;
    if (peer == null || transport == null || !peer.isSecure) return;

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
    transport.sendRtp(peer, out);
    packetsForwarded++;
    bytesForwarded += out.length;
  }

  /// Forward inbound publisher RTCP. Phase 8 — rewrites SR/RR so the
  /// SSRCs and (for SR) the RTP timestamp match the subscriber's view
  /// of the stream. Other RTCP types pass through unchanged. Compound
  /// packets are walked sub-packet by sub-packet.
  void writeRtcp(Uint8List rtcp) {
    if (_closed) return;
    final peer = subscriberPc.activePeer;
    final transport = subscriberPc.transport;
    if (peer == null || transport == null || !peer.isSecure) return;
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
    transport.sendRtcp(peer, out);
  }

  /// Replay [packets] (already SSRC-rewritten primary packets fetched
  /// from this DownTrack's jitter buffer) toward the subscriber. Used
  /// by the NACK responder.
  void replay(List<Uint8List> packets) {
    if (_closed) return;
    final peer = subscriberPc.activePeer;
    final transport = subscriberPc.transport;
    if (peer == null || transport == null || !peer.isSecure) return;
    for (final p in packets) {
      transport.sendRtp(peer, p);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _removeSsrcListener?.call();
  }
}
