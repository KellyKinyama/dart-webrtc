// Receiver — one inbound publisher track. Holds the codec metadata,
// resolved primary/RTX SSRC pair (per layer for simulcast tracks), and
// the list of DownTracks subscribed to it.
//
// Mirrors `pkg/sfu/receiver.go` (the simple, non-simulcast slice plus
// the SIM-group simulcast extensions added in Phase 3).

import 'dart:typed_data';

import 'package:pure_dart_webrtc/signal/sdp_v2.dart' show SdpCodec;
import 'package:pure_dart_webrtc/webrtc/webrtc.dart' show MediaKind;

import 'down_track.dart';
import 'producer_layer.dart';
import 'producer_stream.dart';

class Receiver {
  /// Stable id (`<peerId>:<mid>`).
  final String id;

  /// Owning publisher peer id.
  final String peerId;

  final MediaKind kind;
  final List<SdpCodec> codecs;

  /// Producer-side stream description (SSRCs, cname, msid, layers). Set
  /// by the router as soon as the publisher offer is parsed.
  final ProducerStream stream;

  /// inbound primary SSRC → layer.
  final Map<int, ProducerLayer> _byPrimarySsrc = {};

  /// inbound RTX SSRC → layer.
  final Map<int, ProducerLayer> _byRtxSsrc = {};

  final List<DownTrack> _downTracks = [];

  bool _closed = false;

  Receiver({
    required this.id,
    required this.peerId,
    required this.kind,
    required this.codecs,
    required this.stream,
  }) {
    for (final l in stream.layers) {
      _byPrimarySsrc[l.primarySsrc] = l;
      if (l.rtxSsrc != null) _byRtxSsrc[l.rtxSsrc!] = l;
    }
  }

  /// Convenience accessor — the default layer's primary SSRC.
  int get primarySsrc => stream.primarySsrc;

  /// Default layer's RTX SSRC (or null).
  int? get rtxSsrc => stream.rtxSsrc;

  bool get isClosed => _closed;
  List<DownTrack> get downTracks => List.unmodifiable(_downTracks);
  bool get isSimulcast => stream.isSimulcast;
  Iterable<ProducerLayer> get layers => stream.layers;

  void attachDownTrack(DownTrack dt) {
    if (_closed) return;
    _downTracks.add(dt);
  }

  void detachDownTrack(DownTrack dt) {
    _downTracks.remove(dt);
  }

  /// Publisher → subscribers fast-path. Resolves which simulcast layer
  /// the inbound packet belongs to (by SSRC) and forwards to every
  /// attached DownTrack with the layer + isRtx flag pre-resolved.
  void deliverRtp(Uint8List rtp) {
    if (_closed || rtp.length < 12) return;
    final ssrc = (rtp[8] << 24) | (rtp[9] << 16) | (rtp[10] << 8) | rtp[11];
    final primaryLayer = _byPrimarySsrc[ssrc];
    final rtxLayer = primaryLayer == null ? _byRtxSsrc[ssrc] : null;
    final layer = primaryLayer ?? rtxLayer;
    if (layer == null) return;
    final isRtx = rtxLayer != null;

    // Snapshot to avoid concurrent-modification if a DownTrack closes
    // during iteration.
    final snap = List<DownTrack>.from(_downTracks, growable: false);
    for (final dt in snap) {
      dt.writeRtp(layer, isRtx, rtp);
    }
  }

  void deliverRtcp(Uint8List rtcp) {
    if (_closed) return;
    final snap = List<DownTrack>.from(_downTracks, growable: false);
    for (final dt in snap) {
      dt.writeRtcp(rtcp);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    final snap = List<DownTrack>.from(_downTracks, growable: false);
    for (final dt in snap) {
      dt.close();
    }
    _downTracks.clear();
  }
}
