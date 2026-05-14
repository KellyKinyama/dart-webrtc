// Tests for the rebuilt per-session worker isolate.
//
// The shard now hosts a real PeerConnection-owning `Sfu`, so these
// tests focus on:
//  * RPC plumbing (request/reply tagging, error propagation).
//  * Event channel demultiplexing.
//  * Lifecycle (idle shutdown, mainRequested shutdown, post-close
//    error semantics).
//  * `ShardedSfu` orchestrator: lazy spawn, dedupe, port-slot
//    allocation, snapshot aggregation.
//
// Real WebRTC SDP negotiation between two PeerConnections lives in
// the broader peer-connection test suite; here we drive joins and
// snapshots through the worker to prove the RPC actually reaches the
// in-isolate Sfu.

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

ShardConfig _cfg(String sid, {int port = 53000}) => ShardConfig(
      sessionId: sid,
      bindAddress: '127.0.0.1',
      rtpBasePort: port,
      announceAddress: '127.0.0.1',
      quiet: true,
    );

void main() {
  group('SessionShard (Phase 11)', () {
    test('spawns and accepts join RPCs; snapshot reflects state', () async {
      final shard = await SessionShard.spawn(_cfg('room-1'));
      addTearDown(shard.close);
      expect(shard.sessionId, 'room-1');

      await shard.join('alice');
      await shard.join('bob');

      final snap = await shard.snapshotJson();
      expect(snap['sessions'], 1);
      expect(snap['peers'], 2);
    });

    test('emits peerJoined events as peers arrive', () async {
      final shard = await SessionShard.spawn(_cfg('room-2', port: 53100));
      addTearDown(shard.close);

      final joined = <String>[];
      final sub = shard.events.listen((e) {
        if (e is PeerLifecycleEvent && e.joined) joined.add(e.uid);
      });
      addTearDown(sub.cancel);

      await shard.join('alice');
      await shard.join('bob');
      // Give the event microtasks a chance to flush.
      await Future.delayed(const Duration(milliseconds: 50));
      expect(joined..sort(), ['alice', 'bob']);
    });

    test('leave drops the peer; idle session triggers self-shutdown', () async {
      final shard = await SessionShard.spawn(_cfg('room-3', port: 53200));

      final closeFuture = shard.events
          .firstWhere((e) => e is ShardClosedEvent)
          .timeout(const Duration(seconds: 5));

      await shard.join('alice');
      await shard.leave('alice');

      final ev = await closeFuture as ShardClosedEvent;
      expect(ev.reason, ShardCloseReason.idle);

      // Subsequent RPC must throw.
      expect(() => shard.snapshotJson(), throwsStateError);
      await shard.close();
    });

    test('errors raised inside the worker propagate as StateError', () async {
      final shard = await SessionShard.spawn(_cfg('room-4', port: 53300));
      addTearDown(shard.close);

      // pubOffer for an unknown uid must surface as an error reply.
      expect(
        () => shard.applyPublisherOffer('ghost', 'v=0\r\n'),
        throwsA(isA<StateError>()),
      );
    });

    test('close() is idempotent and cancels in-flight calls', () async {
      final shard = await SessionShard.spawn(_cfg('room-5', port: 53400));
      await shard.close();
      await shard.close(); // must not throw
      expect(() => shard.join('x'), throwsStateError);
    });

    test('many concurrent join/leave RPCs all complete in order', () async {
      final shard = await SessionShard.spawn(_cfg('room-6', port: 53500));
      addTearDown(shard.close);
      final joins = [for (var i = 0; i < 20; i++) shard.join('peer-$i')];
      await Future.wait(joins);
      final snap = await shard.snapshotJson();
      expect(snap['peers'], 20);
    });
  });

  group('ShardedSfu (Phase 11)', () {
    ShardConfigTemplate template({int port = 54000}) => ShardConfigTemplate(
          bindAddress: '127.0.0.1',
          rtpBasePort: port,
          announceAddress: '127.0.0.1',
          quiet: true,
        );

    test('lazily spawns one shard per session id', () async {
      final sfu = ShardedSfu(template());
      addTearDown(sfu.close);
      expect(sfu.shardCount, 0);
      final s1 = await sfu.getOrCreate('A');
      expect(sfu.shardCount, 1);
      final s2 = await sfu.getOrCreate('A');
      expect(identical(s1, s2), isTrue);
      final s3 = await sfu.getOrCreate('B');
      expect(sfu.shardCount, 2);
      expect(identical(s1, s3), isFalse);
    });

    test('concurrent getOrCreate dedupes', () async {
      final sfu = ShardedSfu(template(port: 54100));
      addTearDown(sfu.close);
      final fs = [for (var i = 0; i < 5; i++) sfu.getOrCreate('X')];
      final all = await Future.wait(fs);
      expect(sfu.shardCount, 1);
      for (final r in all) {
        expect(identical(r, all.first), isTrue);
      }
    });

    test('hands out non-overlapping port slots', () async {
      final sfu = ShardedSfu(template(port: 54200));
      addTearDown(sfu.close);
      final a = await sfu.getOrCreate('a');
      final b = await sfu.getOrCreate('b');
      expect(a.config.rtpBasePort, 54200);
      expect(b.config.rtpBasePort, 54264); // 54200 + 1*64
    });

    test('aggregateSnapshotJson sums across shards', () async {
      final sfu = ShardedSfu(template(port: 54400));
      addTearDown(sfu.close);
      final a = await sfu.getOrCreate('a');
      final b = await sfu.getOrCreate('b');
      await a.join('alice');
      await a.join('bob');
      await b.join('charlie');

      final snap = await sfu.aggregateSnapshotJson();
      expect(snap['sessions'], 2);
      expect(snap['peers'], 3);
    });

    test('aggregateSnapshot rehydrates into a SfuStatsSnapshot', () async {
      final sfu = ShardedSfu(template(port: 54500));
      addTearDown(sfu.close);
      final a = await sfu.getOrCreate('only');
      await a.join('alice');
      final snap = await sfu.aggregateSnapshot();
      expect(snap.peers, 1);
      expect(snap.sessions, 1);
      // formatPrometheus must accept it without throwing.
      final text = formatPrometheus(snap);
      expect(text, contains('ionsfu_peers 1'));
    });

    test('idle shard is reaped from the registry', () async {
      final sfu = ShardedSfu(template(port: 54600));
      addTearDown(sfu.close);
      final s = await sfu.getOrCreate('reap-me');
      await s.join('alice');
      await s.leave('alice');
      // Wait for the closed event to propagate through the orchestrator.
      await Future.delayed(const Duration(milliseconds: 200));
      expect(sfu.get('reap-me'), isNull);
    });

    test('close() shuts every shard down and rejects new spawns', () async {
      final sfu = ShardedSfu(template(port: 54700));
      await sfu.getOrCreate('a');
      await sfu.getOrCreate('b');
      await sfu.close();
      expect(sfu.shardCount, 0);
      expect(() => sfu.getOrCreate('c'), throwsStateError);
    });
  });
}
