// Phase 16 — subscriber-side cascade churn.
//
// When a cascade bridge dies (remote `bye`, idle reaper, or local
// teardown), every subscriber in the shard's session that was
// pulling from that bridge's relayed receivers must drop the
// corresponding DownTrack and get a fresh subscriber offer so the
// client renegotiates the now-removed track. Prior to Phase 16
// `RelayPeer.close()` only called `router.close()`, which closed the
// underlying receivers but never iterated `session.peers` to fire
// `subscriber.removeReceiver(...)` -> `_scheduleNegotiation()`, so
// subscribers ended up with stale DownTracks and no SDP update.
//
// This test boots an owner cluster, joins a real subscriber peer
// inside the owner's session shard, brings up a fake remote SFU
// that announces a relayed stream (-> first sub offer), then closes
// the relay (-> second sub offer if Phase 16 is wired correctly).

import 'dart:async';
import 'dart:io';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart' show MediaKind;
import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

String _sessionOwnedBy(String peerId, List<ClusterPeer> peers) {
  final loc = RoomLocator(selfId: peerId, peers: peers);
  for (var i = 0; i < 1000; i++) {
    final sid = 'p16-$i';
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
  group('Subscriber-side cascade churn (Phase 16)', () {
    test(
        'closing an inbound bridge removes the relayed track and triggers a '
        'subscriber renegotiation offer', () async {
      final ownerPeer = ClusterPeer.parse('127.0.0.1:18401:18402');
      final fakePeer = ClusterPeer.parse('127.0.0.1:18403:18404');
      final owner = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: ownerPeer.httpPort,
        rtpBase: 57000,
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
        rtpBasePort: 57300,
      ));
      addTearDown(() async {
        await owner.close();
        await fakeHub.close();
        await fakeSfu.close();
      });

      final sid = _sessionOwnedBy(ownerPeer.id, [ownerPeer, fakePeer]);

      // Materialise the owner shard and join a real subscriber peer
      // (no publisher — we only care about its renegotiation events).
      final shard = await owner.sharded.getOrCreate(sid);
      await shard.join('sub1', noPublish: true);

      // Capture every SubscriberOfferEvent for `sub1`.
      final subOffers = <SubscriberOfferEvent>[];
      final subListener = shard.events.listen((e) {
        if (e is SubscriberOfferEvent && e.uid == 'sub1') subOffers.add(e);
      });
      addTearDown(subListener.cancel);

      // Bring up the fake remote, cascade-hello, and announce a
      // relayed stream.
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

      final stream = ProducerStream(
        kind: 'video',
        mid: 'churn-v',
        primarySsrc: 0xC0FFEE,
        rtxSsrc: null,
        cname: 'cn',
        msidStream: 's',
        msidTrack: 't',
      );
      final localRecv = relay.router.publishRelayedStream(
        kind: MediaKind.video,
        stream: stream,
      );
      relay.exportReceiver(localRecv);

      // First sub offer: the relayed receiver was added to sub1's
      // subscriber, scheduling renegotiation.
      await _waitFor(() => subOffers.isNotEmpty);
      final offersAfterAdd = subOffers.length;

      // Now close the relay (bye on the wire, then onClosed). Phase 16
      // says this must drive `subscriber.removeReceiver(...)`, which
      // schedules a *second* renegotiation on sub1.
      await relay.close();

      await _waitFor(
        () => subOffers.length > offersAfterAdd,
        timeout: const Duration(seconds: 4),
      );
      expect(
        subOffers.length,
        greaterThan(offersAfterAdd),
        reason: 'closing the bridge must trigger a follow-up sub offer',
      );

      // The owner's shard should also no longer expose the bridge's
      // relayed receiver in its bridge stats (Phase 14 teardown path).
      await _waitFor(() async {
        final stats = await shard.cascadeBridgeStats();
        return stats.every((s) => (s['relayedReceivers'] as int) == 0);
      });
    });
  });
}
