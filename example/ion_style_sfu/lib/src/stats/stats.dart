// Stats — per-peer / per-track counters surfaced via `/stats` (JSON)
// and `/metrics` (Prometheus text exposition).
//
// Phase 9 extends the snapshot with per-DownTrack counters
// (forwarded/dropped/twcc/nack/layer-switches) plus per-Subscriber
// bandwidth-estimate gauges, and adds [formatPrometheus] which renders
// the snapshot in the v0.0.4 text exposition format scrapers expect.

import '../sfu.dart';

/// Per-DownTrack counters.
class DownTrackStats {
  final String trackId;
  final String sessionId;
  final String peerId;
  final String kind; // "audio" | "video"
  final String trackType; // "simple" | "simulcast"
  final String currentLayer;
  final int layerSwitches;
  final int packetsForwarded;
  final int bytesForwarded;
  final int packetsDroppedWrongLayer;
  final int packetsTwccStamped;
  final int nackRetransmits;
  final int nackUpstreamRequested;

  const DownTrackStats({
    required this.trackId,
    required this.sessionId,
    required this.peerId,
    required this.kind,
    required this.trackType,
    required this.currentLayer,
    required this.layerSwitches,
    required this.packetsForwarded,
    required this.bytesForwarded,
    required this.packetsDroppedWrongLayer,
    required this.packetsTwccStamped,
    required this.nackRetransmits,
    required this.nackUpstreamRequested,
  });

  Map<String, Object?> toJson() => {
        'trackId': trackId,
        'sessionId': sessionId,
        'peerId': peerId,
        'kind': kind,
        'trackType': trackType,
        'currentLayer': currentLayer,
        'layerSwitches': layerSwitches,
        'packetsForwarded': packetsForwarded,
        'bytesForwarded': bytesForwarded,
        'packetsDroppedWrongLayer': packetsDroppedWrongLayer,
        'packetsTwccStamped': packetsTwccStamped,
        'nackRetransmits': nackRetransmits,
        'nackUpstreamRequested': nackUpstreamRequested,
      };
}

/// Per-Subscriber bandwidth-estimator state.
class SubscriberBweStats {
  final String sessionId;
  final String peerId;
  final int currentBps;

  const SubscriberBweStats({
    required this.sessionId,
    required this.peerId,
    required this.currentBps,
  });

  Map<String, Object?> toJson() => {
        'sessionId': sessionId,
        'peerId': peerId,
        'currentBps': currentBps,
      };
}

class SfuStatsSnapshot {
  final int sessions;
  final int peers;
  final int routers;
  final int downTracks;
  final int totalBytesForwarded;
  final int totalPacketsForwarded;
  final List<DownTrackStats> tracks;
  final List<SubscriberBweStats> subscriberBwe;

  const SfuStatsSnapshot({
    required this.sessions,
    required this.peers,
    required this.routers,
    required this.downTracks,
    required this.totalBytesForwarded,
    required this.totalPacketsForwarded,
    this.tracks = const [],
    this.subscriberBwe = const [],
  });

  Map<String, Object?> toJson() => {
        'sessions': sessions,
        'peers': peers,
        'routers': routers,
        'downTracks': downTracks,
        'totalBytesForwarded': totalBytesForwarded,
        'totalPacketsForwarded': totalPacketsForwarded,
        'tracks': [for (final t in tracks) t.toJson()],
        'subscriberBwe': [for (final b in subscriberBwe) b.toJson()],
      };
}

SfuStatsSnapshot snapshotSfu(Sfu sfu) {
  var peers = 0;
  var routers = 0;
  var downTracks = 0;
  var bytes = 0;
  var packets = 0;
  final tracks = <DownTrackStats>[];
  final bwe = <SubscriberBweStats>[];
  for (final s in sfu.sessions) {
    peers += s.peerCount;
    for (final p in s.peers) {
      final sub = p.subscriber;
      if (sub != null) {
        bwe.add(SubscriberBweStats(
          sessionId: s.id,
          peerId: p.id,
          currentBps: sub.bwe.currentBps,
        ));
      }
    }
    for (final r in s.routers) {
      routers++;
      for (final receiver in r.receivers) {
        for (final dt in receiver.downTracks) {
          downTracks++;
          bytes += dt.bytesForwarded;
          packets += dt.packetsForwarded;
          tracks.add(DownTrackStats(
            trackId: dt.id,
            sessionId: s.id,
            peerId: r.peerId,
            kind: receiver.kind.name,
            trackType: dt.trackType.name,
            currentLayer: dt.currentLayer,
            layerSwitches: dt.layerSwitches,
            packetsForwarded: dt.packetsForwarded,
            bytesForwarded: dt.bytesForwarded,
            packetsDroppedWrongLayer: dt.packetsDroppedWrongLayer,
            packetsTwccStamped: dt.packetsTwccStamped,
            nackRetransmits: dt.nack.retransmits,
            nackUpstreamRequested: dt.nack.upstreamRequested,
          ));
        }
      }
    }
  }
  return SfuStatsSnapshot(
    sessions: sfu.sessions.length,
    peers: peers,
    routers: routers,
    downTracks: downTracks,
    totalBytesForwarded: bytes,
    totalPacketsForwarded: packets,
    tracks: tracks,
    subscriberBwe: bwe,
  );
}

