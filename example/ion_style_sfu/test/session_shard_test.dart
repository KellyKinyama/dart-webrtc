import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

void main() {
  group('SessionShard', () {
    test('spawns, accepts RPC, returns stats, closes cleanly', () async {
      final shard = await SessionShard.spawn('room-1');
      addTearDown(shard.close);
      expect(shard.sessionId, 'room-1');

      await shard.addPeer('alice');
      await shard.addPeer('bob');
      await shard.recordRtpForwarded(42);
      await shard.recordRtcpForwarded(7);

      final s = await shard.stats();
      expect(s.sessionId, 'room-1');
      expect(s.peerCount, 2);
      expect(s.peerIds..sort(), ['alice', 'bob']);
      expect(s.rtpForwarded, 42);
      expect(s.rtcpForwarded, 7);
    });

    test('removePeer drops the peer; addPeer is idempotent', () async {
      final shard = await SessionShard.spawn('room-2');
      addTearDown(shard.close);
      await shard.addPeer('alice');
      await shard.addPeer('alice'); // dup
      await shard.addPeer('bob');
      await shard.removePeer('alice');
      await shard.removePeer('charlie'); // missing
      final s = await shard.stats();
      expect(s.peerIds, ['bob']);
    });

    test('many concurrent RPCs all complete with correct order', () async {
      final shard = await SessionShard.spawn('room-3');
      addTearDown(shard.close);
      // Fire 100 increments without awaiting individually.
      final futures = [
        for (var i = 0; i < 100; i++) shard.recordRtpForwarded(1)
      ];
      await Future.wait(futures);
      final s = await shard.stats();
      expect(s.rtpForwarded, 100);
    });

    test('stats() is JSON-serialisable', () async {
      final shard = await SessionShard.spawn('room-4');
      addTearDown(shard.close);
      await shard.addPeer('a');
      final s = await shard.stats();
      final j = s.toJson();
      expect(j['sessionId'], 'room-4');
      expect(j['peerCount'], 1);
    });

    test('calling RPC after close throws StateError', () async {
      final shard = await SessionShard.spawn('room-5');
      await shard.close();
      expect(() => shard.addPeer('x'), throwsStateError);
    });

    test('close() is idempotent', () async {
      final shard = await SessionShard.spawn('room-6');
      await shard.close();
      await shard.close(); // must not throw
    });
  });

  group('ShardedSfu', () {
    test('lazily spawns one shard per session id', () async {
      final sfu = ShardedSfu();
      addTearDown(sfu.close);
      expect(sfu.shardCount, 0);
      final s1 = await sfu.getOrCreate('room-A');
      expect(sfu.shardCount, 1);
      final s2 = await sfu.getOrCreate('room-A');
      expect(identical(s1, s2), isTrue);
      final s3 = await sfu.getOrCreate('room-B');
      expect(sfu.shardCount, 2);
      expect(identical(s1, s3), isFalse);
    });

    test('concurrent getOrCreate for same id deduplicates', () async {
      final sfu = ShardedSfu();
      addTearDown(sfu.close);
      final futures = [for (var i = 0; i < 5; i++) sfu.getOrCreate('room-X')];
      final results = await Future.wait(futures);
      expect(sfu.shardCount, 1);
      for (final r in results) {
        expect(identical(r, results.first), isTrue);
      }
    });

    test('get() returns null for unknown id, shard for known id', () async {
      final sfu = ShardedSfu();
      addTearDown(sfu.close);
      expect(sfu.get('nope'), isNull);
      final s = await sfu.getOrCreate('room-Y');
      expect(identical(sfu.get('room-Y'), s), isTrue);
    });

    test('closeShard tears down a single session', () async {
      final sfu = ShardedSfu();
      addTearDown(sfu.close);
      await sfu.getOrCreate('a');
      await sfu.getOrCreate('b');
      await sfu.closeShard('a');
      expect(sfu.shardCount, 1);
      expect(sfu.get('a'), isNull);
      expect(sfu.get('b'), isNotNull);
    });

    test('close() shuts down every shard and rejects new spawns', () async {
      final sfu = ShardedSfu();
      await sfu.getOrCreate('a');
      await sfu.getOrCreate('b');
      await sfu.close();
      expect(sfu.shardCount, 0);
      expect(() => sfu.getOrCreate('c'), throwsStateError);
    });

    test('shards are independent — state does not leak across', () async {
      final sfu = ShardedSfu();
      addTearDown(sfu.close);
      final a = await sfu.getOrCreate('a');
      final b = await sfu.getOrCreate('b');
      await a.addPeer('alice');
      await b.addPeer('bob');
      final sa = await a.stats();
      final sb = await b.stats();
      expect(sa.peerIds, ['alice']);
      expect(sb.peerIds, ['bob']);
    });
  });
}
