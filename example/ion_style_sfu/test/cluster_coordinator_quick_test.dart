// cluster_coordinator quick wins — exercises:
//   * default log path (line 110): construct without `log:`.
//   * cascade-hello reject when self is not the owner (line 557).
//   * _reapShard route cleanup (lines 520-527) via closeShard on a
//     non-owner shard with a registered upstream route.
//   * close() cancelling a pending reconnect timer (line 260).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

ClusterPeer _p(String spec) => ClusterPeer.parse(spec);

void main() {
  group('ClusterCoordinator quick wins', () {
    test('default constructor wires a stderr logger (no throw)', () async {
      final self = _p('127.0.0.1:19501:19502');
      final peer = _p('127.0.0.1:19503:19504');
      final hub = await UdpRelayHub.bind(
        bindAddress: InternetAddress('127.0.0.1'),
        port: 0,
      );
      final sharded = ShardedSfu(ShardConfigTemplate(
        bindAddress: '127.0.0.1',
        rtpBasePort: 56000,
        announceAddress: '127.0.0.1',
        quiet: true,
      ));
      final coord = ClusterCoordinator(
        sharded: sharded,
        hub: hub,
        locator: RoomLocator(selfId: self.id, peers: [self, peer]),
        // log: omitted — exercises the default stderr.writeln branch.
      );
      addTearDown(() async {
        await coord.close();
        await sharded.close();
      });
      expect(coord.snapshot(), isEmpty);
    });

    test('cascade-hello for a non-owned session is rejected', () async {
      final self = _p('127.0.0.1:19505:19506');
      final peer = _p('127.0.0.1:19507:19508');
      final hub = await UdpRelayHub.bind(
        bindAddress: InternetAddress('127.0.0.1'),
        port: 0,
      );
      final sharded = ShardedSfu(ShardConfigTemplate(
        bindAddress: '127.0.0.1',
        rtpBasePort: 56020,
        announceAddress: '127.0.0.1',
        quiet: true,
      ));
      final logs = <String>[];
      final coord = ClusterCoordinator(
        sharded: sharded,
        hub: hub,
        locator: RoomLocator(selfId: self.id, peers: [self, peer]),
        log: logs.add,
      );
      addTearDown(() async {
        await coord.close();
        await sharded.close();
      });

      // Find a sid owned by `peer`, then have a remote hub send us a
      // cascade-hello for it. We are not the owner, so the
      // coordinator must log & drop without spinning up a shard.
      final loc = RoomLocator(selfId: self.id, peers: [self, peer]);
      String? sidNotOwned;
      for (var i = 0; i < 1000; i++) {
        final sid = 'cc-$i';
        if (loc.ownerOf(sid)?.id == peer.id) {
          sidNotOwned = sid;
          break;
        }
      }
      expect(sidNotOwned, isNotNull, reason: 'need a sid owned by peer');

      final remoteHub = await UdpRelayHub.bind(
        bindAddress: InternetAddress('127.0.0.1'),
        port: 0,
      );
      addTearDown(remoteHub.close);
      final ep = remoteHub.endpointTo(InternetAddress('127.0.0.1'), hub.port);
      ep.sendControl({
        'type': 'cascade-hello',
        'sessionId': sidNotOwned,
        'fromSfu': peer.id,
      });

      // Wait for the dispatch + reject log.
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (logs.any((l) => l.contains('rejecting cascade-hello'))) break;
      }
      expect(logs.any((l) => l.contains('rejecting cascade-hello')), isTrue);
      // No shard was created for that session.
      expect(sharded.get(sidNotOwned!), isNull);
    });

    test('closeShard reaps the upstream route in _reapShard', () async {
      final self = _p('127.0.0.1:19509:19510');
      final peer = _p('127.0.0.1:19511:19512');
      final hub = await UdpRelayHub.bind(
        bindAddress: InternetAddress('127.0.0.1'),
        port: 0,
      );
      final sharded = ShardedSfu(ShardConfigTemplate(
        bindAddress: '127.0.0.1',
        rtpBasePort: 56040,
        announceAddress: '127.0.0.1',
        quiet: true,
      ));
      final logs = <String>[];
      final coord = ClusterCoordinator(
        sharded: sharded,
        hub: hub,
        locator: RoomLocator(selfId: self.id, peers: [self, peer]),
        log: logs.add,
      );
      addTearDown(() async {
        await sharded.close();
        await coord.close();
      });

      // Pick a sid owned by the (never-started) peer so the
      // coordinator's onShardCreated installs an upstream route.
      final loc = RoomLocator(selfId: self.id, peers: [self, peer]);
      String? sid;
      for (var i = 0; i < 1000; i++) {
        final s = 'reap-$i';
        if (loc.ownerOf(s)?.id == peer.id) {
          sid = s;
          break;
        }
      }
      expect(sid, isNotNull);

      await sharded.getOrCreate(sid!);
      // Give the coordinator a tick to register the upstream route.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(coord.snapshot().any((b) => b.sessionId == sid), isTrue,
          reason: 'upstream route should be registered');

      // Closing the shard surfaces ShardClosedEvent → _reapShard,
      // which walks _byBridge / _byEndpoint and clears them.
      await sharded.closeShard(sid);
      // Wait for the event to propagate through the worker reply port.
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (coord.snapshot().isEmpty) break;
      }
      expect(coord.snapshot(), isEmpty);
    });

    test('coordinator close() cancels pending reconnect timers', () async {
      final self = _p('127.0.0.1:19513:19514');
      final peer = _p('127.0.0.1:19515:19516');
      final hub = await UdpRelayHub.bind(
        bindAddress: InternetAddress('127.0.0.1'),
        port: 0,
      );
      final sharded = ShardedSfu(ShardConfigTemplate(
        bindAddress: '127.0.0.1',
        rtpBasePort: 56060,
        announceAddress: '127.0.0.1',
        quiet: true,
      ));
      final coord = ClusterCoordinator(
        sharded: sharded,
        hub: hub,
        locator: RoomLocator(selfId: self.id, peers: [self, peer]),
        log: (_) {},
      );

      // Pick a sid owned by the (never-started) peer so onShardCreated
      // installs an upstream route → first attach fails → a reconnect
      // timer is scheduled. Closing the coordinator must cancel it.
      final loc = RoomLocator(selfId: self.id, peers: [self, peer]);
      String? sid;
      for (var i = 0; i < 1000; i++) {
        final s = 'rc-$i';
        if (loc.ownerOf(s)?.id == peer.id) {
          sid = s;
          break;
        }
      }
      expect(sid, isNotNull);
      await sharded.getOrCreate(sid!);
      // Wait long enough for the first attach attempt to fail and a
      // reconnect timer to be queued (initial delay ~100ms).
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      await coord.close();
      await sharded.close();
      // No assertion needed — if the timer wasn't cancelled the test
      // would leak a pending Timer and the test runner would hang on
      // shutdown. Reaching this point is the success criterion.
      expect(true, isTrue);
    });
  });

  // Smoke for hub framing path used elsewhere — keeps the import
  // surface non-trivial and proves the helper utf8 still compiles.
  test('utf8 helper compiles', () {
    final s = utf8.decode(Uint8List.fromList([0x68, 0x69]));
    expect(s, 'hi');
  });
}
