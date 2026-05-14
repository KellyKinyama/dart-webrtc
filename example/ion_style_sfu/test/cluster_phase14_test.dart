// Phase 14 — cluster cascade hardening + reverse-direction (full mesh).
//
// Two scenarios on top of the Phase 13 harness:
//
//   1. Hardening: when a remote SFU sends `bye` (relay close), the
//      owner shard tears down the corresponding inbound bridge,
//      `/healthz` no longer lists it, and the underlying UDP hub
//      endpoint is reclaimed so a fresh hello from the same
//      `host:port` would re-attach cleanly.
//
//   2. Reverse-direction / full mesh: two fake-remote SFUs (A and B)
//      both inbound-cascade to the same owner. A announces a stream;
//      the owner re-exports it across B's bridge so B sees it as a
//      relayed receiver — proving the per-bridge loop-prevention now
//      allows A → owner → B fan-out.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart' show MediaKind;
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

Uint8List _rtp({required int ssrc, required int seq, int pt = 96}) {
  final b = Uint8List(12);
  b[0] = 0x80;
  b[1] = pt & 0x7f;
  b[2] = (seq >> 8) & 0xff;
  b[3] = seq & 0xff;
  b[8] = (ssrc >> 24) & 0xff;
  b[9] = (ssrc >> 16) & 0xff;
  b[10] = (ssrc >> 8) & 0xff;
  b[11] = ssrc & 0xff;
  return b;
}

String _sessionOwnedBy(String peerId, List<ClusterPeer> peers) {
  final loc = RoomLocator(selfId: peerId, peers: peers);
  for (var i = 0; i < 1000; i++) {
    final sid = 'p14-$i';
    if (loc.ownerOf(sid)?.id == peerId) return sid;
  }
  fail('no session id mapped to $peerId in 1000 tries');
}

