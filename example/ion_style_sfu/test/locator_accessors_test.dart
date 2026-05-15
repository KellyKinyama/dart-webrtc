// Phase B-quick — micro-tests for ClusterPeer.toJson/toString and
// RoomLocator.size. These three covers the trivial accessors that
// existing locator_test.dart skips because they aren't part of the
// hashing logic.

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

void main() {
  group('ClusterPeer accessors', () {
    test('toJson serialises every field', () {
      final p = ClusterPeer(
        id: 'sfu-1',
        host: '10.0.0.1',
        httpPort: 8080,
        relayPort: 8081,
      );
      expect(
        p.toJson(),
        equals({
          'id': 'sfu-1',
          'host': '10.0.0.1',
          'httpPort': 8080,
          'relayPort': 8081,
        }),
      );
    });

    test('toString includes id and relay port', () {
      final s = ClusterPeer(
        id: 'sfu-2',
        host: '10.0.0.2',
        httpPort: 9000,
        relayPort: 9001,
      ).toString();
      expect(s, contains('sfu-2'));
      expect(s, contains('9001'));
    });
  });

  group('RoomLocator.size', () {
    test('returns 0 for empty cluster', () {
      expect(RoomLocator(peers: const []).size, 0);
    });

    test('counts unique peers', () {
      final loc = RoomLocator(peers: [
        ClusterPeer(id: 'a', host: 'a', httpPort: 1, relayPort: 2),
        ClusterPeer(id: 'b', host: 'b', httpPort: 3, relayPort: 4),
        ClusterPeer(id: 'c', host: 'c', httpPort: 5, relayPort: 6),
      ]);
      expect(loc.size, 3);
    });
  });
}
