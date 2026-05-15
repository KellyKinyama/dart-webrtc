// Receiver — one inbound publisher track. Holds the codec metadata,
// resolved primary/RTX SSRC pair (per layer for simulcast tracks), and
// the list of DownTracks subscribed to it.
//
// Mirrors `pkg/sfu/receiver.go` (the simple, non-simulcast slice plus
// the SIM-group simulcast extensions added in Phase 3a and the RID-
// extension routing added in Phase 3c).

import 'dart:typed_data';

import 'package:pure_dart_webrtc/signal/sdp_v2.dart' show SdpCodec;
import 'package:pure_dart_webrtc/webrtc/webrtc.dart' show MediaKind;

import 'audio_observer.dart';
import 'down_track.dart';
import 'producer_layer.dart';
import 'producer_stream.dart';
import 'rtp_header.dart';

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

  /// rid string → layer (built from [stream.layers]).
  final Map<String, ProducerLayer> _byRid = {};

  /// Hook fired when an SSRC is bound to a layer at runtime (RID-based
  /// simulcast). Lets the Router add the new SSRC to its routing
  /// table so subsequent packets with the same SSRC short-circuit
  /// straight to this Receiver without re-reading the RID extension.
  void Function(int ssrc, ProducerLayer layer, {required bool isRtx})?
      onSsrcLearned;

  /// Phase 8 — additional listeners (DownTracks register here so they
  /// can extend their RTCP-rewrite SSRC map). Distinct from
  /// [onSsrcLearned] so we don't clobber the Router's binding.
  final List<
          void Function(int ssrc, ProducerLayer layer, {required bool isRtx})>
      _ssrcListeners = [];

  /// Phase 8 — register an additional listener for SSRC bindings.
  /// Returns a closure that removes the listener.
  void Function() addSsrcListener(
      void Function(int ssrc, ProducerLayer layer, {required bool isRtx}) cb) {
    _ssrcListeners.add(cb);
    return () => _ssrcListeners.remove(cb);
  }

  /// Optional audio-level observer fed by [deliverRtp] when the
  /// publisher negotiated the RFC 6464 `ssrc-audio-level` extension and
  /// this is an audio receiver. Set by Router on creation.
  AudioObserver? audioObserver;

  final List<DownTrack> _downTracks = [];

  /// Phase 6b — RTP/RTCP taps. Each tap is fired *after* fan-out to
  /// DownTracks with the raw inbound packet, so relays can forward the
  /// unmodified upstream SSRC + sequence numbers downstream.
  final List<void Function(Uint8List rtp)> _rtpTaps = [];
  final List<void Function(Uint8List rtcp)> _rtcpTaps = [];

  bool _closed = false;

  // ---- RFC 3550 §A.8 interarrival jitter ----------------------------

  /// Assumed RTP timestamp clock rate, used to convert local arrival
  /// wallclock into the same units as the source's RTP timestamp.
  /// Real WebRTC negotiates this per-codec; we approximate with the
  /// near-universal defaults so the jitter EMA is at least in the
  /// right ballpark for stats / RR generation.
  late final int _jitterClockHz = kind == MediaKind.audio ? 48000 : 90000;

  /// Last seen primary-packet RTP timestamp; used to compute the
  /// transit-delta `D` between consecutive primaries.
  int? _lastRtpTs;

  /// Local arrival wallclock of [_lastRtpTs], expressed in microseconds
  /// since epoch. Distinct from a `DateTime` to avoid extra allocation
  /// per packet on the hot path.
  int? _lastArrivalUs;

  /// Smoothed interarrival jitter, RFC 3550 §A.8 EMA factor 1/16, in
  /// RTP timestamp units of [_jitterClockHz]. Surfaced via [jitter].
  double _jitterUnits = 0.0;

  /// Number of primary packets folded into the jitter EMA. Useful for
  /// detecting a stream that hasn't seen enough samples yet.
  int _jitterSamples = 0;

  /// Smoothed interarrival jitter in milliseconds. Stable definition
  /// for stats / Prometheus regardless of codec clock rate.
  double get jitterMs => _jitterUnits * 1000.0 / _jitterClockHz;

  /// Smoothed interarrival jitter in raw RTP-timestamp units of the
  /// source's codec clock. Matches what an RFC 3550 RR would carry.
  int get jitter => _jitterUnits.round();

  /// Number of primary packets folded into the jitter EMA.
  int get jitterSamples => _jitterSamples;

  // ---- Phase G — publisher-side receive counters ------------------

  /// Total primary RTP packets observed from the publisher (across all
  /// simulcast layers). RTX packets are counted separately under
  /// [rtxPacketsReceived] so they don't inflate the loss estimate.
  int packetsReceived = 0;

  /// Total primary RTP bytes (header + payload) observed.
  int bytesReceived = 0;

  /// Total RFC 4588 RTX packets observed.
  int rtxPacketsReceived = 0;

  /// Per-primary-SSRC sequence-number tracking used to estimate the
  /// number of packets lost between the publisher and the SFU. Each
  /// entry holds the highest seq seen (16-bit, with wrap detection).
  final Map<int, int> _highestSeqBySsrc = {};

  /// Cumulative count of packets the publisher sent but never arrived
  /// (estimated from sequence-number gaps). Decreases when an
  /// out-of-order packet retroactively fills a gap (clamped at 0).
  int packetsLost = 0;

  /// When [forwardAudioLevel] is false, the audio-level RTP header
  /// extension (RFC 6464) is stripped from packets before they are
  /// fanned out to subscribers. Defaults to true (forward as-is) for
  /// backward compatibility; set to false on a per-receiver basis to
  /// keep loudness data inside the SFU (privacy / silent-room mode).
  bool forwardAudioLevel = true;


  Receiver({
    required this.id,
    required this.peerId,
    required this.kind,
    required this.codecs,
    required this.stream,
  }) {
    for (final l in stream.layers) {
      _byRid[l.rid] = l;
      if (l.primarySsrc != 0) _byPrimarySsrc[l.primarySsrc] = l;
      if (l.rtxSsrc != null && l.rtxSsrc != 0) {
        _byRtxSsrc[l.rtxSsrc!] = l;
      }
    }
  }

  /// Convenience accessor — the default layer's primary SSRC. Returns
  /// 0 for RID-discovery streams that haven't seen any packets yet.
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

  /// Phase 6b — install an RTP tap. The tap fires for every primary
  /// and RTX packet delivered to this receiver, with the raw inbound
  /// bytes. Returns a closure that removes the tap.
  void Function() addRtpTap(void Function(Uint8List rtp) tap) {
    _rtpTaps.add(tap);
    return () => _rtpTaps.remove(tap);
  }

  /// Phase 6b — install an RTCP tap.
  void Function() addRtcpTap(void Function(Uint8List rtcp) tap) {
    _rtcpTaps.add(tap);
    return () => _rtcpTaps.remove(tap);
  }

  /// Publisher → subscribers fast-path. Resolves which simulcast layer
  /// the inbound packet belongs to (by SSRC, falling back to the RID
  /// header extension for modern Chrome simulcast where SSRCs are not
  /// pre-announced) and forwards to every attached DownTrack with the
  /// layer + isRtx flag pre-resolved.
  void deliverRtp(Uint8List rtp) {
    if (_closed || rtp.length < 12) return;
    final ssrc = (rtp[8] << 24) | (rtp[9] << 16) | (rtp[10] << 8) | rtp[11];
    var primaryLayer = _byPrimarySsrc[ssrc];
    var rtxLayer = primaryLayer == null ? _byRtxSsrc[ssrc] : null;

    // RID-extension fallback (Phase 3c). Only consulted when the SSRC
    // is unknown AND the publisher negotiated the RID extension. On a
    // hit we bind the SSRC to the layer for the rest of the session.
    if (primaryLayer == null && rtxLayer == null && stream.ridExtId != null) {
      final exts = readRtpExtensions(rtp);
      // Repaired-RID identifies the layer an RTX retransmits.
      final rrid = stream.repairedRidExtId == null
          ? null
          : decodeRidString(exts[stream.repairedRidExtId!]);
      if (rrid != null) {
        final layer = _byRid[rrid];
        if (layer != null) {
          rtxLayer = layer;
          _byRtxSsrc[ssrc] = layer;
          onSsrcLearned?.call(ssrc, layer, isRtx: true);
          for (final l in _ssrcListeners) {
            l(ssrc, layer, isRtx: true);
          }
        }
      } else {
        final rid = decodeRidString(exts[stream.ridExtId!]);
        if (rid != null) {
          final layer = _byRid[rid];
          if (layer != null) {
            primaryLayer = layer;
            _byPrimarySsrc[ssrc] = layer;
            onSsrcLearned?.call(ssrc, layer, isRtx: false);
            for (final l in _ssrcListeners) {
              l(ssrc, layer, isRtx: false);
            }
          }
        }
      }
    }

    final layer = primaryLayer ?? rtxLayer;
    if (layer == null) return;
    final isRtx = rtxLayer != null;

    // Phase G — publisher-side receive counters. Track packets
    // separately for primary vs RTX so we can estimate inbound loss
    // off the primary SSRC's sequence-number deltas (RTX retransmits
    // are gap-fillers — if we counted them as new arrivals we'd
    // double-count and under-report loss).
    if (isRtx) {
      rtxPacketsReceived++;
    } else {
      packetsReceived++;
      bytesReceived += rtp.length;
      final ssrc =
          (rtp[8] << 24) | (rtp[9] << 16) | (rtp[10] << 8) | rtp[11];
      final seq = (rtp[2] << 8) | rtp[3];
      final prev = _highestSeqBySsrc[ssrc];
      if (prev == null) {
        _highestSeqBySsrc[ssrc] = seq;
      } else {
        // Treat the 16-bit space as signed-mod so a small backward
        // delta after a wraparound looks like a forward jump.
        var delta = (seq - prev) & 0xffff;
        if (delta >= 0x8000) {
          // Out-of-order arrival — retroactively fill a gap.
          if (packetsLost > 0) packetsLost--;
        } else if (delta > 1) {
          packetsLost += delta - 1;
          _highestSeqBySsrc[ssrc] = seq;
        } else if (delta == 1) {
          _highestSeqBySsrc[ssrc] = seq;
        }
        // delta == 0 — duplicate, ignore.
      }
    }

    // RFC 3550 §A.8 — per-source interarrival jitter EMA. Computed
    // from primary packet arrivals only (RTX retransmits are
    // out-of-order copies of already-observed primaries; folding
    // them in would inflate the estimate). Update happens before any
    // fan-out so a DownTrack tap that consults [jitter] sees the
    // latest value.
    if (!isRtx) {
      final nowUs = DateTime.now().microsecondsSinceEpoch;
      final ts = rtpTimestamp(rtp);
      final lastTs = _lastRtpTs;
      final lastArr = _lastArrivalUs;
      if (lastTs != null && lastArr != null) {
        // Convert arrival delta to RTP-timestamp units, then form D
        // = transit(j) - transit(i). Use modular arithmetic on TS
        // because the publisher's timestamp wraps every ~13 hours
        // (90 kHz video).
        final arrivalDeltaUnits =
            ((nowUs - lastArr) * _jitterClockHz / 1000000).round();
        var tsDelta = (ts - lastTs) & 0xffffffff;
        // Treat tsDelta as a signed 32-bit value so that backward
        // jumps (timestamp going down) don't blow the jitter up to
        // billions of units.
        if (tsDelta >= 0x80000000) tsDelta -= 0x100000000;
        final d = (arrivalDeltaUnits - tsDelta).abs().toDouble();
        _jitterUnits += (d - _jitterUnits) / 16.0;
        _jitterSamples++;
      }
      _lastRtpTs = ts;
      _lastArrivalUs = nowUs;
    }

    // Phase 4 — feed the audio-level observer for primary audio
    // packets when the extension was negotiated. RTX retransmits are
    // skipped (they re-send already-observed primary frames).
    final observer = audioObserver;
    final levelExtId = stream.audioLevelExtId;
    if (!isRtx &&
        observer != null &&
        levelExtId != null &&
        kind == MediaKind.audio) {
      final exts = readRtpExtensions(rtp);
      final lvl = decodeAudioLevel(exts[levelExtId]);
      if (lvl != null) {
        observer.observe(id, lvl.level, voice: lvl.voice);
      }
    }

    // Phase G — audio-level forwarding policy. When the receiver opts
    // out, zero the level byte in place so subscribers see silence
    // markers but the on-the-wire extension shape is unchanged (no
    // need to rewrite the X-bit / extension length). Done here, after
    // the observer call, so the SFU still gets ground-truth loudness
    // for active-speaker detection.
    if (!isRtx &&
        !forwardAudioLevel &&
        levelExtId != null &&
        kind == MediaKind.audio) {
      stripAudioLevel(rtp, levelExtId);
    }

    // Snapshot to avoid concurrent-modification if a DownTrack closes
    // during iteration.
    final snap = List<DownTrack>.from(_downTracks, growable: false);
    for (final dt in snap) {
      dt.writeRtp(layer, isRtx, rtp);
    }
    if (_rtpTaps.isNotEmpty) {
      final tapSnap =
          List<void Function(Uint8List)>.from(_rtpTaps, growable: false);
      for (final t in tapSnap) {
        t(rtp);
      }
    }
  }

  void deliverRtcp(Uint8List rtcp) {
    if (_closed) return;
    final snap = List<DownTrack>.from(_downTracks, growable: false);
    for (final dt in snap) {
      dt.writeRtcp(rtcp);
    }
    if (_rtcpTaps.isNotEmpty) {
      final tapSnap =
          List<void Function(Uint8List)>.from(_rtcpTaps, growable: false);
      for (final t in tapSnap) {
        t(rtcp);
      }
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    audioObserver?.forget(id);
    final snap = List<DownTrack>.from(_downTracks, growable: false);
    for (final dt in snap) {
      dt.close();
    }
    _downTracks.clear();
    _rtpTaps.clear();
    _rtcpTaps.clear();
  }
}
