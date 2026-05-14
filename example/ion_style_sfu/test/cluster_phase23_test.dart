// Phase 23 \u2014 circuit breaker on upstream auto-reconnect.
//
// When the owner SFU is permanently gone, the Phase 22 reconnect
// loop would retry forever. With `upstreamReconnectMaxAttempts` set,
// the coordinator gives up after N consecutive establishment
// failures, bumps `upstreamReconnectsGivenUp`, and stops scheduling
// timers for that session.

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

String _sessionOwnedBy(String ownerId, List<ClusterPeer> peers) {
  final loc = RoomLocator(selfId: ownerId, peers: peers);
  for (var i = 0; i < 1000; i++) {
    final sid = 'p23-$i';
    if (loc.ownerOf(sid)?.id == ownerId) return sid;
  }
  fail('no session id mapped to $ownerId in 1000 tries');
}

Future<void> _waitFor(
  FutureOr<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 10),
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
  group('Cluster upstream circuit breaker (Phase 23)', () {
    test(
        'gives up after upstreamReconnectMaxAttempts when owner is unreachable',
        () async {
      final ownerPeer = ClusterPeer.parse('127.0.0.1:19101:19102');
      final otherPeer = ClusterPeer.parse('127.0.0.1:19103:19104');
      // Only run the *other* node \u2014 the owner does not exist.
      final otherSfu = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: otherPeer.httpPort,
        rtpBase: 62500,
        announceIp: '127.0.0.1',
        quiet: true,
        clusterPeers: [ownerPeer, otherPeer],
        selfClusterId: otherPeer.id,
        relayPort: otherPeer.relayPort,
        upstreamReconnectMaxAttempts: 3,
      );
      addTearDown(() async {
        await otherSfu.close();
      });

      // Pick a session whose owner is the missing node; creating it
      // here should kick off the upstream attach, which will never
      // establish because the owner isn't running.
      final sid = _sessionOwnedBy(ownerPeer.id, [ownerPeer, otherPeer]);
      await otherSfu.sharded.getOrCreate(sid);

      // Wait for the breaker to trip.
      await _waitFor(
        () async {
          final j = await _getJson(otherPeer.httpPort, '/cluster');
          final r = (j['reconnect'] as Map).cast<String, Object?>();
          return (r['givenUp'] as int) >= 1;
        },
        timeout: const Duration(seconds: 15),
      );

      final j = await _getJson(otherPeer.httpPort, '/cluster');
      final r = (j['reconnect'] as Map).cast<String, Object?>();
      // We attempted up to the cap, none succeeded, exactly one shard
      // gave up.
      expect(r['attempts'] as int, greaterThanOrEqualTo(3));
      expect(r['succeeded'], 0);
      expect(r['givenUp'], 1);

      // Snapshot the counters; they should not climb further once
      // the breaker has tripped (we wait one full backoff window).
      await Future.delayed(const Duration(seconds: 2));
      final j2 = await _getJson(otherPeer.httpPort, '/cluster');
      final r2 = (j2['reconnect'] as Map).cast<String, Object?>();
      expect(r2['attempts'], r['attempts'],
          reason: 'no more attempts should fire after the breaker trips');
      expect(r2['givenUp'], 1);

      // /metrics should expose the new give-up counter.
      final metrics = await _getText(otherPeer.httpPort, '/metrics');
      expect(metrics,
          contains('ionsfu_cluster_upstream_reconnect_given_up_total '));
    });
  });
}
