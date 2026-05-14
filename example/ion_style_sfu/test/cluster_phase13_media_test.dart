// Phase 13 — end-to-end media across the cluster cascade.
//
// Approach: boot one real clustered SFU as the *owner* of a known
// session id, then drive the SFU's UDP relay socket from the test as
// if we were a remote sibling SFU. We:
//
//   1. Open a second [UdpRelayHub] on a private port (the "fake
//      remote SFU").
//   2. Send a `cascade-hello` for a session sid that the locator maps
//      to the real SFU.
//   3. Run a real [RelayPeer] over that hub, complete the relay
//      handshake, announce a synthetic stream, and inject RTP.
//   4. Assert the real SFU's worker fires a [RelayedStreamEvent] for
//      the announced mid, and that its `/stats` snapshot reflects the
//      new relayed receiver.

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

/// Pick a session id whose consistent-hash owner is [peerId].
String _sessionOwnedBy(String peerId, List<ClusterPeer> peers) {
  final loc = RoomLocator(selfId: peerId, peers: peers);
  for (var i = 0; i < 1000; i++) {
    final sid = 'p13-$i';
    if (loc.ownerOf(sid)?.id == peerId) return sid;
  }
  fail('no session id mapped to $peerId in 1000 tries');
}

void main() {
  group('Cluster cascade media (Phase 13)', () {
    late ClusterPeer ownerPeer;
    late ClusterPeer fakePeer;
    late IonSfuServerHandle owner;
    late UdpRelayHub fakeHub;
    // Local Sfu used only to host a Session for the fake-remote
    // RelayPeer (its router holds the synthetic publisher).
    late Sfu fakeSfu;

    setUp(() async {
      ownerPeer = ClusterPeer.parse('127.0.0.1:18101:18102');
      fakePeer = ClusterPeer.parse('127.0.0.1:18103:18104');
      owner = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: ownerPeer.httpPort,
        rtpBase: 55000,
        announceIp: '127.0.0.1',
        quiet: true,
        clusterPeers: [ownerPeer, fakePeer],
        selfClusterId: ownerPeer.id,
        relayPort: ownerPeer.relayPort,
      );
      fakeHub = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: fakePeer.relayPort,
      );
      fakeSfu = Sfu(WebRTCTransportConfig(
        bindAddress: InternetAddress.loopbackIPv4,
        rtpBasePort: 55300,
      ));
    });

    tearDown(() async {
      await owner.close();
      await fakeHub.close();
      await fakeSfu.close();
    });

    test('cascade-hello + announce + RTP reaches owner shard', () async {
      final sid = _sessionOwnedBy(ownerPeer.id, [ownerPeer, fakePeer]);

      // Subscribe to shard events BEFORE we trigger anything.
      final relayedEvents = <RelayedStreamEvent>[];
      final sub = owner.sharded.onEvent;
      owner.sharded.onEvent = (e) {
        sub?.call(e);
        if (e is RelayedStreamEvent) relayedEvents.add(e);
      };

      // Build the fake-remote RelayPeer talking over the UDP socket
      // to the real owner SFU's relay port.
      final transport = fakeHub.endpointTo(
        InternetAddress('127.0.0.1'),
        ownerPeer.relayPort,
      );
      final fakeSession = fakeSfu.getSession(sid);
      final fakeRelay = RelayPeer.over(
        remoteId: 'cluster:${fakePeer.id}:$sid',
        session: fakeSession,
        transport: transport,
      );

      // The real SFU only opens an inbound bridge after a
      // cascade-hello control frame. Send it on the same socket BEFORE
      // the relay hello so the coordinator can lazily attach.
      transport.sendControl({
        'type': 'cascade-hello',
        'sessionId': sid,
        'fromSfu': fakePeer.id,
      });
      // Give the coordinator one event-loop hop to materialise the
      // shard + bridge.
      await Future.delayed(const Duration(milliseconds: 250));
      fakeRelay.start();

      // Synthesize a publisher on the fake side and export it.
      final stream = ProducerStream(
        kind: 'video',
        mid: 'remote-v',
        primarySsrc: 0xCAFE01,
        rtxSsrc: null,
        cname: 'cn',
        msidStream: 's',
        msidTrack: 't',
      );
      final localRecv = fakeRelay.router.publishRelayedStream(
        kind: MediaKind.video,
        stream: stream,
      );
      // Wait for the relay handshake to round-trip before exporting.
      await Future.delayed(const Duration(milliseconds: 250));
      fakeRelay.exportReceiver(localRecv);

      // Inject a few RTP packets.
      for (var seq = 100; seq < 110; seq++) {
        localRecv.deliverRtp(_rtp(ssrc: 0xCAFE01, seq: seq));
      }

      // Allow datagrams to traverse + the worker to publish the
      // relayed receiver.
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (relayedEvents.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      expect(relayedEvents, isNotEmpty,
          reason: 'owner should publish the announced stream');
      final ev = relayedEvents.first;
      expect(ev.sessionId, sid);
      expect(ev.mid, 'remote-v');
      expect(ev.kind, 'video');
      expect(ev.primarySsrc, 0xCAFE01);

      // Snapshot must show the relayed receiver landed.
      final stats = await _getJson(ownerPeer.httpPort, '/stats');
      // After publishing one relayed receiver inside one shard, we
      // expect at least one router. (Peer count is 0 — no real peers
      // have joined; the relay imports a virtual publisher.)
      expect(stats['routers'] as int, greaterThanOrEqualTo(1));
      expect(stats['sessions'] as int, greaterThanOrEqualTo(1));

      // /healthz reports the inbound bridge.
      final h = await _getJson(ownerPeer.httpPort, '/healthz');
      final bridges = (h['cascadeBridges'] as List).cast<Map>();
      expect(
        bridges.any(
          (b) =>
              b['sessionId'] == sid &&
              (b['bridgeId'] as String).startsWith('inbound:'),
        ),
        isTrue,
      );

      // Per-bridge stats inside the worker should now show the inbound
      // RTP packets we injected (allow a poll loop for delivery).
      final shard = owner.sharded.get(sid);
      expect(shard, isNotNull);
      var bridgeStats = await shard!.cascadeBridgeStats();
      final pollDeadline = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(pollDeadline) &&
          (bridgeStats.isEmpty ||
              (bridgeStats.first['inboundRtpPackets'] as int) == 0)) {
        await Future.delayed(const Duration(milliseconds: 50));
        bridgeStats = await shard.cascadeBridgeStats();
      }
      expect(bridgeStats, isNotEmpty);
      final inb =
          bridgeStats.firstWhere((b) => b['relayedReceivers'] as int >= 1);
      expect(inb['inboundRtpPackets'] as int, greaterThanOrEqualTo(1),
          reason: 'owner shard should have received our injected RTP');
      expect(inb['established'], isTrue);
    });
  });
}
