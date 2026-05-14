// Receiver — one inbound publisher track. Holds the codec metadata,
// resolved primary/RTX SSRC pair, and the list of DownTracks
// subscribed to it.
//
// Mirrors `pkg/sfu/receiver.go` (the simple, non-simulcast slice).

import 'dart:typed_data';

import 'package:pure_dart_webrtc/signal/sdp_v2.dart' show SdpCodec;
import 'package:pure_dart_webrtc/webrtc/webrtc.dart' show MediaKind;

import 'down_track.dart';
import 'producer_stream.dart';

class Receiver {
  /// Stable id (`<peerId>:<mid>`).
  final String id;

  /// Owning publisher peer id.
  final String peerId;

  final MediaKind kind;
  final List<SdpCodec> codecs;

  /// Producer-side stream description (SSRCs, cname, msid). Set by the
  /// router as soon as the publisher offer is parsed.
  final ProducerStream stream;

  final List<DownTrack> _downTracks = [];

  bool _closed = false;

  Receiver({
    required this.id,
    required this.peerId,
    required this.kind,
    required this.codecs,
    required this.stream,
  });

  /// Convenience accessor — the SSRC the publisher actually sends on.
  int get primarySsrc => stream.primarySsrc;

  /// Paired RTX SSRC, or null when the publisher didn't negotiate RTX.
  int? get rtxSsrc => stream.rtxSsrc;

  bool get isClosed => _closed;
  List<DownTrack> get downTracks => List.unmodifiable(_downTracks);

  void attachDownTrack(DownTrack dt) {
    if (_closed) return;
    _downTracks.add(dt);
  }

  void detachDownTrack(DownTrack dt) {
    _downTracks.remove(dt);
  }

  /// Publisher → subscribers fast-path. Walks the attached DownTracks
  /// in a snapshot and forwards the packet (parallel-friendly).
  void deliverRtp(Uint8List rtp) {
    if (_closed) return;
    // Snapshot to avoid concurrent-modification if a DownTrack closes
    // during iteration.
    final snap = List<DownTrack>.from(_downTracks, growable: false);
    for (final dt in snap) {
      dt.writeRtp(rtp);
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
