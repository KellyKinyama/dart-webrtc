// Phase 12 — cluster cascade tests.
//
// We don't run real WebRTC peers here (that's covered by the broader
// peer-connection suite). Instead we verify that:
//
//   * Two SFUs with overlapping cluster membership boot correctly.
//   * When a session is created on the non-owner SFU, an upstream
//     cascade bridge appears in `/healthz`.
//   * The owner SFU lazily materialises the matching shard and
//     surfaces a corresponding inbound bridge.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

Future<Map<String, Object?>> _getJson(int port, String path) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, Object?>;
  } finally {
    client.close(force: true);
  }
}

Future<int> _findRoomOwnedByPeer(
  String peerId,
  List<ClusterPeer> peers,
) async {
  // Look up via /locate against peer that owns the lookup table.
  for (var i = 0; i < 200; i++) {
    final candidate = 'room-$i';
    // Just consult the locator directly via a fresh instance — both
    // SFUs share identical config so they agree on ownership.
    final loc = RoomLocator(selfId: peerId, peers: peers);
    if (loc.ownerOf(candidate)?.id == peerId) return i;
  }
  fail('no candidate session id mapped to $peerId in 200 tries');
}

void main() {
  group('Cluster cascade (Phase 12)', () {
    late ClusterPeer p1;
    late ClusterPeer p2;
    late IonSfuServerHandle s1;
    late IonSfuServerHandle s2;

    setUp(() async {
      p1 = ClusterPeer.parse('127.0.0.1:18091:18092');
      p2 = ClusterPeer.parse('127.0.0.1:18093:18094');
      final peers = [p1, p2];

      s1 = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: p1.httpPort,
        rtpBase: 54000,
        announceIp: '127.0.0.1',
        quiet: true,
        clusterPeers: peers,
        selfClusterId: p1.id,
        relayPort: p1.relayPort,
      );
      s2 = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: p2.httpPort,
        rtpBase: 54200,
        announceIp: '127.0.0.1',
        quiet: true,
        clusterPeers: peers,
        selfClusterId: p2.id,
        relayPort: p2.relayPort,
      );
    });

    tearDown(() async {
      await s1.close();
      await s2.close();
    });

    test('/healthz reports cluster mode on both nodes', () async {
      final h1 = await _getJson(p1.httpPort, '/healthz');
      final h2 = await _getJson(p2.httpPort, '/healthz');
      expect(h1['mode'], 'cluster');
      expect(h2['mode'], 'cluster');
      expect(h1['self'], p1.id);
      expect(h2['self'], p2.id);
      expect(h1['peers'], 2);
    });

    test('/locate routes session ids to the owning peer', () async {
      final loc = RoomLocator(selfId: p1.id, peers: [p1, p2]);
      final owned = await _findRoomOwnedByPeer(p1.id, [p1, p2]);
      final other = await _findRoomOwnedByPeer(p2.id, [p1, p2]);

      final r1 = await _getJson(p1.httpPort, '/locate?sid=room-$owned');
      expect((r1['owner'] as Map)['self'], true);

      final r2 = await _getJson(p1.httpPort, '/locate?sid=room-$other');
      expect((r2['owner'] as Map)['self'], false);
      expect((r2['owner'] as Map)['id'], p2.id);

      // Sanity: locator agrees.
      expect(loc.ownerOf('room-$owned')?.id, p1.id);
      expect(loc.ownerOf('room-$other')?.id, p2.id);
    });

    test('non-owner shard opens an upstream cascade bridge', () async {
      // Pick a session id owned by p2 and create it on p1.
      final ownedByP2 = await _findRoomOwnedByPeer(p2.id, [p1, p2]);
      final sid = 'room-$ownedByP2';
      final shard = await s1.sharded.getOrCreate(sid);
      expect(shard.sessionId, sid);

      // The upstream bridge is attached synchronously when the shard
      // is created. Allow the relay handshake to round-trip.
      await Future.delayed(const Duration(milliseconds: 1500));

      final h1 = await _getJson(p1.httpPort, '/healthz');
      final bridges = (h1['cascadeBridges'] as List).cast<Map>();
      expect(
        bridges.any(
          (b) => b['sessionId'] == sid && b['bridgeId'] == 'upstream',
        ),
        isTrue,
        reason: 'p1 should have an upstream bridge for $sid; got $bridges',
      );

      // The owner (p2) should have lazily materialised an inbound
      // bridge after the cascade-hello round-trip.
      final h2 = await _getJson(p2.httpPort, '/healthz');
      final inbound = (h2['cascadeBridges'] as List).cast<Map>();
      expect(
        inbound.any(
          (b) =>
              b['sessionId'] == sid &&
              (b['bridgeId'] as String).startsWith('inbound:'),
        ),
        isTrue,
        reason: 'p2 should have an inbound bridge for $sid; got $inbound',
      );
    });

    test('owner-side session creation does NOT spawn a cascade', () async {
      final ownedByP1 = await _findRoomOwnedByPeer(p1.id, [p1, p2]);
      final sid = 'room-$ownedByP1';
      await s1.sharded.getOrCreate(sid);
      await Future.delayed(const Duration(milliseconds: 100));
      final h1 = await _getJson(p1.httpPort, '/healthz');
      final bridges = (h1['cascadeBridges'] as List).cast<Map>();
      expect(
        bridges.any((b) => b['sessionId'] == sid),
        isFalse,
        reason: 'owner shard should not open any outbound bridge',
      );
    });
  });
}
