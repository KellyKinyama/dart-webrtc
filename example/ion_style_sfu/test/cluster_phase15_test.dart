// Phase 15 — cluster observability + idle-bridge reaper.
//
// Two scenarios:
//
//   1. `/cluster` endpoint surfaces per-bridge stats from the worker
//      (remoteId, established, lastInboundAtMs, idleMs, ...) merged
//      with the coordinator's host:port view.
//
//   2. The worker's idle-bridge reaper closes a bridge whose remote
//      side has gone silent past `bridgeIdleTimeoutMs`, and the
//      closure flows through the existing `bridgeClosed` path so the
//      coordinator drops the route + reclaims the hub endpoint.

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
    final sid = 'p15-$i';
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
  group('Cluster observability + reaper (Phase 15)', () {
    test('/cluster surfaces per-bridge stats from the worker', () async {
      final ownerPeer = ClusterPeer.parse('127.0.0.1:18301:18302');
      final fakePeer = ClusterPeer.parse('127.0.0.1:18303:18304');
      final owner = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: ownerPeer.httpPort,
        rtpBase: 56500,
        announceIp: '127.0.0.1',
        quiet: true,
        clusterPeers: [ownerPeer, fakePeer],
        selfClusterId: ownerPeer.id,
        relayPort: ownerPeer.relayPort,
      );
      final fakeHub = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: fakePeer.relayPort,
      );
      final fakeSfu = Sfu(WebRTCTransportConfig(
        bindAddress: InternetAddress.loopbackIPv4,
        rtpBasePort: 56700,
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
      await Future.delayed(const Duration(milliseconds: 200));
      relay.start();
      await _waitFor(() => relay.established);

      // /cluster should list the inbound bridge with stats merged in.
      Map<String, Object?>? entry;
      await _waitFor(() async {
        final j = await _getJson(ownerPeer.httpPort, '/cluster');
        final bridges = (j['bridges'] as List).cast<Map>();
        for (final b in bridges) {
          if (b['sessionId'] == sid &&
              (b['bridgeId'] as String).startsWith('inbound:') &&
              b.containsKey('established')) {
            entry = b.cast<String, Object?>();
            return true;
          }
        }
        return false;
      });
      final e = entry!;
      expect(e['established'], isTrue);
      expect(e['role'], 'inbound');
      expect(e['remote'], isA<String>());
      expect((e['remote'] as String).contains(':'), isTrue);
      expect(e['remoteId'], isA<String>());
      expect(e['createdAtMs'], isA<int>());
      expect(e['lastInboundAtMs'], isA<int>());
      expect(e['idleMs'], isA<int>());
      // The bridge has just been talked to, so idle should be small.
      expect(e['idleMs'] as int, lessThan(5000));

      // Top-level peers list should mark the owner as self.
      final j = await _getJson(ownerPeer.httpPort, '/cluster');
      final peers = (j['peers'] as List).cast<Map>();
      expect(peers.any((p) => p['id'] == ownerPeer.id && p['self'] == true),
          isTrue);
      expect(peers.any((p) => p['id'] == fakePeer.id && p['self'] == false),
          isTrue);
    });

    test('idle-bridge reaper closes a silent bridge and reclaims the route',
        () async {
      final ownerPeer = ClusterPeer.parse('127.0.0.1:18311:18312');
      final fakePeer = ClusterPeer.parse('127.0.0.1:18313:18314');
      final owner = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: ownerPeer.httpPort,
        rtpBase: 56800,
        announceIp: '127.0.0.1',
        quiet: true,
        clusterPeers: [ownerPeer, fakePeer],
        selfClusterId: ownerPeer.id,
        relayPort: ownerPeer.relayPort,
        // Aggressive timeout so the test runs quickly. Sweep clamps
        // to 250ms minimum, so worst-case lateness ≈ 250ms.
        bridgeIdleTimeoutMs: 600,
      );
      final fakeHub = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: fakePeer.relayPort,
      );
      final fakeSfu = Sfu(WebRTCTransportConfig(
        bindAddress: InternetAddress.loopbackIPv4,
        rtpBasePort: 56900,
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
      await Future.delayed(const Duration(milliseconds: 200));
      relay.start();

      // Wait until the owner registers the inbound bridge.
      await _waitFor(() async {
        final h = await _getJson(ownerPeer.httpPort, '/healthz');
        final bridges = (h['cascadeBridges'] as List).cast<Map>();
        return bridges.any(
          (b) =>
              b['sessionId'] == sid &&
              (b['bridgeId'] as String).startsWith('inbound:'),
        );
      });

      // Now go silent — do not send any further frames. The reaper
      // should close the bridge within ~timeout + sweep.
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
    });
  });
}