/// Render [snap] in Prometheus text exposition format v0.0.4.
///
/// Metric naming follows the `ionsfu_` prefix convention (similar to
/// pion's `pion_sfu_`). Counters end in `_total`, gauges have no
/// suffix. Per-track metrics carry `session`, `peer`, `track`, `kind`
/// labels; per-subscriber BWE carries `session` + `peer`.
String formatPrometheus(SfuStatsSnapshot snap) {
  final out = StringBuffer();

  void gauge(String name, String help, Object value) {
    out.writeln('# HELP $name $help');
    out.writeln('# TYPE $name gauge');
    out.writeln('$name $value');
  }

  void counter(String name, String help, Object value) {
    out.writeln('# HELP $name $help');
    out.writeln('# TYPE $name counter');
    out.writeln('$name $value');
  }

  // --- top-level gauges ---
  gauge('ionsfu_sessions', 'Number of active sessions.', snap.sessions);
  gauge('ionsfu_peers', 'Number of active peers across sessions.', snap.peers);
  gauge('ionsfu_routers', 'Number of active publisher routers.', snap.routers);
  gauge('ionsfu_down_tracks', 'Number of active subscriber-side DownTracks.',
      snap.downTracks);

  // --- top-level counters ---
  counter(
      'ionsfu_bytes_forwarded_total',
      'Total RTP payload bytes forwarded to subscribers.',
      snap.totalBytesForwarded);
  counter(
      'ionsfu_packets_forwarded_total',
      'Total RTP packets forwarded to subscribers.',
      snap.totalPacketsForwarded);

  // --- per-track families ---
  void trackFamily(
      String name, String help, String type, int Function(DownTrackStats) v) {
    out.writeln('# HELP $name $help');
    out.writeln('# TYPE $name $type');
    for (final t in snap.tracks) {
      out.writeln('$name${_trackLabels(t)} ${v(t)}');
    }
  }

  if (snap.tracks.isNotEmpty) {
    trackFamily(
        'ionsfu_track_packets_forwarded_total',
        'Per-track RTP packets forwarded.',
        'counter',
        (t) => t.packetsForwarded);
    trackFamily('ionsfu_track_bytes_forwarded_total',
        'Per-track RTP bytes forwarded.', 'counter', (t) => t.bytesForwarded);
    trackFamily(
        'ionsfu_track_packets_dropped_wrong_layer_total',
        'Packets dropped because they were not from the currently-forwarded simulcast layer.',
        'counter',
        (t) => t.packetsDroppedWrongLayer);
    trackFamily(
        'ionsfu_track_packets_twcc_stamped_total',
        'Packets that were stamped with a TWCC sequence number.',
        'counter',
        (t) => t.packetsTwccStamped);
    trackFamily(
        'ionsfu_track_layer_switches_total',
        'Number of simulcast layer switches.',
        'counter',
        (t) => t.layerSwitches);
    trackFamily(
        'ionsfu_track_nack_retransmits_total',
        'Number of jitter-buffer NACK retransmits served to the subscriber.',
        'counter',
        (t) => t.nackRetransmits);
    trackFamily(
        'ionsfu_track_nack_upstream_total',
        'NACKs forwarded upstream to the publisher (not satisfied locally).',
        'counter',
        (t) => t.nackUpstreamRequested);
  }

  // --- per-subscriber BWE ---
  if (snap.subscriberBwe.isNotEmpty) {
    out.writeln('# HELP ionsfu_subscriber_bwe_bps '
        'Subscriber-side bandwidth estimate (bits per second).');
    out.writeln('# TYPE ionsfu_subscriber_bwe_bps gauge');
    for (final b in snap.subscriberBwe) {
      final lbl = '{session="${_esc(b.sessionId)}",'
          'peer="${_esc(b.peerId)}"}';
      out.writeln('ionsfu_subscriber_bwe_bps$lbl ${b.currentBps}');
    }
  }

  return out.toString();
}

String _trackLabels(DownTrackStats t) => '{session="${_esc(t.sessionId)}",'
    'peer="${_esc(t.peerId)}",'
    'track="${_esc(t.trackId)}",'
    'kind="${_esc(t.kind)}"}';

/// Escape label values per Prometheus exposition format: backslash,
/// double quote, and newline are the only required escapes.
String _esc(String v) {
  final b = StringBuffer();
  for (var i = 0; i < v.length; i++) {
    final c = v[i];
    if (c == '\\') {
      b.write(r'\\');
    } else if (c == '"') {
      b.write(r'\"');
    } else if (c == '\n') {
      b.write(r'\n');
    } else {
      b.write(c);
    }
  }
  return b.toString();
}
