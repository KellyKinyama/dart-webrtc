// Phase 22 \u2014 upstream cascade auto-reconnect with capped backoff.
//
// When a non-owner shard's outbound (upstream) bridge closes \u2014 e.g.
// the owner SFU restarted, the worker's idle reaper fired, or the
// upstream peer sent `bye` \u2014 the coordinator schedules a re-attach
// with capped exponential backoff so the cluster heals automatically.

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

Future<String> _getText(int port, String path) async {
  final c = HttpClient();
  try {
    final req = await c.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    final resp = await req.close();
    return await resp.transform(utf8.decoder).join();
  } finally {
    c.close(force: true);
  }
}

/// Find a session id that is owned by [otherPeer] (not by [selfPeer])
/// so the [selfPeer] node will spin up an upstream bridge to
/// [otherPeer] when the session is created locally.
String _sessionOwnedBy(String ownerId, List<ClusterPeer> peers) {
  final loc = RoomLocator(selfId: ownerId, peers: peers);
  for (var i = 0; i < 1000; i++) {
    final sid = 'p22-$i';
    if (loc.ownerOf(sid)?.id == ownerId) return sid;
  }
  fail('no session id mapped to $ownerId in 1000 tries');
}

Future<void> _waitFor(
  FutureOr<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
  Duration interval = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) return;
    await Future.delayed(interval);
  }
  fail('predicate never became true within $timeout');
}

void main() {
  group('Cluster upstream auto-reconnect (Phase 22)', () {
    test('detaching the upstream bridge triggers an automatic reconnect',
        () async {
      final ownerPeer = ClusterPeer.parse('127.0.0.1:19001:19002');
      final otherPeer = ClusterPeer.parse('127.0.0.1:19003:19004');
      // Two real ion-style SFUs in the same cluster.
      final ownerSfu = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: ownerPeer.httpPort,
        rtpBase: 62000,
        announceIp: '127.0.0.1',
        quiet: true,
        clusterPeers: [ownerPeer, otherPeer],
        selfClusterId: ownerPeer.id,
        relayPort: ownerPeer.relayPort,
      );
      final otherSfu = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: otherPeer.httpPort,
        rtpBase: 62300,
        announceIp: '127.0.0.1',
        quiet: true,
        clusterPeers: [ownerPeer, otherPeer],
        selfClusterId: otherPeer.id,
        relayPort: otherPeer.relayPort,
      );
      addTearDown(() async {
        await ownerSfu.close();
        await otherSfu.close();
      });

      // Pick a session owned by the *owner* node \u2014 so when we create
      // it on the *other* node, the other node spins up an upstream
      // bridge to the owner.
      final sid = _sessionOwnedBy(ownerPeer.id, [ownerPeer, otherPeer]);
      final shard = await otherSfu.sharded.getOrCreate(sid);

      // Wait for the upstream bridge to appear on the other node.
      await _waitFor(() async {
        final stats = await shard.cascadeBridgeStats();
        return stats.any(
            (s) => s['bridgeId'] == 'upstream' && s['established'] == true);
      });

      // Sanity \u2014 no reconnects yet.
      var c = await _getJson(otherPeer.httpPort, '/cluster');
      var rec = (c['reconnect'] as Map).cast<String, Object?>();
      expect(rec['attempts'], 0);
      expect(rec['succeeded'], 0);

      // Tear the upstream down: the worker emits `bridgeClosed` and
      // the coordinator schedules a re-attach (~100ms backoff).
      await shard.cascadeDetach('upstream');

      // Wait for the reconnect to land.
      await _waitFor(() async {
        final j = await _getJson(otherPeer.httpPort, '/cluster');
        final r = (j['reconnect'] as Map).cast<String, Object?>();
        return (r['succeeded'] as int) >= 1;
      });

      // Bridge should be re-established and re-announced as 'upstream'.
      await _waitFor(() async {
        final stats = await shard.cascadeBridgeStats();
        return stats.any(
            (s) => s['bridgeId'] == 'upstream' && s['established'] == true);
      });

      c = await _getJson(otherPeer.httpPort, '/cluster');
      rec = (c['reconnect'] as Map).cast<String, Object?>();
      expect(rec['attempts'] as int, greaterThanOrEqualTo(1));
      expect(rec['succeeded'] as int, greaterThanOrEqualTo(1));

      // /metrics should expose the new counters.
      final metrics = await _getText(otherPeer.httpPort, '/metrics');
      expect(
        metrics,
        contains('ionsfu_cluster_upstream_reconnect_attempts_total '),
      );
      expect(
        metrics,
        contains('ionsfu_cluster_upstream_reconnect_succeeded_total '),
      );
    });
  });
}
