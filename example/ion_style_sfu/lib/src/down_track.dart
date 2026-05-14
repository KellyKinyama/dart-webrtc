// DownTrack — one outbound stream from the SFU to a single subscriber,
// pairing a `Receiver` (the producer side) with the subscriber's
// PeerConnection (the consumer side).
//
// Mirrors `pkg/sfu/downtrack.go`. Phase 2 introduces SSRC rewriting and
// the per-track jitter buffer that backs NACK retransmission. Phase 3
// adds simulcast layer filtering — packets from layers other than
// [currentLayer] are dropped, so the subscriber only ever sees one
// continuous SSRC stream regardless of how many the publisher sends.

import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

import 'buffer/buffer.dart';
import 'buffer/nack.dart';
import 'producer_layer.dart';
import 'receiver.dart';

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

  /// RID of the layer we're currently forwarding. Empty string for
  /// non-simulcast receivers (matches the single layer's empty rid).
  /// Updated via [setCurrentLayer].
  String currentLayer;

  /// Phase 4: sequence-number / timestamp offsets so a layer switch (or
  /// publisher restart) doesn't desync the receiver.
  int snOffset = 0;
  int tsOffset = 0;

  /// Counters surfaced via [Stats].
  int packetsForwarded = 0;
  int bytesForwarded = 0;
  int packetsDroppedWrongLayer = 0;

  /// Jitter buffer of forwarded primary RTP packets, keyed by sequence
  /// number. Used by [NackResponder] to satisfy subscriber retransmit
  /// requests without involving the publisher.
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
        currentLayer = receiver.stream.defaultLayer.rid {
    nack = NackResponder(buffer: _jitter);
  }

  bool get isClosed => _closed;

  /// Switch the forwarded simulcast layer to [rid]. No-op when this
  /// track is not simulcast or when the requested layer is unknown.
  /// Returns true if the layer changed.
  bool setCurrentLayer(String rid) {
    if (trackType != DownTrackType.simulcast) return false;
    if (currentLayer == rid) return false;
    final exists = receiver.layers.any((l) => l.rid == rid);
    if (!exists) return false;
    currentLayer = rid;
    return true;
  }

  /// Push one publisher RTP packet to this subscriber's transport.
  /// [layer] is the producer-side layer the packet belongs to (resolved
  /// by [Receiver.deliverRtp]); [isRtx] is true for RFC 4588 RTX
  /// packets. Packets from layers other than [currentLayer] are
  /// silently dropped.
  void writeRtp(ProducerLayer layer, bool isRtx, Uint8List rtp) {
    if (_closed || rtp.length < 12) return;
    if (layer.rid != currentLayer) {
      packetsDroppedWrongLayer++;
      return;
    }
    final peer = subscriberPc.activePeer;
    final transport = subscriberPc.transport;
    if (peer == null || transport == null || !peer.isSecure) return;

    final outSsrc = isRtx
        ? (rewrittenRtxSsrc ?? rewrittenPrimarySsrc)
        : rewrittenPrimarySsrc;

    final out = Uint8List.fromList(rtp);
    out[8] = (outSsrc >> 24) & 0xff;
    out[9] = (outSsrc >> 16) & 0xff;
    out[10] = (outSsrc >> 8) & 0xff;
    out[11] = outSsrc & 0xff;

    if (!isRtx) {
      final seq = (out[2] << 8) | out[3];
      _jitter.record(seq, out);
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
