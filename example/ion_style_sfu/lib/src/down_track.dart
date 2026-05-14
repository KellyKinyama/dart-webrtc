// DownTrack — one outbound stream from the SFU to a single subscriber,
// pairing a `Receiver` (the producer side) with the subscriber's
// PeerConnection (the consumer side).
//
// Mirrors `pkg/sfu/downtrack.go`. Phase 2 introduces SSRC rewriting and
// the per-track jitter buffer that backs NACK retransmission.

import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

import 'buffer/buffer.dart';
import 'buffer/nack.dart';
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

  /// Phase 3 will use this to pick a simulcast layer per subscriber.
  DownTrackType trackType = DownTrackType.simple;

  /// Phase 3: sequence-number / timestamp offsets so a layer switch (or
  /// publisher restart) doesn't desync the receiver.
  int snOffset = 0;
  int tsOffset = 0;

  /// Counters surfaced via [Stats].
  int packetsForwarded = 0;
  int bytesForwarded = 0;

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
  }) : _jitter = JitterBuffer(capacity: jitterCapacity) {
    nack = NackResponder(buffer: _jitter);
  }

  bool get isClosed => _closed;

  /// Push one publisher RTP packet to this subscriber's transport.
  /// Routes by the inbound SSRC: primary or RTX (RFC 4588). The packet
  /// is copied so the original buffer stays intact for other
  /// subscribers, then the SSRC field at offset 8 is overwritten with
  /// the rewritten value the subscriber expects.
  void writeRtp(Uint8List rtp) {
    if (_closed || rtp.length < 12) return;
    final peer = subscriberPc.activePeer;
    final transport = subscriberPc.transport;
    if (peer == null || transport == null || !peer.isSecure) return;

    final ssrc = (rtp[8] << 24) | (rtp[9] << 16) | (rtp[10] << 8) | rtp[11];
    final isRtx = ssrc == receiver.rtxSsrc;
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
