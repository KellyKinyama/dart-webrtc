// Phase 3b — testable simulcast SN/TS rewrite engine, extracted from
// DownTrack so the offset arithmetic can be verified in isolation
// (without spinning up a real DTLS transport).
//
// Maintains per-layer (snOffset, tsOffset) pairs that are recomputed on
// every layer switch so the outbound stream stays monotonically
// continuous regardless of which producer layer is currently being
// forwarded.

import 'dart:typed_data';

import 'byte_pool.dart';
import 'rtp_header.dart';

class _LayerOffset {
  int snOffset;
  int tsOffset;
  _LayerOffset(this.snOffset, this.tsOffset);
}

/// Outcome of rewriting a single packet.
class RewriteResult {
  /// The rewritten packet (mutated copy of the input). Null when the
  /// packet was dropped (RTX before its layer's primary baseline).
  final Uint8List? out;

  /// Outbound primary sequence number for this layer. Null for RTX or
  /// for dropped packets.
  final int? outSeq;

  /// Outbound primary timestamp for this layer. Null for RTX or for
  /// dropped packets.
  final int? outTs;

  /// True when the packet was rewritten as RTX.
  final bool isRtx;

  const RewriteResult({
    required this.out,
    required this.outSeq,
    required this.outTs,
    required this.isRtx,
  });

  bool get dropped => out == null;
}

/// Rewrites publisher-side RTP packets onto a single outbound SSRC pair
/// (primary + optional RTX) while preserving SN/TS continuity across
/// simulcast layer switches. One instance per DownTrack.
class SimulcastRewriter {
  final int rewrittenPrimarySsrc;
  final int? rewrittenRtxSsrc;

  /// Currently forwarded layer's RID. Empty string for non-simulcast.
  String currentLayer;

  /// Phase 10 — buffer pool used to allocate the rewritten copy. Defaults
  /// to the per-isolate [BytePool.instance]; tests/benches may override.
  final BytePool pool;

  /// Optional codec-specific keyframe detector. When set and a layer
  /// switch is in flight, the rewriter drops every primary packet on
  /// the new layer until [isKeyframe] returns true — this prevents
  /// the decoder from receiving a partial GOP that references frames
  /// it never saw.
  final bool Function(Uint8List rtp)? isKeyframe;

  /// Counter incremented every time the keyframe gate dropped a
  /// non-keyframe primary while waiting for the resync boundary.
  int gateDropped = 0;

  final Map<String, _LayerOffset> _layerOffsets = {};
  bool _resyncOnNext = true;

  int _lastOutSeq = 0;
  int _lastOutTs = 0;
  bool _haveLastOut = false;

  int layerSwitches = 0;

  SimulcastRewriter({
    required this.rewrittenPrimarySsrc,
    required this.rewrittenRtxSsrc,
    required this.currentLayer,
    BytePool? pool,
    this.isKeyframe,
  }) : pool = pool ?? BytePool.instance;

  /// True while a previously-requested layer switch is still
  /// waiting for its first primary packet to arrive (the keyframe
  /// boundary). Subscribers that flip the layer mid-switch end up
  /// with a half-applied offset and decoder corruption, so DownTrack
  /// uses this to gate further [setCurrentLayer] calls.
  bool get switchInFlight => _resyncOnNext;

  /// Switch the forwarded layer. Returns true when [rid] differs from
  /// the prior current layer (i.e. a real switch happened).
  bool setCurrentLayer(String rid) {
    if (currentLayer == rid) return false;
    currentLayer = rid;
    _layerOffsets.remove(rid);
    _resyncOnNext = true;
    layerSwitches++;
    return true;
  }

  /// Phase 8 — current layer's (snOffset, tsOffset) pair, or null when
  /// the layer hasn't seen a primary packet yet (so no offset has been
  /// computed). Used by SR rewriting to align the publisher's RTP
  /// timestamp into the rewritten timeline.
  ({int snOffset, int tsOffset})? currentLayerOffset() {
    final off = _layerOffsets[currentLayer];
    if (off == null) return null;
    return (snOffset: off.snOffset, tsOffset: off.tsOffset);
  }

  /// Rewrite [rtp] (a publisher-side packet on layer [rid]) onto this
  /// DownTrack's outbound SSRC space. [isRtx] marks RFC 4588 RTX
  /// packets; their embedded OSN field is shifted by the layer's
  /// snOffset so it still points at the rewritten primary sequence
  /// number.
  RewriteResult rewrite({
    required String rid,
    required bool isRtx,
    required Uint8List rtp,
  }) {
    if (rtp.length < 12) {
      return const RewriteResult(
          out: null, outSeq: null, outTs: null, isRtx: false);
    }
    final inSeq = rtpSeq(rtp);
    final inTs = rtpTimestamp(rtp);

    var off = _layerOffsets[rid];
    if (!isRtx && (off == null || _resyncOnNext)) {
      // reSync keyframe gate — if a codec-specific keyframe detector
      // was supplied, refuse to baseline this layer until a keyframe
      // lands. Drops any leading delta frames so the decoder sees a
      // clean GOP boundary on layer switch.
      final det = isKeyframe;
      if (det != null && !det(rtp)) {
        gateDropped++;
        return const RewriteResult(
            out: null, outSeq: null, outTs: null, isRtx: false);
      }
      final baseSeq = _haveLastOut ? ((_lastOutSeq + 1) & 0xffff) : inSeq;
      final baseTs = _haveLastOut ? ((_lastOutTs + 1) & 0xffffffff) : inTs;
      off = _LayerOffset(
        (baseSeq - inSeq) & 0xffff,
        (baseTs - inTs) & 0xffffffff,
      );
      _layerOffsets[rid] = off;
      _resyncOnNext = false;
    }
    if (off == null) {
      // RTX arrived before we ever forwarded a primary on this layer.
      return const RewriteResult(
          out: null, outSeq: null, outTs: null, isRtx: true);
    }

    final outSsrc = isRtx
        ? (rewrittenRtxSsrc ?? rewrittenPrimarySsrc)
        : rewrittenPrimarySsrc;

    final out = pool.acquireFrom(rtp);
    out[8] = (outSsrc >> 24) & 0xff;
    out[9] = (outSsrc >> 16) & 0xff;
    out[10] = (outSsrc >> 8) & 0xff;
    out[11] = outSsrc & 0xff;

    if (!isRtx) {
      final outSeq = (inSeq + off.snOffset) & 0xffff;
      final outTs = (inTs + off.tsOffset) & 0xffffffff;
      writeRtpSeq(out, outSeq);
      writeRtpTimestamp(out, outTs);
      _lastOutSeq = outSeq;
      _lastOutTs = outTs;
      _haveLastOut = true;
      return RewriteResult(
          out: out, outSeq: outSeq, outTs: outTs, isRtx: false);
    } else {
      final payloadOff = rtpPayloadOffset(out);
      if (payloadOff + 2 > out.length) {
        return const RewriteResult(
            out: null, outSeq: null, outTs: null, isRtx: true);
      }
      final origOsn = (out[payloadOff] << 8) | out[payloadOff + 1];
      final newOsn = (origOsn + off.snOffset) & 0xffff;
      out[payloadOff] = (newOsn >> 8) & 0xff;
      out[payloadOff + 1] = newOsn & 0xff;
      writeRtpSeq(out, (inSeq + off.snOffset) & 0xffff);
      return RewriteResult(out: out, outSeq: null, outTs: null, isRtx: true);
    }
  }
}
