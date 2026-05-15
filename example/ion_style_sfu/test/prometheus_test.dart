import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

SfuStatsSnapshot _snap({
  int sessions = 0,
  int peers = 0,
  int routers = 0,
  int downTracks = 0,
  int totalBytes = 0,
  int totalPackets = 0,
  List<DownTrackStats> tracks = const [],
  List<SubscriberBweStats> bwe = const [],
}) =>
    SfuStatsSnapshot(
      sessions: sessions,
      peers: peers,
      routers: routers,
      downTracks: downTracks,
      totalBytesForwarded: totalBytes,
      totalPacketsForwarded: totalPackets,
      tracks: tracks,
      subscriberBwe: bwe,
    );

DownTrackStats _track({
  String trackId = 't1',
  String sessionId = 'room',
  String peerId = 'alice',
  String kind = 'video',
  String trackType = 'simple',
  String currentLayer = 'q',
  int layerSwitches = 0,
  int packetsForwarded = 0,
  int bytesForwarded = 0,
  int packetsDroppedWrongLayer = 0,
  int packetsTwccStamped = 0,
  int nackRetransmits = 0,
  int nackUpstreamRequested = 0,
}) =>
    DownTrackStats(
      trackId: trackId,
      sessionId: sessionId,
      peerId: peerId,
      kind: kind,
      trackType: trackType,
      currentLayer: currentLayer,
      layerSwitches: layerSwitches,
      packetsForwarded: packetsForwarded,
      bytesForwarded: bytesForwarded,
      packetsDroppedWrongLayer: packetsDroppedWrongLayer,
      packetsTwccStamped: packetsTwccStamped,
      nackRetransmits: nackRetransmits,
      nackUpstreamRequested: nackUpstreamRequested,
    );

