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
import 'simulcast_rewriter.dart';

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
    transport.sendRtp(peer, out);
    packetsForwarded++;
    bytesForwarded += out.length;
  }

  /// Forward inbound publisher RTCP. Phase 2 deliberately *drops*
  /// publisher RTCP rather than relaying it: the rewritten SSRC space
  /// makes the publisher's SR/RR meaningless to the subscriber, and
  /// browsers generate their own RR independently. Phase 5 will rewrite
  /// SR/RR per subscriber and re-enable forwarding.
  void writeRtcp(Uint8List rtcp) {
    if (_closed) return;
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
  }
}
