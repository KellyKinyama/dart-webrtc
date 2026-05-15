// Phase 19 — relay-level keepalive ping/pong.
//
// Without keepalives, the Phase 15 idle-bridge reaper would tear
// down a healthy-but-silent bridge as soon as media stopped flowing
// (e.g. audio paused, screen-share toggled off). With the new
// `bridgeKeepaliveMs` knob, every established bridge periodically
// emits a relay-level `ping`; the remote side replies with `pong`,
// and the inbound delivery resets `lastInboundAt` so the reaper
// keeps its hands off.

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

String _sessionOwnedBy(String peerId, List<ClusterPeer> peers) {
  final loc = RoomLocator(selfId: peerId, peers: peers);
  for (var i = 0; i < 1000; i++) {
    final sid = 'p19-$i';
    if (loc.ownerOf(sid)?.id == peerId) return sid;
  }
  fail('no session id mapped to $peerId in 1000 tries');
}

Future<void> _waitFor(
  FutureOr<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 4),
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
  group('Cluster relay keepalive (Phase 19)', () {
    test(
        'keepalive ping prevents the idle reaper from tearing down a '
        'silent bridge', () async {
      final ownerPeer = ClusterPeer.parse('127.0.0.1:18701:18702');
      final fakePeer = ClusterPeer.parse('127.0.0.1:18703:18704');
      // Reaper at 600ms, keepalive at 200ms — keepalive << timeout / 2.
      final owner = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: ownerPeer.httpPort,
        rtpBase: 60000,
        announceIp: '127.0.0.1',
        quiet: true,
        clusterPeers: [ownerPeer, fakePeer],
        selfClusterId: ownerPeer.id,
        relayPort: ownerPeer.relayPort,
        bridgeIdleTimeoutMs: 600,
        bridgeKeepaliveMs: 200,
      );
      final fakeHub = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: fakePeer.relayPort,
      );
      final fakeSfu = Sfu(WebRTCTransportConfig(
        bindAddress: InternetAddress.loopbackIPv4,
        rtpBasePort: 60300,
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

      // Wait long enough that, without keepalives, the reaper would
      // have killed the bridge multiple times over.
      await Future.delayed(const Duration(milliseconds: 1800));

      final h = await _getJson(ownerPeer.httpPort, '/healthz');
      final bridges = (h['cascadeBridges'] as List).cast<Map>();
      expect(
        bridges.any(
          (b) =>
              b['sessionId'] == sid &&
              (b['bridgeId'] as String).startsWith('inbound:'),
        ),
        isTrue,
        reason: 'keepalive must keep the bridge alive past the idle timeout',
      );

      // Per-bridge stats should show idleMs well under the timeout
      // because pings keep bumping lastInboundAt.
      final shard = owner.sharded.get(sid)!;
      final stats = await shard.cascadeBridgeStats();
      final inbound = stats.firstWhere(
        (s) => (s['bridgeId'] as String).startsWith('inbound:'),
      );
      expect(inbound['idleMs'] as int, lessThan(600),
          reason: 'idleMs must be reset by inbound ping/pong traffic');
    }, retry: 2);

    test(
        'turning keepalive off lets the reaper close the bridge as before '
        '(regression check)', () async {
      final ownerPeer = ClusterPeer.parse('127.0.0.1:18711:18712');
      final fakePeer = ClusterPeer.parse('127.0.0.1:18713:18714');
      // Reaper on, keepalive off.
      final owner = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: ownerPeer.httpPort,
        rtpBase: 60400,
        announceIp: '127.0.0.1',
        quiet: true,
        clusterPeers: [ownerPeer, fakePeer],
        selfClusterId: ownerPeer.id,
        relayPort: ownerPeer.relayPort,
        bridgeIdleTimeoutMs: 600,
      );
      final fakeHub = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: fakePeer.relayPort,
      );
      final fakeSfu = Sfu(WebRTCTransportConfig(
        bindAddress: InternetAddress.loopbackIPv4,
        rtpBasePort: 60700,
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

      await _waitFor(() async {
        final h = await _getJson(ownerPeer.httpPort, '/healthz');
        final bridges = (h['cascadeBridges'] as List).cast<Map>();
        return bridges.any(
          (b) =>
              b['sessionId'] == sid &&
              (b['bridgeId'] as String).startsWith('inbound:'),
        );
      });

      // Without keepalives the reaper should close the bridge.
      await _waitFor(
        () async {
          final h = await _getJson(ownerPeer.httpPort, '/healthz');
          final bridges = (h['cascadeBridges'] as List).cast<Map>();
          return !bridges.any(
            (b) =>
                b['sessionId'] == sid &&
                (b['bridgeId'] as String).startsWith('inbound:'),
          );
        },
        timeout: const Duration(seconds: 4),
      );
    }, retry: 2);
  });
}
