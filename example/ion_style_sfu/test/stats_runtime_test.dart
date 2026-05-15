// Phase B-quick — exercise the snapshotSfu DownTrack iteration block
// (lines 185-209) which only fires when the SFU has at least one
// receiver with attached DownTracks. Builds a real Sfu with one
// publisher + one subscriber and verifies the per-track stats fields
// are populated end-to-end.

import 'dart:io';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

Sfu _sfu({int rtpBase = 52000}) => Sfu(WebRTCTransportConfig(
      bindAddress: InternetAddress.loopbackIPv4,
      rtpBasePort: rtpBase,
      defaultVideoCodecs: [Vp8Codec()],
      defaultAudioCodecs: [PcmaCodec()],
    ));

ProducerStream _videoStream({int primary = 0xDA0001, int? rtx = 0xDA0002}) =>
    ProducerStream(
      kind: 'video',
      mid: 'v0',
      primarySsrc: primary,
      rtxSsrc: rtx,
      cname: 'cn',
      msidStream: 's',
      msidTrack: 't',
    );

void main() {
  group('snapshotSfu DownTrack iteration', () {
    late Sfu sfu;
    late Peer publisher;
    late Peer subscriber;

    setUp(() async {
      sfu = _sfu();
      publisher = Peer(sfu);
      await publisher.join(
        sid: 'stats-room',
        uid: 'pub',
        joinConfig: const PeerJoinConfig(noSubscribe: true),
      );
      subscriber = Peer(sfu);
      await subscriber.join(
        sid: 'stats-room',
        uid: 'sub',
        joinConfig: const PeerJoinConfig(noPublish: true),
      );
    });

    tearDown(() async {
      await subscriber.close();
      await publisher.close();
      await sfu.close();
    });

    test('snapshotSfu populates DownTrackStats for each subscriber track', () {
      final published = publisher.publisher!.router.publishRelayedStream(
        kind: MediaKind.video,
        stream: _videoStream(),
      );
      subscriber.subscriber!.addReceiver(published);

      final snap = snapshotSfu(sfu);
      expect(snap.sessions, 1);
      expect(snap.peers, 2);
      expect(snap.routers, greaterThanOrEqualTo(1));
      expect(snap.downTracks, 1);
      expect(snap.totalBytesForwarded, 0);
      expect(snap.totalPacketsForwarded, 0);
      expect(snap.tracks, hasLength(1));

      final t = snap.tracks.single;
      expect(t.sessionId, 'stats-room');
      expect(t.peerId, 'pub');
      expect(t.kind, 'video');
      expect(t.trackType, 'simple');
      expect(t.packetsForwarded, 0);
      expect(t.bytesForwarded, 0);
      expect(t.packetsDroppedWrongLayer, 0);
      expect(t.packetsTwccStamped, 0);
      expect(t.publisherPacketsReceived, 0);
      expect(t.publisherBytesReceived, 0);
      expect(t.publisherRtxPacketsReceived, 0);
      expect(t.publisherPacketsLost, 0);
      expect(t.packetsDroppedSimulator, 0);

      // BWE entry exists for the subscriber.
      expect(snap.subscriberBwe, hasLength(1));
      expect(snap.subscriberBwe.single.peerId, 'sub');

      // Render Prometheus to exercise the per-track formatting too.
      final body = formatPrometheus(snap);
      expect(body, contains('ionsfu_track_packets_forwarded_total'));
      expect(body, contains('session="stats-room"'));
      expect(body, contains('peer="pub"'));
      expect(body, contains('kind="video"'));
      expect(body, contains('ionsfu_publisher_packets_received_total'));
    });

    test('snapshotSfu reflects two subscribers on the same publisher',
        () async {
      final published = publisher.publisher!.router.publishRelayedStream(
        kind: MediaKind.video,
        stream: _videoStream(primary: 0xDA0011, rtx: 0xDA0012),
      );
      subscriber.subscriber!.addReceiver(published);

      final sub2 = Peer(sfu);
      await sub2.join(
        sid: 'stats-room',
        uid: 'sub2',
        joinConfig: const PeerJoinConfig(noPublish: true),
      );
      addTearDown(sub2.close);
      sub2.subscriber!.addReceiver(published);

      final snap = snapshotSfu(sfu);
      expect(snap.peers, 3);
      expect(snap.downTracks, 2);
      expect(snap.tracks, hasLength(2));
      // Both tracks share the same publisher peerId.
      expect(snap.tracks.every((t) => t.peerId == 'pub'), isTrue);
      // Both BWE entries present.
      expect(snap.subscriberBwe, hasLength(2));
    });
  });
}
