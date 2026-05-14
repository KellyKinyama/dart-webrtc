// Phase 24 \u2014 circuit-breaker trip auto-closes the orphaned shard.
//
// Phase 23 stops the reconnect loop after N failures. Phase 24
// completes the cycle: the local non-owner shard, which can never
// reach its owner, is reaped via ShardedSfu.closeShard with the new
// ShardCloseReason.upstreamUnreachable so subscribers see a clean
// close and the worker isolate is freed.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

Future<Map<String, Object?>> _getJson(int port, String path) async {
  final c = HttpClient();
  try {
    final req = await c.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, Object?>;
  } finally {
    c.close(force: true);
  }
}

String _sessionOwnedBy(String ownerId, List<ClusterPeer> peers) {
  final loc = RoomLocator(selfId: ownerId, peers: peers);
  for (var i = 0; i < 1000; i++) {
    final sid = 'p24-$i';
    if (loc.ownerOf(sid)?.id == ownerId) return sid;
  }
  fail('no session id mapped to $ownerId in 1000 tries');
}

Future<void> _waitFor(
  FutureOr<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 15),
  Duration interval = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) return;
    await Future.delayed(interval);
  }
  fail('predicate never became true within $timeout');
}

void main() {
  group('Cluster shard reap on breaker trip (Phase 24)', () {
    test('breaker trip closes the local shard with upstreamUnreachable',
        () async {
      final ownerPeer = ClusterPeer.parse('127.0.0.1:19201:19202');
      final otherPeer = ClusterPeer.parse('127.0.0.1:19203:19204');
      // Owner is intentionally never started.
      final otherSfu = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: otherPeer.httpPort,
        rtpBase: 62800,
        announceIp: '127.0.0.1',
        quiet: true,
        clusterPeers: [ownerPeer, otherPeer],
        selfClusterId: otherPeer.id,
        relayPort: otherPeer.relayPort,
        upstreamReconnectMaxAttempts: 2,
      );
      addTearDown(() async {
        await otherSfu.close();
      });

      // Capture every event the orchestrator surfaces so we can
      // verify the synthetic ShardClosedEvent reason.
      final closes = <ShardClosedEvent>[];
      final prev = otherSfu.sharded.onEvent;
      otherSfu.sharded.onEvent = (e) {
        prev?.call(e);
        if (e is ShardClosedEvent) closes.add(e);
      };

      final sid = _sessionOwnedBy(ownerPeer.id, [ownerPeer, otherPeer]);
      await otherSfu.sharded.getOrCreate(sid);
      // Sanity \u2014 shard is alive.
      expect(otherSfu.sharded.get(sid), isNotNull);

      // Wait for the breaker to trip *and* for the shard to be reaped.
      await _waitFor(() => closes.any(
            (e) =>
                e.sessionId == sid &&
                e.reason == ShardCloseReason.upstreamUnreachable,
          ));

      // Shard should be gone from the registry.
      expect(otherSfu.sharded.get(sid), isNull);
      // Reconnect counters: gave up exactly once.
      final j = await _getJson(otherPeer.httpPort, '/cluster');
      final r = (j['reconnect'] as Map).cast<String, Object?>();
      expect(r['givenUp'], 1);

      // Exactly one synthetic close event for that sid (no double-fire).
      final ours = closes.where((e) => e.sessionId == sid).toList();
      expect(ours.length, 1);
      expect(ours.single.reason, ShardCloseReason.upstreamUnreachable);
    });
  });
}
