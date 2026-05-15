// Phase B8 — wiring tests for the per-Subscriber LeakyBucketPacer.
// Verifies that every Subscriber owns a pacer, that DownTracks
// created via addReceiver inherit it, that setPacerBitrate routes
// through, that the sink safely no-ops when no DTLS peer is up, and
// that closing the subscriber tears the pacer's Timer down.

import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

Sfu _sfu({int rtpBase = 51400}) => Sfu(WebRTCTransportConfig(
      bindAddress: InternetAddress.loopbackIPv4,
      rtpBasePort: rtpBase,
      defaultVideoCodecs: [Vp8Codec()],
      defaultAudioCodecs: [PcmaCodec()],
    ));

ProducerStream _videoStream({
  String mid = 'v0',
  int primary = 0xCD0001,
  int? rtx = 0xCD0002,
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

void main() {
  group('Subscriber leaky-bucket pacer', () {
    late Sfu sfu;
    late Peer publisher;
    late Peer subscriber;

    setUp(() async {
      sfu = _sfu();
      publisher = Peer(sfu);
      await publisher.join(
        sid: 'pacer-room',
        uid: 'pub',
        joinConfig: const PeerJoinConfig(noSubscribe: true),
      );
      subscriber = Peer(sfu);
      await subscriber.join(
        sid: 'pacer-room',
        uid: 'sub',
        joinConfig: const PeerJoinConfig(noPublish: true),
      );
    });

    tearDown(() async {
      await subscriber.close();
      await publisher.close();
      await sfu.close();
    });

    test('subscriber owns a running pacer with 8 Mbps default target',
        () {
      final pacer = subscriber.subscriber!.pacer;
      expect(pacer, isNotNull);
      expect(pacer.isRunning, isTrue);
      expect(pacer.isClosed, isFalse);
      expect(pacer.targetBitrateBps, 8000000);
    });

    test('setPacerBitrate routes through to the pacer', () {
      subscriber.subscriber!.setPacerBitrate(1500000);
      expect(subscriber.subscriber!.pacer.targetBitrateBps, 1500000);
    });

    test('DownTracks created via addReceiver share the subscriber pacer',
        () {
      final pub = publisher.publisher!.router.publishRelayedStream(
        kind: MediaKind.video,
        stream: _videoStream(),
      );
      subscriber.subscriber!.addReceiver(pub);
      final dt = subscriber.subscriber!.downTracks.single;
      expect(dt.pacer, same(subscriber.subscriber!.pacer));
    });

    test('pacer sink is a no-op when no secured peer is attached', () {
      final pacer = subscriber.subscriber!.pacer;
      // Simulate enqueue from a DownTrack with no DTLS peer up.
      final ok = pacer.enqueue(Uint8List(120), isRtx: false);
      expect(ok, isTrue);
      expect(pacer.queueDepth, 1);
      pacer.drainForTest();
      // Drained, but sink saw activePeer == null and skipped emission.
      expect(pacer.queueDepth, 0);
      // No throw. No packetsSent counter assertion — the pacer counts
      // sink invocations regardless of whether the sink emitted.
      expect(pacer.packetsSent, 1);
    });

    test('closing the subscriber closes the pacer', () async {
      final pacer = subscriber.subscriber!.pacer;
      expect(pacer.isClosed, isFalse);
      await subscriber.close();
      expect(pacer.isClosed, isTrue);
    });
  });
}
