// Phase 29 — idle-session reaper.
//
// Verifies that a shard spawned with `idleSessionTimeoutMs` and
// never joined by any peer (and with no bridges) self-closes with
// reason [ShardCloseReason.idle] within the timeout window.
//
// The Phase 11 immediate-shutdown-on-last-peer-leave behaviour is
// already covered by session_shard_test.dart; this test specifically
// targets the "born empty, never had a peer" path that Phase 29
// introduces.

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

void main() {
  group('Phase 29 — idle-session reaper', () {
    test('empty shard self-closes after idleSessionTimeoutMs', () async {
      final shard = await SessionShard.spawn(const ShardConfig(
        sessionId: 'born-empty',
        bindAddress: '127.0.0.1',
        rtpBasePort: 19501,
        announceAddress: '127.0.0.1',
        quiet: true,
        idleSessionTimeoutMs: 400,
      ));
      addTearDown(shard.close);

      final closed = <ShardClosedEvent>[];
      final sub = shard.events.listen((e) {
        if (e is ShardClosedEvent) closed.add(e);
      });
      addTearDown(sub.cancel);

      // Wait beyond the configured timeout + one sweep tick.
      await Future.delayed(const Duration(milliseconds: 900));

      expect(closed, isNotEmpty);
      expect(closed.first.reason, ShardCloseReason.idle);
    });

    test('shard with active peer is not reaped while peer is present',
        () async {
      final shard = await SessionShard.spawn(const ShardConfig(
        sessionId: 'busy',
        bindAddress: '127.0.0.1',
        rtpBasePort: 19505,
        announceAddress: '127.0.0.1',
        quiet: true,
        idleSessionTimeoutMs: 300,
      ));
      addTearDown(shard.close);

      final closed = <ShardClosedEvent>[];
      final sub = shard.events.listen((e) {
        if (e is ShardClosedEvent) closed.add(e);
      });
      addTearDown(sub.cancel);

      await shard.join('alice');

      // Past the idle timeout, the shard must still be alive because
      // a peer is present.
      await Future.delayed(const Duration(milliseconds: 600));
      expect(closed, isEmpty);

      final snap = await shard.snapshotJson();
      expect(snap['peers'], 1);
    });
  });
}
