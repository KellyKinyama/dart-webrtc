// Phase 18 — Prometheus exposition for cluster/relay metrics.
//
// Two scenarios on top of the existing `/metrics` (Phase 10):
//
//   1. Sharded mode (no cluster): /metrics returns the existing
//      ionsfu_* SFU metrics and *no* cluster/relay metrics.
//   2. Cluster mode with a live inbound bridge: /metrics now also
//      exposes ionsfu_relay_* counters and per-bridge gauges
//      (established / inbound_rtp_packets / idle_ms / relayed_receivers).
//      A wrong-secret peer additionally bumps
//      ionsfu_relay_auth_failures_total above zero.

import 'dart:async';
import 'dart:io';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

Future<String> _getText(int port, String path) async {
  final c = HttpClient();
  try {
    final req = await c.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    final resp = await req.close();
    return await resp.transform(const SystemEncoding().decoder).join();
  } finally {
    c.close(force: true);
  }
}

String _sessionOwnedBy(String peerId, List<ClusterPeer> peers) {
  final loc = RoomLocator(selfId: peerId, peers: peers);
  for (var i = 0; i < 1000; i++) {
    final sid = 'p18-$i';
    if (loc.ownerOf(sid)?.id == peerId) return sid;
  }
  fail('no session id mapped to $peerId in 1000 tries');
}

Future<void> _waitFor(
  FutureOr<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
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
  group('Prometheus cluster metrics (Phase 18)', () {
    test('/metrics omits cluster series in sharded (non-cluster) mode',
        () async {
      final h = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: 18601,
        rtpBase: 59000,
        announceIp: '127.0.0.1',
        quiet: true,
      );
      addTearDown(h.close);

      final body = await _getText(18601, '/metrics');
      // Existing series must still be present.
      expect(body, contains('ionsfu_sessions'));
      expect(body, contains('ionsfu_peers'));
      // Cluster series must NOT be present.
      expect(body, isNot(contains('ionsfu_cluster_')));
      expect(body, isNot(contains('ionsfu_relay_')));
    });

    test('/metrics exposes relay + per-bridge series in cluster mode',
        () async {
      final secret = 'm3tr1cs';
      final ownerPeer = ClusterPeer.parse('127.0.0.1:18611:18612');
      final fakePeer = ClusterPeer.parse('127.0.0.1:18613:18614');
      final wrongPeer = ClusterPeer.parse('127.0.0.1:18615:18616');
      final owner = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: ownerPeer.httpPort,
        rtpBase: 59100,
        announceIp: '127.0.0.1',
        quiet: true,
        clusterPeers: [ownerPeer, fakePeer, wrongPeer],
        selfClusterId: ownerPeer.id,
        relayPort: ownerPeer.relayPort,
        relaySecret: secret,
      );
      final fakeHub = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: fakePeer.relayPort,
        secret: secret,
      );
      final fakeSfu = Sfu(WebRTCTransportConfig(
        bindAddress: InternetAddress.loopbackIPv4,
        rtpBasePort: 59400,
      ));
      final wrongHub = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: wrongPeer.relayPort,
        secret: 'definitely-not-the-right-key',
      );
      addTearDown(() async {
        await owner.close();
        await fakeHub.close();
        await fakeSfu.close();
        await wrongHub.close();
      });

      final sid = _sessionOwnedBy(
          ownerPeer.id, [ownerPeer, fakePeer, wrongPeer]);

      // Bring up a real (correctly-signed) inbound bridge.
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

      // Fire a few wrong-secret datagrams so authFailures climbs.
      // Yield between sends so each one actually leaves the socket
      // (RawDatagramSocket.send is non-blocking and a tight loop can
      // race the writability signal on Windows).
      final wrongTransport = wrongHub.endpointTo(
        InternetAddress('127.0.0.1'),
        ownerPeer.relayPort,
      );
      for (var i = 0; i < 6; i++) {
        wrongTransport.sendControl({
          'type': 'cascade-hello',
          'sessionId': sid,
          'fromSfu': wrongPeer.id,
        });
        await Future.delayed(const Duration(milliseconds: 30));
      }
      await Future.delayed(const Duration(milliseconds: 250));

      final body = await _getText(ownerPeer.httpPort, '/metrics');

      // Self / authentication / relay-level counters.
      expect(body, contains('ionsfu_cluster_self{id="${ownerPeer.id}"} 1'));
      expect(body, contains('ionsfu_relay_authenticated 1'));
      expect(body, contains('ionsfu_relay_auth_failures_total'));
      // The wrong-secret datagrams must have bumped the counter.
      final m =
          RegExp(r'ionsfu_relay_auth_failures_total (\d+)').firstMatch(body);
      expect(m, isNotNull);
      expect(int.parse(m!.group(1)!), greaterThanOrEqualTo(1),
          reason: 'at least one wrong-secret frame must be counted');

      // Cluster-level + per-bridge series.
      expect(body, contains('ionsfu_cluster_bridges'));
      expect(body, contains('ionsfu_cluster_bridge_established'));
      expect(body, contains('ionsfu_cluster_bridge_idle_ms'));
      expect(body, contains('ionsfu_cluster_bridge_relayed_receivers'));
      expect(body, contains('ionsfu_cluster_bridge_inbound_rtp_packets_total'));
      // The labels for our live inbound bridge should be present and
      // marked established=1.
      expect(
        RegExp(
                r'ionsfu_cluster_bridge_established\{[^}]*session="' +
                    RegExp.escape(sid) +
                    r'"[^}]*\} 1')
            .hasMatch(body),
        isTrue,
        reason: 'inbound bridge for $sid should be reported established=1',
      );
    });
  });
}