void main() {
  group('SfuStatsSnapshot.toJson', () {
    test('includes tracks and subscriberBwe arrays', () {
      final s = _snap(
        sessions: 1,
        peers: 2,
        routers: 1,
        downTracks: 1,
        totalBytes: 5000,
        totalPackets: 10,
        tracks: [_track(packetsForwarded: 10, bytesForwarded: 5000)],
        bwe: [
          const SubscriberBweStats(
              sessionId: 'room', peerId: 'alice', currentBps: 750000),
        ],
      );
      final j = s.toJson();
      expect(j['sessions'], 1);
      expect(j['peers'], 2);
      expect(j['totalBytesForwarded'], 5000);
      expect(j['tracks'], hasLength(1));
      expect((j['tracks'] as List).first, isA<Map>());
      expect(j['subscriberBwe'], hasLength(1));
      expect(((j['subscriberBwe'] as List).first as Map)['currentBps'], 750000);
    });
  });

  group('formatPrometheus - top-level', () {
    test('emits HELP/TYPE for each top-level metric and the value lines', () {
      final out = formatPrometheus(_snap(
        sessions: 3,
        peers: 7,
        routers: 4,
        downTracks: 12,
        totalBytes: 9999,
        totalPackets: 555,
      ));
      // Required gauges
      expect(out, contains('# TYPE ionsfu_sessions gauge'));
      expect(out, contains('\nionsfu_sessions 3\n'));
      expect(out, contains('\nionsfu_peers 7\n'));
      expect(out, contains('\nionsfu_routers 4\n'));
      expect(out, contains('\nionsfu_down_tracks 12\n'));
      // Required counters
      expect(out, contains('# TYPE ionsfu_bytes_forwarded_total counter'));
      expect(out, contains('\nionsfu_bytes_forwarded_total 9999\n'));
      expect(out, contains('\nionsfu_packets_forwarded_total 555\n'));
    });

    test('with no tracks the per-track families are omitted', () {
      final out = formatPrometheus(_snap());
      expect(out, isNot(contains('ionsfu_track_packets_forwarded_total')));
      expect(out, isNot(contains('ionsfu_subscriber_bwe_bps')));
    });
  });

  group('formatPrometheus - per-track families', () {
    test('emits all 7 families with proper labels for each track', () {
      final out = formatPrometheus(_snap(
        downTracks: 2,
        tracks: [
          _track(
            trackId: 'tA',
            sessionId: 'room1',
            peerId: 'alice',
            kind: 'video',
            packetsForwarded: 100,
            bytesForwarded: 50000,
            packetsDroppedWrongLayer: 5,
            packetsTwccStamped: 95,
            layerSwitches: 2,
            nackRetransmits: 7,
            nackUpstreamRequested: 1,
          ),
          _track(
            trackId: 'tB',
            sessionId: 'room1',
            peerId: 'bob',
            kind: 'audio',
            packetsForwarded: 200,
          ),
        ],
      ));

      // Labels are present and per-track
      expect(
          out,
          contains('ionsfu_track_packets_forwarded_total{'
              'session="room1",peer="alice",track="tA",kind="video"} 100'));
      expect(
          out,
          contains('ionsfu_track_packets_forwarded_total{'
              'session="room1",peer="bob",track="tB",kind="audio"} 200'));
      expect(
          out,
          contains('ionsfu_track_bytes_forwarded_total{'
              'session="room1",peer="alice",track="tA",kind="video"} 50000'));
      expect(
          out,
          contains('ionsfu_track_packets_dropped_wrong_layer_total{'
              'session="room1",peer="alice",track="tA",kind="video"} 5'));
      expect(
          out,
          contains('ionsfu_track_packets_twcc_stamped_total{'
              'session="room1",peer="alice",track="tA",kind="video"} 95'));
      expect(
          out,
          contains('ionsfu_track_layer_switches_total{'
              'session="room1",peer="alice",track="tA",kind="video"} 2'));
      expect(
          out,
          contains('ionsfu_track_nack_retransmits_total{'
              'session="room1",peer="alice",track="tA",kind="video"} 7'));
      expect(
          out,
          contains('ionsfu_track_nack_upstream_total{'
              'session="room1",peer="alice",track="tA",kind="video"} 1'));

      // Each family has exactly one HELP/TYPE pair (not duplicated per
      // sample) — characteristic of grouped exposition.
      expect('HELP ionsfu_track_packets_forwarded_total'.allMatches(out).length,
          1);
      expect(
          'TYPE ionsfu_track_packets_forwarded_total counter'
              .allMatches(out)
              .length,
          1);
    });
  });

  group('formatPrometheus - subscriber BWE', () {
    test('emits one gauge sample per subscriber', () {
      final out = formatPrometheus(_snap(
        bwe: [
          SubscriberBweStats(
              sessionId: 'r', peerId: 'alice', currentBps: 1000000),
          SubscriberBweStats(sessionId: 'r', peerId: 'bob', currentBps: 500000),
        ],
      ));
      expect(out, contains('# TYPE ionsfu_subscriber_bwe_bps gauge'));
      expect(
          out,
          contains(
              'ionsfu_subscriber_bwe_bps{session="r",peer="alice"} 1000000'));
      expect(out,
          contains('ionsfu_subscriber_bwe_bps{session="r",peer="bob"} 500000'));
    });
  });

  group('formatPrometheus - label escaping', () {
    test('escapes backslash, double-quote, and newline', () {
      final out = formatPrometheus(_snap(
        downTracks: 1,
        tracks: [
          _track(
            trackId: 'tr"1',
            sessionId: r'a\b',
            peerId: 'x\ny',
          ),
        ],
      ));
      // session="a\\b", peer="x\ny", track="tr\"1"
      expect(
          out,
          contains(
              'session="a\\\\b",peer="x\\ny",track="tr\\"1",kind="video"'));
    });
  });

  group('formatPrometheus - exposition shape', () {
    test('every metric line is preceded by a HELP and TYPE line for its family',
        () {
      final out = formatPrometheus(_snap(
        sessions: 1,
        downTracks: 1,
        tracks: [_track(packetsForwarded: 1)],
        bwe: [
          const SubscriberBweStats(
              sessionId: 'room', peerId: 'alice', currentBps: 1),
        ],
      ));
      final lines = out.split('\n');
      // Collect family names that have value lines.
      final seenFamilies = <String>{};
      for (final l in lines) {
        if (l.isEmpty || l.startsWith('#')) continue;
        // family name = leading identifier up to '{' or whitespace.
        final brace = l.indexOf('{');
        final space = l.indexOf(' ');
        final cut = brace > 0 ? brace : space;
        if (cut < 0) continue;
        seenFamilies.add(l.substring(0, cut));
      }
      for (final fam in seenFamilies) {
        expect(out, contains('# HELP $fam '), reason: 'missing HELP for $fam');
        expect(out, contains('# TYPE $fam '), reason: 'missing TYPE for $fam');
      }
    });

    test('output ends with a newline', () {
      final out = formatPrometheus(_snap(sessions: 1));
      expect(out.endsWith('\n'), isTrue);
    });
  });

  group('formatPrometheusCluster - overload caps (Phase 25)', () {
    test('emits sessionCap + peerCap gauges when configured', () {
      final out = formatPrometheusCluster(
        hubStats: const {
          'port': 9100,
          'authenticated': false,
          'endpoints': 0,
          'framingErrors': 0,
          'authFailures': 0,
          'unknownPeerFrames': 0,
        },
        bridges: const [],
        sessionCap: 64,
        peerCap: 8,
      );
      expect(out, contains('ionsfu_sfu_session_cap'));
      expect(out, contains(' 64'));
      expect(out, contains('ionsfu_sfu_peer_cap'));
      expect(out, contains(' 8'));
    });

    test('omits cap gauges when sessionCap/peerCap are null', () {
      final out = formatPrometheusCluster(
        hubStats: const {
          'port': 9100,
          'authenticated': false,
          'endpoints': 0,
          'framingErrors': 0,
          'authFailures': 0,
          'unknownPeerFrames': 0,
        },
        bridges: const [],
      );
      expect(out, isNot(contains('ionsfu_sfu_session_cap')));
      expect(out, isNot(contains('ionsfu_sfu_peer_cap')));
    });
  });
}
