// Phase 25 — resource caps.
//
// Verifies:
//  * `ShardConfigTemplate.maxSessions` makes [ShardedSfu.getOrCreate]
//    throw [SfuOverloadedException] once the per-node cap is hit, and
//    bumps `sessionsRejectedAtCap`.
//  * `ShardConfigTemplate.maxPeersPerSession` propagates to the
//    worker, which rejects further join() calls past the cap with
//    [SessionFullException]. Existing peers in the cap window are
//    unaffected; a re-join from an already-present uid is tolerated.

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

void main() {
  group('Phase 25 — resource caps', () {
    test('ShardedSfu enforces maxSessions and counts rejections', () async {
      final sharded = ShardedSfu(const ShardConfigTemplate(
        bindAddress: '127.0.0.1',
        rtpBasePort: 19301,
        announceAddress: '127.0.0.1',
        quiet: true,
        maxSessions: 2,
      ));
      addTearDown(sharded.close);

      final s1 = await sharded.getOrCreate('room-a');
      final s2 = await sharded.getOrCreate('room-b');
      expect(s1.sessionId, 'room-a');
      expect(s2.sessionId, 'room-b');
      expect(sharded.sessionsRejectedAtCap, 0);

      // Third spawn must be rejected with the typed exception.
      await expectLater(
        () => sharded.getOrCreate('room-c'),
        throwsA(isA<SfuOverloadedException>()),
      );
      expect(sharded.sessionsRejectedAtCap, 1);

      // Repeat lookup of an existing session must still succeed.
      final s1again = await sharded.getOrCreate('room-a');
      expect(identical(s1, s1again), isTrue);
      expect(sharded.sessionsRejectedAtCap, 1);
    });

    test('worker rejects join past maxPeersPerSession', () async {
      final shard = await SessionShard.spawn(const ShardConfig(
        sessionId: 'capped',
        bindAddress: '127.0.0.1',
        rtpBasePort: 19305,
        announceAddress: '127.0.0.1',
        quiet: true,
        maxPeersPerSession: 2,
      ));
      addTearDown(shard.close);

      await shard.join('alice');
      await shard.join('bob');

      // Re-join of an existing uid is a no-op.
      await shard.join('alice');

      // Third uid must be rejected — error surfaces as the toString().
      await expectLater(
        () => shard.join('carol'),
        throwsA(
            predicate((e) => e.toString().contains('SessionFullException'))),
      );

      final snap = await shard.snapshotJson();
      expect(snap['peers'], 2);
    });
  });
}
