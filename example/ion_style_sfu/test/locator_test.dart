import 'package:pure_dart_webrtc_ion_style_sfu/src/cluster/locator.dart';
import 'package:test/test.dart';

void main() {
  group('ClusterPeer.parse', () {
    test('host:httpPort defaults relayPort to httpPort+1', () {
      final p = ClusterPeer.parse('10.0.0.1:9090');
      expect(p.host, '10.0.0.1');
      expect(p.httpPort, 9090);
      expect(p.relayPort, 9091);
      expect(p.id, '10.0.0.1:9090');
    });

    test('host:httpPort:relayPort honours explicit relay port', () {
      final p = ClusterPeer.parse('10.0.0.2:9090:7777');
      expect(p.relayPort, 7777);
    });

    test('rejects malformed specs', () {
      expect(() => ClusterPeer.parse('only-host'), throwsFormatException);
      expect(() => ClusterPeer.parse('a:b:c:d'), throwsFormatException);
    });
  });

  group('RoomLocator', () {
    final peers = [
      ClusterPeer.parse('10.0.0.1:9090'),
      ClusterPeer.parse('10.0.0.2:9090'),
      ClusterPeer.parse('10.0.0.3:9090'),
    ];

    test('every session resolves to one of the configured peers', () {
      final loc = RoomLocator(peers: peers, selfId: peers.first.id);
      for (final sid in ['room-a', 'room-b', 'room-c', 'room-d']) {
        final owner = loc.ownerOf(sid);
        expect(owner, isNotNull);
        expect(peers.map((p) => p.id), contains(owner!.id));
      }
    });

    test('ownership is stable across constructions with same membership', () {
      final l1 = RoomLocator(peers: peers);
      final l2 = RoomLocator(peers: peers);
      for (final sid in ['x', 'y', 'z', 'session-with-long-name']) {
        expect(l1.ownerOf(sid)!.id, l2.ownerOf(sid)!.id);
      }
    });

    test('isOwner reflects ownership relative to selfId', () {
      final loc = RoomLocator(peers: peers, selfId: peers[1].id);
      var ownedBySelf = 0;
      const N = 2000;
      for (var i = 0; i < N; i++) {
        if (loc.isOwner('room-$i')) ownedBySelf++;
      }
      // ~1/3 of keys with 3 peers; allow ±15 % drift on a 2 000-key
      // sample.
      final share = ownedBySelf / N;
      expect(share, greaterThan(0.18));
      expect(share, lessThan(0.50));
    });

    test('removing one peer reshuffles only ~1/N of the keys', () {
      final l1 = RoomLocator(peers: peers);
      final reduced = peers.sublist(0, 2);
      final l2 = RoomLocator(peers: reduced);
      var stayed = 0;
      const N = 1000;
      for (var i = 0; i < N; i++) {
        final sid = 'sess-$i';
        final o1 = l1.ownerOf(sid)!.id;
        final o2 = l2.ownerOf(sid)!.id;
        // Keys whose owner is still in the cluster should mostly stay.
        if (o1 == o2 || !reduced.any((p) => p.id == o1)) stayed++;
      }
      // At least 80% of unaffected keys keep their owner. Exact value
      // depends on virtual-node distribution.
      expect(stayed / N, greaterThan(0.8));
    });

    test('empty cluster returns null', () {
      final loc = RoomLocator(peers: const []);
      expect(loc.ownerOf('anything'), isNull);
      expect(loc.isOwner('anything'), isFalse);
    });
  });
}
