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

/// Phase 18 — render cluster/relay observability counters in
/// Prometheus exposition format. [hubStats] is `UdpRelayHub.stats`,
/// [bridges] is the list returned by
/// `ClusterCoordinator.detailedSnapshot()`. Pass [selfId] to label
/// the `ionsfu_cluster_self` gauge.
///
/// Designed to be appended to the output of [formatPrometheus] when
/// the SFU is running in cluster mode.
String formatPrometheusCluster({
  required Map<String, Object?> hubStats,
  required List<Map<String, Object?>> bridges,
  String? selfId,
  int upstreamReconnectAttempts = 0,
  int upstreamReconnectsSucceeded = 0,
  int upstreamReconnectsGivenUp = 0,
  // Phase 25 — overload counters.
  int sessionsRejectedAtCap = 0,
  int? sessionCap,
  int? peerCap,
}) {
  final out = StringBuffer();

  void counter(String name, String help, Object value) {
    out.writeln('# HELP $name $help');
    out.writeln('# TYPE $name counter');
    out.writeln('$name $value');
  }

  void gauge(String name, String help, Object value) {
    out.writeln('# HELP $name $help');
    out.writeln('# TYPE $name gauge');
    out.writeln('$name $value');
  }

  if (selfId != null) {
    out.writeln('# HELP ionsfu_cluster_self Identity of this SFU node.');
    out.writeln('# TYPE ionsfu_cluster_self gauge');
    out.writeln('ionsfu_cluster_self{id="${_esc(selfId)}"} 1');
  }

  gauge(
    'ionsfu_relay_authenticated',
    'Whether the relay hub enforces HMAC-SHA256 (1=yes,0=no).',
    (hubStats['authenticated'] == true) ? 1 : 0,
  );
  gauge('ionsfu_relay_endpoints', 'Number of live relay endpoints.',
      hubStats['endpoints'] ?? 0);
  counter(
      'ionsfu_relay_framing_errors_total',
      'UDP datagrams dropped due to bad magic/version/type/length.',
      hubStats['framingErrors'] ?? 0);
  counter(
      'ionsfu_relay_auth_failures_total',
      'UDP datagrams dropped due to HMAC mismatch (when secret is set).',
      hubStats['authFailures'] ?? 0);
  counter(
      'ionsfu_relay_unknown_peer_frames_total',
      'Well-formed datagrams from a host:port with no live endpoint.',
      hubStats['unknownPeerFrames'] ?? 0);

  gauge('ionsfu_cluster_bridges', 'Number of live cascade bridges.',
      bridges.length);

  // Phase 22 — upstream auto-reconnect activity.
  counter(
      'ionsfu_cluster_upstream_reconnect_attempts_total',
      'Times the coordinator tried to reattach a closed upstream bridge.',
      upstreamReconnectAttempts);
  counter(
      'ionsfu_cluster_upstream_reconnect_succeeded_total',
      'Upstream-bridge reattach attempts that succeeded.',
      upstreamReconnectsSucceeded);
  counter(
      'ionsfu_cluster_upstream_reconnect_given_up_total',
      'Upstream-bridge reconnect loops abandoned by the circuit breaker.',
      upstreamReconnectsGivenUp);

  // Phase 25 — overload caps + rejection counter.
  counter(
      'ionsfu_sfu_sessions_rejected_total',
      'Session-spawn attempts rejected because the per-node session cap '
          'was already reached.',
      sessionsRejectedAtCap);
  if (sessionCap != null) {
    gauge('ionsfu_sfu_session_cap', 'Configured per-node session cap.',
        sessionCap);
  }
  if (peerCap != null) {
    gauge('ionsfu_sfu_peer_cap', 'Configured per-session peer cap.', peerCap);
  }

  // Per-bridge gauges — labels: session, bridge, role, remote.
  if (bridges.isNotEmpty) {
    out.writeln(
        '# HELP ionsfu_cluster_bridge_established Whether the bridge has '
        'completed its relay handshake (1=yes,0=no).');
    out.writeln('# TYPE ionsfu_cluster_bridge_established gauge');
    for (final b in bridges) {
      final lbl = _bridgeLabels(b);
      final v = (b['established'] == true) ? 1 : 0;
      out.writeln('ionsfu_cluster_bridge_established$lbl $v');
    }
    out.writeln('# HELP ionsfu_cluster_bridge_inbound_rtp_packets_total '
        'RTP packets received on a cascade bridge.');
    out.writeln(
        '# TYPE ionsfu_cluster_bridge_inbound_rtp_packets_total counter');
    for (final b in bridges) {
      final lbl = _bridgeLabels(b);
      out.writeln(
          'ionsfu_cluster_bridge_inbound_rtp_packets_total$lbl ${b['inboundRtpPackets'] ?? 0}');
    }
    out.writeln('# HELP ionsfu_cluster_bridge_idle_ms '
        'Milliseconds since the last inbound frame on this bridge.');
    out.writeln('# TYPE ionsfu_cluster_bridge_idle_ms gauge');
    for (final b in bridges) {
      final lbl = _bridgeLabels(b);
      out.writeln('ionsfu_cluster_bridge_idle_ms$lbl ${b['idleMs'] ?? 0}');
    }
    out.writeln('# HELP ionsfu_cluster_bridge_relayed_receivers '
        'Number of relayed receivers currently published over this bridge.');
    out.writeln('# TYPE ionsfu_cluster_bridge_relayed_receivers gauge');
    for (final b in bridges) {
      final lbl = _bridgeLabels(b);
      out.writeln(
          'ionsfu_cluster_bridge_relayed_receivers$lbl ${b['relayedReceivers'] ?? 0}');
    }
    // Phase 20 — relay RTT measured from keepalive ping/pong.
    // Emitted only for bridges where a pong has been observed.
    final rttBridges = bridges.where((b) => b['lastRttMs'] != null).toList();
    if (rttBridges.isNotEmpty) {
      out.writeln('# HELP ionsfu_cluster_bridge_rtt_ms '
          'Most-recent relay round-trip time (ms) measured from the '
          'keepalive ping/pong.');
      out.writeln('# TYPE ionsfu_cluster_bridge_rtt_ms gauge');
      for (final b in rttBridges) {
        out.writeln(
            'ionsfu_cluster_bridge_rtt_ms${_bridgeLabels(b)} ${b['lastRttMs']}');
      }
      out.writeln('# HELP ionsfu_cluster_bridge_rtt_ewma_ms '
          'EWMA (alpha=0.25) of the relay round-trip time (ms).');
      out.writeln('# TYPE ionsfu_cluster_bridge_rtt_ewma_ms gauge');
      for (final b in rttBridges) {
        out.writeln(
            'ionsfu_cluster_bridge_rtt_ewma_ms${_bridgeLabels(b)} ${b['rttEwmaMs']}');
      }
    }
    // Phase 21 — throughput counters (TX/RX × control/RTP/RTCP).
    void bridgeCounter(String name, String help, String key) {
      out.writeln('# HELP $name $help');
      out.writeln('# TYPE $name counter');
      for (final b in bridges) {
        out.writeln('$name${_bridgeLabels(b)} ${b[key] ?? 0}');
      }
    }

    bridgeCounter(
        'ionsfu_cluster_bridge_tx_control_packets_total',
        'Control frames sent toward the remote on this bridge.',
        'txControlPackets');
    bridgeCounter(
        'ionsfu_cluster_bridge_tx_control_bytes_total',
        'Control bytes sent toward the remote on this bridge.',
        'txControlBytes');
    bridgeCounter('ionsfu_cluster_bridge_tx_rtp_packets_total',
        'RTP packets sent toward the remote on this bridge.', 'txRtpPackets');
    bridgeCounter('ionsfu_cluster_bridge_tx_rtp_bytes_total',
        'RTP bytes sent toward the remote on this bridge.', 'txRtpBytes');
    bridgeCounter('ionsfu_cluster_bridge_tx_rtcp_packets_total',
        'RTCP packets sent toward the remote on this bridge.', 'txRtcpPackets');
    bridgeCounter('ionsfu_cluster_bridge_tx_rtcp_bytes_total',
        'RTCP bytes sent toward the remote on this bridge.', 'txRtcpBytes');
    bridgeCounter(
        'ionsfu_cluster_bridge_rx_control_packets_total',
        'Control frames received from the remote on this bridge.',
        'rxControlPackets');
    bridgeCounter(
        'ionsfu_cluster_bridge_rx_control_bytes_total',
        'Control bytes received from the remote on this bridge.',
        'rxControlBytes');
    bridgeCounter('ionsfu_cluster_bridge_rx_rtp_packets_total',
        'RTP packets received from the remote on this bridge.', 'rxRtpPackets');
    bridgeCounter('ionsfu_cluster_bridge_rx_rtp_bytes_total',
        'RTP bytes received from the remote on this bridge.', 'rxRtpBytes');
    bridgeCounter(
        'ionsfu_cluster_bridge_rx_rtcp_packets_total',
        'RTCP packets received from the remote on this bridge.',
        'rxRtcpPackets');
    bridgeCounter('ionsfu_cluster_bridge_rx_rtcp_bytes_total',
        'RTCP bytes received from the remote on this bridge.', 'rxRtcpBytes');
  }

  return out.toString();
}

String _bridgeLabels(Map<String, Object?> b) {
  final session = (b['sessionId'] ?? '') as String;
  final bridge = (b['bridgeId'] ?? '') as String;
  final role = (b['role'] ?? '') as String;
  final remote = (b['remote'] ?? '') as String;
  return '{session="${_esc(session)}",'
      'bridge="${_esc(bridge)}",'
      'role="${_esc(role)}",'
      'remote="${_esc(remote)}"}';
}

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
