// Router — per-publisher fan-out hub. Owns the [Receiver] table for one
// peer's published tracks, and forwards inbound RTP/RTCP to every
// [DownTrack] attached to those receivers.
//
// Mirrors `pkg/sfu/router.go`.

import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

import 'producer_stream.dart';
import 'receiver.dart';
import 'rtcp.dart';
import 'sdp_helpers.dart';
import 'session.dart';

class Router {
  /// Owning peer id (the publisher this router belongs to).
  final String peerId;

  /// Session this router publishes into.
  final Session session;

  /// primarySsrc → Receiver.
  final Map<int, Receiver> _byPrimarySsrc = {};

  /// rtxSsrc → Receiver (so we can recognise RTX retransmissions).
  final Map<int, Receiver> _byRtxSsrc = {};

  /// receiverId → Receiver.
  final Map<String, Receiver> _byId = {};

  /// One sequence-gap detector per primary SSRC. Drives upstream NACK.
  final Map<int, SeqGapDetector> _gap = {};

  /// Hook: Router asks the owner (Publisher) to send [pkt] (an RTCP
  /// NACK or PLI) upstream toward the publishing browser. Publisher
  /// installs this when constructing the router.
  void Function(Uint8List pkt)? onUpstreamFeedback;

  bool _closed = false;

  Router({required this.peerId, required this.session});

  Iterable<Receiver> get receivers => _byId.values;

  /// Look up the receiver carrying [ssrc], whether it's the primary or
  /// the RTX SSRC.
  Receiver? receiverForSsrc(int ssrc) =>
      _byPrimarySsrc[ssrc] ?? _byRtxSsrc[ssrc];

  /// Apply an updated publisher offer. Parses [offerSdp] for `a=ssrc`
  /// and `a=ssrc-group:FID` lines, creates one [Receiver] per primary
  /// SSRC, and notifies the session so subscribers wire up DownTracks
  /// before the first packet lands. Idempotent: re-running with the
  /// same SSRCs is a no-op.
  void bindToRemoteOffer(RTCPeerConnection pc, String offerSdp) {
    if (_closed) return;
    final streams = parsePublisherOffer(peerId: peerId, offerSdp: offerSdp);
    if (streams.isEmpty) return;

    final tx = pc.getTransceivers();
    final pendingByKind = <MediaKind, List<RTCRtpTransceiver>>{
      MediaKind.video: [],
      MediaKind.audio: [],
    };
    for (final t in tx) {
      pendingByKind[t.kind]?.add(t);
    }

    for (final s in streams) {
      if (_byPrimarySsrc.containsKey(s.primarySsrc)) continue;
      final mediaKind = s.kind == 'video' ? MediaKind.video : MediaKind.audio;
      final pool = pendingByKind[mediaKind]!;
      if (pool.isEmpty) continue;
      final transceiver = pool.removeAt(0);
      final id = '$peerId:${transceiver.mid ?? s.mid}';
      final receiver = Receiver(
        id: id,
        peerId: peerId,
        kind: mediaKind,
        codecs: transceiver.codecs,
        stream: s,
      );
      _byId[id] = receiver;
      _byPrimarySsrc[s.primarySsrc] = receiver;
      if (s.rtxSsrc != null) _byRtxSsrc[s.rtxSsrc!] = receiver;
      session.publish(this, receiver);
    }
  }

  /// Forward an inbound publisher RTP packet. Routes by the SSRC field
  /// at offset 8. Also feeds the per-stream sequence-gap detector and,
  /// when a gap is detected, asks the publisher to NACK upstream so
  /// the missing packets are retransmitted (and can subsequently be
  /// fanned out / cached for subscriber-side NACK).
  void routeRtp(Uint8List rtp) {
    if (_closed || rtp.length < 12) return;
    final ssrc = (rtp[8] << 24) | (rtp[9] << 16) | (rtp[10] << 8) | rtp[11];
    final receiver = receiverForSsrc(ssrc);
    if (receiver == null) return;
    receiver.deliverRtp(rtp);

    // Only run gap detection on primary SSRCs (RTX retransmissions
    // legitimately arrive out of order).
    if (ssrc == receiver.primarySsrc) {
      final det = _gap.putIfAbsent(ssrc, SeqGapDetector.new);
      final seq = (rtp[2] << 8) | rtp[3];
      final missing = det.feed(seq);
      if (missing.isNotEmpty && onUpstreamFeedback != null) {
        onUpstreamFeedback!(buildNack(1, ssrc, missing));
      }
    }
  }

  /// Forward an inbound publisher RTCP compound packet to every
  /// receiver. Subscriber-side feedback (NACK/PLI from a remote viewer)
  /// is *not* delivered here — it travels in via subscriber-side
  /// reverse-mapping.
  ///
  /// Phase 5 will parse SR/RR here and feed REMB/TWCC.
  void routeRtcp(Uint8List rtcp) {
    if (_closed) return;
    for (final r in _byId.values) {
      r.deliverRtcp(rtcp);
    }
  }

  /// All declared producer streams (one per receiver).
  List<ProducerStream> get producerStreams =>
      [for (final r in _byId.values) r.stream];

  void close() {
    if (_closed) return;
    _closed = true;
    for (final r in _byId.values) {
      r.close();
    }
    _byId.clear();
    _byPrimarySsrc.clear();
    _byRtxSsrc.clear();
    _gap.clear();
  }
}
