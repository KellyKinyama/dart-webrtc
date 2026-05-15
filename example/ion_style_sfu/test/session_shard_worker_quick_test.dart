// Worker-isolate quick wins for session_shard.
//   * codec materialiser: vp9 / h264 / pcma branches.
//   * SessionShard.close() drives the worker's `'close'` dispatch
//     case (and _shutdown of bridges/peers).
//   * Idle-session reaper marks empty sessions for closure.

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

void main() {
  group('SessionShard codec materialiser', () {
    test('vp9 + h264 + pcma codec configs spawn cleanly', () async {
      final sfu = ShardedSfu(ShardConfigTemplate(
        bindAddress: '127.0.0.1',
        rtpBasePort: 56500,
        announceAddress: '127.0.0.1',
        quiet: true,
        videoCodecs: const [ShardCodec.vp9, ShardCodec.h264, ShardCodec.vp8],
        audioCodecs: const [ShardCodec.pcma, ShardCodec.pcmu],
      ));
      addTearDown(sfu.close);
      final shard = await sfu.getOrCreate('codecs');
      expect(shard.sessionId, 'codecs');
      // Snapshot just to round-trip an op through the worker.
      final snap = await shard.snapshotJson();
      expect(snap['peers'], 0);
    });
  });

  group('SessionShard explicit close()', () {
    test('SessionShard.close() drives the worker close dispatch',
        () async {
      final sfu = ShardedSfu(ShardConfigTemplate(
        bindAddress: '127.0.0.1',
        rtpBasePort: 56520,
        announceAddress: '127.0.0.1',
        quiet: true,
      ));
      final shard = await sfu.getOrCreate('bye');
      expect(shard.isClosed, isFalse);
      await shard.close();
      expect(shard.isClosed, isTrue);
      // ShardedSfu.close() must remain idempotent after individual close.
      await sfu.close();
    });
  });

  group('SessionShard idle reaper', () {
    test('idle empty session is reaped automatically', () async {
      final sfu = ShardedSfu(ShardConfigTemplate(
        bindAddress: '127.0.0.1',
        rtpBasePort: 56540,
        announceAddress: '127.0.0.1',
        quiet: true,
        idleSessionTimeoutMs: 400,
      ));
      addTearDown(sfu.close);
      final closes = <ShardClosedEvent>[];
      sfu.onEvent = (e) {
        if (e is ShardClosedEvent) closes.add(e);
      };
      final shard = await sfu.getOrCreate('idle');
      expect(shard.sessionId, 'idle');
      // Wait for the reaper tick (idleTimeoutMs/4 clamped to >=100ms,
      // so at most ~500ms after the timeout elapses).
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (closes.any((e) =>
            e.sessionId == 'idle' && e.reason == ShardCloseReason.idle)) {
          break;
        }
      }
      expect(
        closes.any((e) =>
            e.sessionId == 'idle' && e.reason == ShardCloseReason.idle),
        isTrue,
      );
    });
  });
}
