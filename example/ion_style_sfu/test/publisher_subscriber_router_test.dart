// Coverage tests for publisher.dart, subscriber.dart, router.dart.
//
// These exercise the SFU's per-peer state machine end-to-end through
// the public Sfu / Peer / Router surface — no signaling layer
// required. Real UDP transports are bound on loopback (rtpBase shared
// with relay_export_test.dart), but no SDP / DTLS handshake runs:
// we drive the inbound media plumbing directly via Receiver.deliverRtp
// / Router.routeRtp and assert state-machine transitions.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

Sfu _sfu({int rtpBase = 50500}) => Sfu(WebRTCTransportConfig(
      bindAddress: InternetAddress.loopbackIPv4,
      rtpBasePort: rtpBase,
      defaultVideoCodecs: [Vp8Codec()],
      defaultAudioCodecs: [PcmaCodec()],
    ));

ProducerStream _videoStream({
  String mid = 'v0',
  int primary = 0xA10001,
  int? rtx = 0xA10002,
}) =>
    ProducerStream(
      kind: 'video',
      mid: mid,
      primarySsrc: primary,
      rtxSsrc: rtx,
      cname: 'cn',
      msidStream: 's',
      msidTrack: 't',
    );

Uint8List _rtp({
  required int ssrc,
  required int seq,
  int pt = 96,
  int ts = 0,
}) {
  final b = Uint8List(20);
  b[0] = 0x80;
  b[1] = pt & 0x7f;
  b[2] = (seq >> 8) & 0xff;
  b[3] = seq & 0xff;
  b[4] = (ts >> 24) & 0xff;
  b[5] = (ts >> 16) & 0xff;
  b[6] = (ts >> 8) & 0xff;
  b[7] = ts & 0xff;
  b[8] = (ssrc >> 24) & 0xff;
  b[9] = (ssrc >> 16) & 0xff;
  b[10] = (ssrc >> 8) & 0xff;
  b[11] = ssrc & 0xff;
  return b;
}

