// Phase 20 \u2014 relay RTT measured from keepalive ping/pong.
//
// Phase 19 added the keepalive emitter; Phase 20 records when each
// ping was sent and matches it against the pong reply, exposing
// `lastRttMs` and `rttEwmaMs` on every bridge plus
// `ionsfu_cluster_bridge_rtt_ms` / `..._rtt_ewma_ms` Prometheus
// gauges.

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

String _sessionOwnedBy(String peerId, List<ClusterPeer> peers) {
  final loc = RoomLocator(selfId: peerId, peers: peers);
  for (var i = 0; i < 1000; i++) {
    final sid = 'p20-$i';
    if (loc.ownerOf(sid)?.id == peerId) return sid;
  }
  fail('no session id mapped to $peerId in 1000 tries');
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
  group('Cluster relay RTT (Phase 20)', () {
    test('keepalive ping/pong populates lastRttMs and rttEwmaMs', () async {
      final ownerPeer = ClusterPeer.parse('127.0.0.1:18801:18802');
      final fakePeer = ClusterPeer.parse('127.0.0.1:18803:18804');
      final owner = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: ownerPeer.httpPort,
        rtpBase: 60800,
        announceIp: '127.0.0.1',
        quiet: true,
        clusterPeers: [ownerPeer, fakePeer],
        selfClusterId: ownerPeer.id,
        relayPort: ownerPeer.relayPort,
        bridgeKeepaliveMs: 100,
      );
      final fakeHub = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: fakePeer.relayPort,
      );
      final fakeSfu = Sfu(WebRTCTransportConfig(
        bindAddress: InternetAddress.loopbackIPv4,
        rtpBasePort: 61100,
      ));
      addTearDown(() async {
        await owner.close();
        await fakeHub.close();
        await fakeSfu.close();
      });

      final sid = _sessionOwnedBy(ownerPeer.id, [ownerPeer, fakePeer]);
      final transport = fakeHub.endpointTo(
        InternetAddress('127.0.0.1'),
        ownerPeer.relayPort,
      );
      final relay = RelayPeer.over(
        remoteId: 'cluster:${fakePeer.id}:$sid',
        session: fakeSfu.getSession(sid),
        transport: transport,
      );
      transport.sendControl({
        'type': 'cascade-hello',
        'sessionId': sid,
        'fromSfu': fakePeer.id,
      });
      await Future.delayed(const Duration(milliseconds: 250));
      relay.start();
      await _waitFor(() => relay.established);

      // Wait for at least one keepalive round-trip to complete.
      final shard = owner.sharded.get(sid)!;
      Map<String, Object?>? inbound;
      await _waitFor(() async {
        final stats = await shard.cascadeBridgeStats();
        for (final s in stats) {
          if ((s['bridgeId'] as String).startsWith('inbound:') &&
              s['lastRttMs'] != null) {
            inbound = s;
            return true;
          }
        }
        return false;
      });

      final lastRtt = inbound!['lastRttMs'] as int;
      final ewma = inbound!['rttEwmaMs'] as num;
      // On loopback the round-trip should be a few ms at most. Allow
      // generous slack for slow CI but assert sanity.
      expect(lastRtt, greaterThanOrEqualTo(0));
      expect(lastRtt, lessThan(1000));
      expect(ewma, greaterThanOrEqualTo(0));
      expect(ewma, lessThan(1000));
      // Pending pings should be drained \u2014 we don't expect more than
      // a couple in flight on loopback.
      expect(inbound!['pendingPings'] as int, lessThan(5));

      // /metrics should expose the new gauges with this bridge's labels.
      final metrics = await _getText(ownerPeer.httpPort, '/metrics');
      expect(metrics, contains('ionsfu_cluster_bridge_rtt_ms{'));
      expect(metrics, contains('ionsfu_cluster_bridge_rtt_ewma_ms{'));
      expect(metrics, contains('session="$sid"'));

      // /cluster should also carry the new fields on this bridge.
      final c = await _getJson(ownerPeer.httpPort, '/cluster');
      final bridges = (c['bridges'] as List).cast<Map>();
      final hb = bridges.firstWhere(
        (b) =>
            b['sessionId'] == sid &&
            (b['bridgeId'] as String).startsWith('inbound:'),
      );
      expect(hb['lastRttMs'], isNotNull);
      expect(hb['rttEwmaMs'], isNotNull);
    });
  });
}
