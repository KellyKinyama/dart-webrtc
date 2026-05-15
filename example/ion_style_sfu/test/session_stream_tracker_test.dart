// Phase B11 — SessionStreamTracker tests. Drives a real Sfu + two
// Peers + publishRelayedStream, attaches a tracker, and asserts the
// snapshot/event surface.

import 'dart:async';
import 'dart:io';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

Sfu _sfu({int rtpBase = 53000}) => Sfu(WebRTCTransportConfig(
      bindAddress: InternetAddress.loopbackIPv4,
      rtpBasePort: rtpBase,
      defaultVideoCodecs: [Vp8Codec()],
      defaultAudioCodecs: [PcmaCodec()],
    ));

ProducerStream _videoStream({int primary = 0xB1A001, int? rtx = 0xB1A002}) =>
    ProducerStream(
      kind: 'video',
      mid: 'v0',
      primarySsrc: primary,
      rtxSsrc: rtx,
      cname: 'cn',
      msidStream: 's',
      msidTrack: 't',
    );

ProducerStream _audioStream({int primary = 0xB1A101}) => ProducerStream(
      kind: 'audio',
      mid: 'a0',
      primarySsrc: primary,
      rtxSsrc: null,
      cname: 'cn',
      msidStream: 's',
      msidTrack: 'a',
    );

void main() {
  group('SessionStreamTracker (Phase B11)', () {
    late Sfu sfu;
    late Peer publisher;
    Peer? subscriber;
    late Session session;
    late SessionStreamTracker tracker;

    setUp(() async {
      sfu = _sfu();
      publisher = Peer(sfu);
      await publisher.join(
        sid: 'b11-room',
        uid: 'pub',
        joinConfig: const PeerJoinConfig(noSubscribe: true),
      );
      session = sfu.getSession('b11-room')!;
      tracker = SessionStreamTracker.attach(session);
    });

    tearDown(() async {
      await tracker.dispose();
      await subscriber?.close();
      await publisher.close();
      await sfu.close();
    });

    test('snapshot is empty before any track publishes', () {
      expect(tracker.snapshot(), isEmpty);
      final js = tracker.snapshotJson();
      expect(js['sessionId'], 'b11-room');
      expect(js['trackCount'], 0);
      expect(js['audioTracks'], 0);
      expect(js['videoTracks'], 0);
      expect(js['tracks'], isEmpty);
    });

    test('publish + subscribe surfaces a TrackInfo and a trackPublished event',
        () async {
      // Buffer events before they fire (broadcast streams drop earlier
      // events on late subscribers).
      final events = <StreamEvent>[];
      final sub = tracker.events.listen(events.add);
      addTearDown(sub.cancel);

      subscriber = Peer(sfu);
      await subscriber!.join(
        sid: 'b11-room',
        uid: 'sub',
        joinConfig: const PeerJoinConfig(noPublish: true),
      );

      final published = publisher.publisher!.router.publishRelayedStream(
        kind: MediaKind.video,
        stream: _videoStream(),
      );
      subscriber!.subscriber!.addReceiver(published);

      // Allow the broadcast controller to drain.
      await Future<void>.delayed(Duration.zero);

      final snap = tracker.snapshot();
      expect(snap, hasLength(1));
      final t = snap.single;
      expect(t.peerId, 'pub');
      expect(t.kind, MediaKind.video);
      expect(t.primarySsrc, 0xB1A001);
      expect(t.rtxSsrc, 0xB1A002);
      expect(t.isSimulcast, isFalse);
      expect(t.layers, hasLength(1));
      expect(t.layers.single.primarySsrc, 0xB1A001);

      final js = tracker.snapshotJson();
      expect(js['trackCount'], 1);
      expect(js['videoTracks'], 1);
      expect(js['audioTracks'], 0);
      final tracks = js['tracks'] as List;
      final tjs = tracks.single as Map;
      expect(tjs['kind'], 'video');
      expect(tjs['simulcast'], isFalse);

      // We expect at least one trackPublished. (peerJoined for `sub`
      // also fires because sub joined after attach.)
      final published1 = events
          .where((e) => e.kind == StreamEventKind.trackPublished)
          .toList();
      expect(published1, hasLength(1));
      expect(published1.single.peerId, 'pub');
      expect(published1.single.track, isNotNull);
      expect(published1.single.track!.primarySsrc, 0xB1A001);

      final joined =
          events.where((e) => e.kind == StreamEventKind.peerJoined).toList();
      expect(joined.map((e) => e.peerId), contains('sub'));

      // toJson round-trip on event itself.
      final ejs = published1.single.toJson();
      expect(ejs['kind'], 'trackPublished');
      expect(ejs['peerId'], 'pub');
      expect((ejs['track'] as Map)['primarySsrc'], 0xB1A001);
    });

    test('peerLeft event fires on Peer.close and chains prior callback',
        () async {
      var priorJoinedCalls = 0;
      var priorLeftCalls = 0;
      // Re-attach with prior callbacks installed.
      await tracker.dispose();
      session.onPeerJoined = (_) => priorJoinedCalls++;
      session.onPeerLeft = (_) => priorLeftCalls++;
      tracker = SessionStreamTracker.attach(session);

      final events = <StreamEvent>[];
      final sub = tracker.events.listen(events.add);
      addTearDown(sub.cancel);

      subscriber = Peer(sfu);
      await subscriber!.join(
        sid: 'b11-room',
        uid: 'sub',
        joinConfig: const PeerJoinConfig(noPublish: true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(priorJoinedCalls, 1);
      expect(
          events.where((e) => e.kind == StreamEventKind.peerJoined).length, 1);

      await subscriber!.close();
      subscriber = null;
      await Future<void>.delayed(Duration.zero);
      expect(priorLeftCalls, 1);
      expect(events.where((e) => e.kind == StreamEventKind.peerLeft).length, 1);
    });

    test('audio + video tracks count separately in snapshotJson', () async {
      subscriber = Peer(sfu);
      await subscriber!.join(
        sid: 'b11-room',
        uid: 'sub',
        joinConfig: const PeerJoinConfig(noPublish: true),
      );

      final v = publisher.publisher!.router.publishRelayedStream(
        kind: MediaKind.video,
        stream: _videoStream(),
      );
      final a = publisher.publisher!.router.publishRelayedStream(
        kind: MediaKind.audio,
        stream: _audioStream(),
      );
      subscriber!.subscriber!.addReceiver(v);
      subscriber!.subscriber!.addReceiver(a);

      final js = tracker.snapshotJson();
      expect(js['trackCount'], 2);
      expect(js['audioTracks'], 1);
      expect(js['videoTracks'], 1);
    });

    test('dispose is idempotent and restores prior callbacks', () async {
      var calls = 0;
      await tracker.dispose();
      session.onTrackPublished = (_, __) => calls++;
      tracker = SessionStreamTracker.attach(session);
      await tracker.dispose();
      await tracker.dispose(); // second dispose is a no-op.

      // After dispose the prior callback is restored — publishing a
      // track must still call it.
      final published = publisher.publisher!.router.publishRelayedStream(
        kind: MediaKind.video,
        stream: _videoStream(primary: 0xB1A201, rtx: 0xB1A202),
      );
      // No subscriber needed — Session.publish runs the callback path.
      expect(published.peerId, 'pub');
      expect(calls, 1);
    });
  });
}