/// Wait until [predicate] returns true or [timeout] elapses.
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
  group('Cluster cascade hardening (Phase 14)', () {
    late ClusterPeer ownerPeer;
    late ClusterPeer fakeAPeer;
    late IonSfuServerHandle owner;
    late UdpRelayHub fakeAHub;
    late Sfu fakeASfu;

    setUp(() async {
      ownerPeer = ClusterPeer.parse('127.0.0.1:18201:18202');
      fakeAPeer = ClusterPeer.parse('127.0.0.1:18203:18204');
      owner = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: ownerPeer.httpPort,
        rtpBase: 56000,
        announceIp: '127.0.0.1',
        quiet: true,
        clusterPeers: [ownerPeer, fakeAPeer],
        selfClusterId: ownerPeer.id,
        relayPort: ownerPeer.relayPort,
      );
      fakeAHub = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: fakeAPeer.relayPort,
      );
      fakeASfu = Sfu(WebRTCTransportConfig(
        bindAddress: InternetAddress.loopbackIPv4,
        rtpBasePort: 56300,
      ));
    });

    tearDown(() async {
      await owner.close();
      await fakeAHub.close();
      await fakeASfu.close();
    });

    test('remote bye tears down the inbound bridge and reclaims the route',
        () async {
      final sid = _sessionOwnedBy(ownerPeer.id, [ownerPeer, fakeAPeer]);

      final transportA = fakeAHub.endpointTo(
        InternetAddress('127.0.0.1'),
        ownerPeer.relayPort,
      );
      final relayA = RelayPeer.over(
        remoteId: 'cluster:${fakeAPeer.id}:$sid',
        session: fakeASfu.getSession(sid),
        transport: transportA,
      );
      transportA.sendControl({
        'type': 'cascade-hello',
        'sessionId': sid,
        'fromSfu': fakeAPeer.id,
      });
      await Future.delayed(const Duration(milliseconds: 200));
      relayA.start();

      // Wait until the owner has the inbound bridge.
      await _waitFor(() async {
        final h = await _getJson(ownerPeer.httpPort, '/healthz');
        final bridges = (h['cascadeBridges'] as List).cast<Map>();
        return bridges.any(
          (b) =>
              b['sessionId'] == sid &&
              (b['bridgeId'] as String).startsWith('inbound:'),
        );
      });

      // Remote sends bye (close()).
      await relayA.close();

      // Owner reaps the bridge within a couple of event-loop turns.
      await _waitFor(() async {
        final h = await _getJson(ownerPeer.httpPort, '/healthz');
        final bridges = (h['cascadeBridges'] as List).cast<Map>();
        return !bridges.any(
          (b) =>
              b['sessionId'] == sid &&
              (b['bridgeId'] as String).startsWith('inbound:'),
        );
      });

      // The shard's per-bridge stats also drop the entry.
      final shard = owner.sharded.get(sid);
      if (shard != null) {
        final stats = await shard.cascadeBridgeStats();
        expect(
          stats.any((s) =>
              (s['bridgeId'] as String).startsWith('inbound:') &&
              s['established'] == true),
          isFalse,
        );
      }
    });

    test('full-mesh fan-out: A announces, B sees the relayed stream', () async {
      // Add a second fake remote (B) on a third UDP port.
      final fakeBPeer = ClusterPeer.parse('127.0.0.1:18205:18206');
      // Owner has to know about B as well so the locator agrees on
      // ownership when B connects. Re-bind owner with a 3-peer
      // membership.
      await owner.close();
      owner = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: ownerPeer.httpPort,
        rtpBase: 56000,
        announceIp: '127.0.0.1',
        quiet: true,
        clusterPeers: [ownerPeer, fakeAPeer, fakeBPeer],
        selfClusterId: ownerPeer.id,
        relayPort: ownerPeer.relayPort,
      );
      final fakeBHub = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: fakeBPeer.relayPort,
      );
      final fakeBSfu = Sfu(WebRTCTransportConfig(
        bindAddress: InternetAddress.loopbackIPv4,
        rtpBasePort: 56400,
      ));
      addTearDown(() async {
        await fakeBHub.close();
        await fakeBSfu.close();
      });

      final sid = _sessionOwnedBy(
        ownerPeer.id,
        [ownerPeer, fakeAPeer, fakeBPeer],
      );

      // Bring B up first so it's already established when A announces.
      final transportB = fakeBHub.endpointTo(
        InternetAddress('127.0.0.1'),
        ownerPeer.relayPort,
      );
      final relayB = RelayPeer.over(
        remoteId: 'cluster:${fakeBPeer.id}:$sid',
        session: fakeBSfu.getSession(sid),
        transport: transportB,
      );
      Receiver? bSawFromA;
      relayB.onRelayedStream = (recv) {
        bSawFromA = recv;
      };
      transportB.sendControl({
        'type': 'cascade-hello',
        'sessionId': sid,
        'fromSfu': fakeBPeer.id,
      });
      await Future.delayed(const Duration(milliseconds: 200));
      relayB.start();
      await _waitFor(() => relayB.established);

      // Now bring A up and have it announce a stream.
      final transportA = fakeAHub.endpointTo(
        InternetAddress('127.0.0.1'),
        ownerPeer.relayPort,
      );
      final relayA = RelayPeer.over(
        remoteId: 'cluster:${fakeAPeer.id}:$sid',
        session: fakeASfu.getSession(sid),
        transport: transportA,
      );
      transportA.sendControl({
        'type': 'cascade-hello',
        'sessionId': sid,
        'fromSfu': fakeAPeer.id,
      });
      await Future.delayed(const Duration(milliseconds: 200));
      relayA.start();
      await _waitFor(() => relayA.established);

      final stream = ProducerStream(
        kind: 'video',
        mid: 'mesh-v',
        primarySsrc: 0xBEEF01,
        rtxSsrc: null,
        cname: 'cn',
        msidStream: 's',
        msidTrack: 't',
      );
      final localOnA = relayA.router.publishRelayedStream(
        kind: MediaKind.video,
        stream: stream,
      );
      relayA.exportReceiver(localOnA);

      // Push some RTP through A -> owner -> B.
      var bRtp = 0;
      // We don't know B's relayed receiver yet; tap it as soon as it
      // appears.
      final attached = Completer<void>();
      relayB.onRelayedStream = (recv) {
        bSawFromA = recv;
        recv.addRtpTap((_) => bRtp++);
        if (!attached.isCompleted) attached.complete();
      };

      await _waitFor(() => bSawFromA != null,
          timeout: const Duration(seconds: 3));
      expect(bSawFromA!.stream.mid, 'mesh-v');
      expect(bSawFromA!.primarySsrc, 0xBEEF01);

      // Inject a few RTP packets.
      for (var seq = 200; seq < 210; seq++) {
        localOnA.deliverRtp(_rtp(ssrc: 0xBEEF01, seq: seq));
      }
      await _waitFor(() => bRtp >= 1, timeout: const Duration(seconds: 3));
      expect(bRtp, greaterThanOrEqualTo(1),
          reason: 'B should receive RTP that A published, via the owner');
    });
  });
}
