// Phase 17 — relay PSK auth + observability.
//
// Two scenarios:
//
//   1. Mismatched secret: fake remote SFU sends frames signed with
//      a wrong PSK. The owner's hub rejects them at the framing
//      layer; no inbound bridge ever materialises and the
//      `authFailures` counter on the hub climbs.
//
//   2. Matching secret: fake remote SFU signs with the right PSK
//      and the cascade-hello / handshake completes normally,
//      proving the auth path is the only difference.

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
    final sid = 'p17-$i';
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
  group('Cluster relay PSK auth (Phase 17)', () {
    test('mismatched secret is rejected at framing; authFailures climbs',
        () async {
      final ownerPeer = ClusterPeer.parse('127.0.0.1:18501:18502');
      final fakePeer = ClusterPeer.parse('127.0.0.1:18503:18504');
      final owner = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: ownerPeer.httpPort,
        rtpBase: 58000,
        announceIp: '127.0.0.1',
        quiet: true,
        clusterPeers: [ownerPeer, fakePeer],
        selfClusterId: ownerPeer.id,
        relayPort: ownerPeer.relayPort,
        relaySecret: 'correct-horse-battery-staple',
      );
      final fakeHub = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: fakePeer.relayPort,
        secret: 'wrong-secret',
      );
      final fakeSfu = Sfu(WebRTCTransportConfig(
        bindAddress: InternetAddress.loopbackIPv4,
        rtpBasePort: 58300,
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
      // Fire several signed-with-wrong-secret frames. Every one must
      // be silently dropped by the owner.
      for (var i = 0; i < 5; i++) {
        transport.sendControl({
          'type': 'cascade-hello',
          'sessionId': sid,
          'fromSfu': fakePeer.id,
        });
      }
      relay.start();

      // Give the datagrams plenty of time to arrive and be rejected.
      await Future.delayed(const Duration(milliseconds: 500));

      // /cluster must show no inbound bridge for sid AND a non-zero
      // authFailures counter.
      final j = await _getJson(ownerPeer.httpPort, '/cluster');
      final bridges = (j['bridges'] as List).cast<Map>();
      expect(
        bridges.any(
          (b) =>
              b['sessionId'] == sid &&
              (b['bridgeId'] as String).startsWith('inbound:'),
        ),
        isFalse,
        reason: 'no bridge should attach when MAC fails',
      );
      final relayStats = (j['relay'] as Map).cast<String, Object?>();
      expect(relayStats['authenticated'], isTrue);
      expect(
        relayStats['authFailures'] as int,
        greaterThanOrEqualTo(5),
        reason: 'every wrong-MAC frame must bump authFailures',
      );

      // Cleanly close the relay (its bye will also fail MAC; that's
      // fine, this just exercises the shutdown path).
      await relay.close();
    });

    test('matching secret completes the cascade handshake', () async {
      final secret = 's3cr3t';
      final ownerPeer = ClusterPeer.parse('127.0.0.1:18511:18512');
      final fakePeer = ClusterPeer.parse('127.0.0.1:18513:18514');
      final owner = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: ownerPeer.httpPort,
        rtpBase: 58400,
        announceIp: '127.0.0.1',
        quiet: true,
        clusterPeers: [ownerPeer, fakePeer],
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
        rtpBasePort: 58700,
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

      // /cluster must report the inbound bridge AND zero authFailures.
      final j = await _getJson(ownerPeer.httpPort, '/cluster');
      final bridges = (j['bridges'] as List).cast<Map>();
      expect(
        bridges.any(
          (b) =>
              b['sessionId'] == sid &&
              (b['bridgeId'] as String).startsWith('inbound:'),
        ),
        isTrue,
      );
      final relayStats = (j['relay'] as Map).cast<String, Object?>();
      expect(relayStats['authenticated'], isTrue);
      expect(relayStats['authFailures'], 0);
    });
  });
}