void main() {
  group('Router', () {
    late Sfu sfu;
    late Session session;
    late Router router;

    setUp(() {
      sfu = _sfu(rtpBase: 50600);
      session = sfu.getSession('room-r');
      router = Router(peerId: 'pub1', session: session);
    });

    tearDown(() async {
      router.close();
      await sfu.close();
    });

    test('publishRelayedStream registers receiver + indexes both SSRCs',
        () {
      final r = router.publishRelayedStream(
        kind: MediaKind.video,
        stream: _videoStream(),
      );
      expect(r.id, 'pub1:v0');
      expect(router.receivers, contains(r));
      expect(router.receiverForSsrc(0xA10001), r);
      expect(router.receiverForSsrc(0xA10002), r);
      expect(router.receiverForSsrc(0xDEADBEEF), isNull);
      expect(router.producerStreams, hasLength(1));
    });

    test('routeRtp ignores closed router and short packets', () {
      router.close();
      // Should not throw.
      router.routeRtp(_rtp(ssrc: 1, seq: 1));
      router.routeRtp(Uint8List(8));
      expect(router.receivers, isEmpty);
    });

    test('routeRtp on unknown SSRC with no RID-discovery receivers is no-op',
        () {
      // No receivers registered yet.
      router.routeRtp(_rtp(ssrc: 0xCAFE, seq: 1));
      // Fresh receiver added afterwards stays empty since the packet
      // was dropped before registration.
      expect(router.receivers, isEmpty);
    });

    test('routeRtp on known SSRC delivers + drives gap detection', () {
      final r = router.publishRelayedStream(
        kind: MediaKind.video,
        stream: _videoStream(primary: 0xB10001, rtx: null),
      );
      final upstream = <Uint8List>[];
      router.onUpstreamFeedback = upstream.add;

      // Sequential — no gap, no NACK.
      router.routeRtp(_rtp(ssrc: 0xB10001, seq: 1));
      router.routeRtp(_rtp(ssrc: 0xB10001, seq: 2));
      expect(upstream, isEmpty);
      expect(r.packetsReceived, 2);

      // Gap of 2 packets (3, 4 missing). Expect upstream NACK.
      router.routeRtp(_rtp(ssrc: 0xB10001, seq: 5));
      expect(upstream, isNotEmpty);
    });

    test('routeRtcp fans out to every receiver', () {
      router.publishRelayedStream(
        kind: MediaKind.video,
        stream: _videoStream(primary: 0xC10001, rtx: null),
      );
      router.publishRelayedStream(
        kind: MediaKind.audio,
        stream: _videoStream(mid: 'a0', primary: 0xC10003, rtx: null),
      );
      // A short / malformed RTCP buffer is forwarded harmlessly to each
      // receiver's deliverRtcp parser.
      router.routeRtcp(Uint8List(4));
      expect(router.receivers, hasLength(2));
    });

    test('removeReceiver clears all SSRC indexes + is idempotent', () {
      final r = router.publishRelayedStream(
        kind: MediaKind.video,
        stream: _videoStream(primary: 0xD10001, rtx: 0xD10002),
      );
      expect(router.receiverForSsrc(0xD10001), r);
      router.removeReceiver(r);
      expect(router.receiverForSsrc(0xD10001), isNull);
      expect(router.receiverForSsrc(0xD10002), isNull);
      // Second remove is a no-op.
      router.removeReceiver(r);
      expect(router.receivers, isEmpty);
    });

    test('close is idempotent and clears everything', () {
      router.publishRelayedStream(
        kind: MediaKind.video,
        stream: _videoStream(primary: 0xE10001, rtx: null),
      );
      router.close();
      router.close();
      expect(router.receivers, isEmpty);
      // Closed router silently ignores further publish + route calls.
      router.routeRtp(_rtp(ssrc: 0xE10001, seq: 1));
      router.routeRtcp(Uint8List(4));
    });
  });

  group('Peer.join — full publisher + subscriber lifecycle', () {
    late Sfu sfu;

    setUp(() {
      sfu = _sfu(rtpBase: 50700);
    });

    tearDown(() async {
      await sfu.close();
    });

    test('default join wires both PCs and registers in session', () async {
      final p = Peer(sfu);
      await p.join(sid: 'room-1', uid: 'alice');
      expect(p.publisher, isNotNull);
      expect(p.subscriber, isNotNull);
      expect(p.session?.peerCount, 1);
      expect(p.session?.getPeer('alice'), p);
      await p.close();
      expect(p.isClosed, isTrue);
      // Session should have evicted itself when the last peer left.
      expect(sfu.sessions, isEmpty);
    });

    test('join with noPublish skips Publisher PC', () async {
      final p = Peer(sfu);
      await p.join(
        sid: 'room-2',
        uid: 'bob',
        joinConfig: const PeerJoinConfig(noPublish: true),
      );
      expect(p.publisher, isNull);
      expect(p.subscriber, isNotNull);
      expect(
        () => p.answerPublisherOffer('v=0\r\n'),
        throwsStateError,
      );
      await p.close();
    });

    test('join with noSubscribe skips Subscriber PC', () async {
      final p = Peer(sfu);
      await p.join(
        sid: 'room-3',
        uid: 'carol',
        joinConfig: const PeerJoinConfig(noSubscribe: true),
      );
      expect(p.publisher, isNotNull);
      expect(p.subscriber, isNull);
      expect(p.createSubscriberOffer, throwsStateError);
      expect(() => p.setSubscriberAnswer('v=0\r\n'), throwsStateError);
      await p.close();
    });

    test('double join throws StateError', () async {
      final p = Peer(sfu);
      await p.join(sid: 'room-4', uid: 'dan');
      await expectLater(
        p.join(sid: 'room-4', uid: 'dan'),
        throwsStateError,
      );
      await p.close();
    });

    test('close is idempotent', () async {
      final p = Peer(sfu);
      await p.join(sid: 'room-5', uid: 'eve');
      await p.close();
      await p.close();
      expect(p.isClosed, isTrue);
    });
  });

  group('Subscriber.addReceiver / removeReceiver', () {
    late Sfu sfu;
    late Peer publisher;
    late Peer subscriber;
    late Receiver published;

    setUp(() async {
      sfu = _sfu(rtpBase: 50800);
      publisher = Peer(sfu);
      await publisher.join(
        sid: 'room-s',
        uid: 'pub',
        joinConfig: const PeerJoinConfig(noSubscribe: true),
      );
      subscriber = Peer(sfu);
      await subscriber.join(
        sid: 'room-s',
        uid: 'sub',
        joinConfig: const PeerJoinConfig(noPublish: true),
      );
      published = publisher.publisher!.router.publishRelayedStream(
        kind: MediaKind.video,
        stream: _videoStream(primary: 0xF10001, rtx: 0xF10002),
      );
    });

    tearDown(() async {
      await subscriber.close();
      await publisher.close();
      await sfu.close();
    });

    test('addReceiver creates a DownTrack + schedules negotiation',
        () async {
      var negotiated = 0;
      subscriber.subscriber!.onNegotiationNeeded = () => negotiated++;
      subscriber.subscriber!.addReceiver(published);
      expect(subscriber.subscriber!.downTracks, hasLength(1));
      // Negotiation is scheduled as a microtask.
      await Future<void>.delayed(Duration.zero);
      expect(negotiated, greaterThanOrEqualTo(1));
    });

    test('addReceiver is idempotent for the same receiver', () {
      subscriber.subscriber!.addReceiver(published);
      subscriber.subscriber!.addReceiver(published);
      expect(subscriber.subscriber!.downTracks, hasLength(1));
    });

    test('noAutoSubscribe makes addReceiver a no-op; addReceiverForced bypasses',
        () async {
      // Spin up a fresh subscriber that joins with noAutoSubscribe so
      // the session.publish call below doesn't auto-attach.
      final lateSub = Peer(sfu);
      addTearDown(lateSub.close);
      await lateSub.join(
        sid: 'room-s',
        uid: 'late',
        joinConfig: const PeerJoinConfig(
          noPublish: true,
          noAutoSubscribe: true,
        ),
      );
      // Re-publish a brand new stream so we hit session.publish ->
      // subscriber.addReceiver while noAutoSubscribe is true.
      final fresh = publisher.publisher!.router.publishRelayedStream(
        kind: MediaKind.video,
        stream: _videoStream(primary: 0xF20001, rtx: null),
      );
      expect(lateSub.subscriber!.downTracks, isEmpty);
      lateSub.subscriber!.addReceiver(fresh);
      expect(lateSub.subscriber!.downTracks, isEmpty);
      lateSub.subscriber!.addReceiverForced(fresh);
      expect(lateSub.subscriber!.downTracks, hasLength(1));
    });

    test('removeReceiver tears the DownTrack down', () {
      subscriber.subscriber!.addReceiver(published);
      expect(subscriber.subscriber!.downTracks, hasLength(1));
      subscriber.subscriber!.removeReceiver(published);
      expect(subscriber.subscriber!.downTracks, isEmpty);
      // Second remove is a no-op.
      subscriber.subscriber!.removeReceiver(published);
    });

    test('setPreferredLayer returns false for unknown receiver id', () {
      expect(
        subscriber.subscriber!.setPreferredLayer('no-such-id', 'q'),
        isFalse,
      );
    });

    test('addReceiver after subscriber.close is a no-op', () async {
      await subscriber.close();
      subscriber.subscriber!.addReceiverForced(published);
      expect(subscriber.subscriber!.downTracks, isEmpty);
    });
  });
}
