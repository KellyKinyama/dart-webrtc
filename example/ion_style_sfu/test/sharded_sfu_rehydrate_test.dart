// sharded_sfu rehydration + suppress-close-event coverage.

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

void main() {
  group('snapshotFromJson rehydration', () {
    test('hand-built snapshot drives the tracks + bwe loops', () {
      final j = <String, Object?>{
        'sessions': 2,
        'peers': 5,
        'routers': 2,
        'downTracks': 3,
        'totalBytesForwarded': 12345,
        'totalPacketsForwarded': 678,
        'tracks': <Map<String, Object?>>[
          {
            'trackId': 't1',
            'sessionId': 'room-a',
            'peerId': 'alice',
            'kind': 'video',
            'trackType': 'simulcast',
            'currentLayer': 'h',
            'layerSwitches': 2,
            'packetsForwarded': 100,
            'bytesForwarded': 110000,
            'packetsDroppedWrongLayer': 1,
            'packetsTwccStamped': 90,
            'nackRetransmits': 4,
            'nackUpstreamRequested': 1,
          },
          {
            'trackId': 't2',
            'sessionId': 'room-a',
            'peerId': 'alice',
            'kind': 'audio',
            'trackType': 'mono',
            'currentLayer': '',
            'layerSwitches': 0,
            'packetsForwarded': 200,
            'bytesForwarded': 8000,
            'packetsDroppedWrongLayer': 0,
            'packetsTwccStamped': 0,
            'nackRetransmits': 0,
            'nackUpstreamRequested': 0,
          },
        ],
        'subscriberBwe': <Map<String, Object?>>[
          {
            'sessionId': 'room-a',
            'peerId': 'bob',
            'currentBps': 1500000,
          },
        ],
      };
      final snap = snapshotFromJson(j);
      expect(snap.sessions, 2);
      expect(snap.peers, 5);
      expect(snap.routers, 2);
      expect(snap.downTracks, 3);
      expect(snap.totalBytesForwarded, 12345);
      expect(snap.totalPacketsForwarded, 678);
      expect(snap.tracks, hasLength(2));
      expect(snap.tracks.first.trackId, 't1');
      expect(snap.tracks.first.kind, 'video');
      expect(snap.tracks.first.currentLayer, 'h');
      expect(snap.tracks.first.packetsForwarded, 100);
      expect(snap.tracks[1].kind, 'audio');
      expect(snap.subscriberBwe, hasLength(1));
      expect(snap.subscriberBwe.first.peerId, 'bob');
      expect(snap.subscriberBwe.first.currentBps, 1500000);

      // formatPrometheus consumes the rehydrated snapshot end-to-end.
      final text = formatPrometheus(snap);
      expect(text, contains('ionsfu_track_packets_forwarded_total'));
      expect(text, contains('peer="alice"'));
    });

    test('empty tracks/bwe lists round-trip cleanly', () {
      final j = <String, Object?>{
        'sessions': 0,
        'peers': 0,
        'routers': 0,
        'downTracks': 0,
        'totalBytesForwarded': 0,
        'totalPacketsForwarded': 0,
        'tracks': const <Object?>[],
        'subscriberBwe': const <Object?>[],
      };
      final snap = snapshotFromJson(j);
      expect(snap.tracks, isEmpty);
      expect(snap.subscriberBwe, isEmpty);
    });

    test('missing tracks/bwe keys are tolerated (default to empty)', () {
      final j = <String, Object?>{
        'sessions': 0,
        'peers': 0,
        'routers': 0,
        'downTracks': 0,
        'totalBytesForwarded': 0,
        'totalPacketsForwarded': 0,
      };
      final snap = snapshotFromJson(j);
      expect(snap.tracks, isEmpty);
      expect(snap.subscriberBwe, isEmpty);
    });
  });

  group('ShardedSfu close-event suppression', () {
    test('closeShard suppresses the worker close event for that sid', () async {
      final sfu = ShardedSfu(ShardConfigTemplate(
        bindAddress: '127.0.0.1',
        rtpBasePort: 56800,
        announceAddress: '127.0.0.1',
        quiet: true,
      ));
      addTearDown(sfu.close);

      final closes = <ShardClosedEvent>[];
      sfu.onEvent = (e) {
        if (e is ShardClosedEvent) closes.add(e);
      };
      await sfu.getOrCreate('s1');
      // closeShard emits the synthetic event AND tags the sid for
      // worker-event suppression. Wait for both to settle.
      await sfu.closeShard('s1', reason: ShardCloseReason.upstreamUnreachable);
      // Allow the worker isolate to push its own close event.
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      // Only ONE close event should be visible to subscribers.
      final s1Closes = closes.where((e) => e.sessionId == 's1').toList();
      expect(s1Closes, hasLength(1));
      expect(s1Closes.single.reason, ShardCloseReason.upstreamUnreachable);
    });
  });
}
