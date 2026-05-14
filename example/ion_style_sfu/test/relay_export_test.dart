// Phase 6b — RelayPeer.exportReceiver end-to-end tests.
//
// These wire an origin-side relay peer that taps a local [Receiver]
// (created directly via [Router.publishRelayedStream] for test
// convenience) and verify that announce + RTP + RTCP all flow to a
// downstream peer, and that [RelayExport.stop] cleanly tears the
// export down.

import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart' show MediaKind;
import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

Sfu _sfu() => Sfu(WebRTCTransportConfig(
      bindAddress: InternetAddress.loopbackIPv4,
      rtpBasePort: 50000,
    ));

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

void main() {
  group('RelayPeer.exportReceiver', () {
    test('announce + RTP flows from origin to downstream', () {
      final originSfu = _sfu();
      final downSfu = _sfu();
      final originSess = originSfu.getSession('room');
      final downSess = downSfu.getSession('room');
      final pipe = InMemoryRelayPipe();

      // Origin-side relay peer (carries our exports outward).
      final origin = RelayPeer.over(
        remoteId: 'originSfu',
        session: originSess,
        transport: pipe.a,
      );
      // Downstream relay peer (publishes the relayed receiver locally).
      final downstream = RelayPeer.over(
        remoteId: 'originSfu',
        session: downSess,
        transport: pipe.b,
      );

      // Build a real local Receiver on the origin side via the relay's
      // own router (simulates a publisher track we want to export).
      final localStream = ProducerStream(
        kind: 'video',
        mid: 'v1',
        primarySsrc: 0xA1B2C3,
        rtxSsrc: null,
        cname: 'cn',
        msidStream: 's',
        msidTrack: 't',
      );
      final localReceiver = origin.router.publishRelayedStream(
        kind: MediaKind.video,
        stream: localStream,
      );

      Receiver? announced;
      downstream.onRelayedStream = (r) => announced = r;

      final exp = origin.exportReceiver(localReceiver);
      expect(exp.isStopped, isFalse);
      expect(origin.exports, hasLength(1));
      expect(announced, isNotNull);
      expect(announced!.id, 'originSfu:v1');
      expect(downstream.router.receiverForSsrc(0xA1B2C3), announced);

      // Feed an RTP packet into the origin-side receiver. The tap
      // should ship it over the pipe to the downstream router.
      var routed = 0;
      announced!.addRtpTap((_) => routed++);
      localReceiver.deliverRtp(_rtp(ssrc: 0xA1B2C3, seq: 100));
      expect(routed, 1);
    });

    test('stop() removes taps and sends unannounce', () {
      final originSfu = _sfu();
      final downSfu = _sfu();
      final pipe = InMemoryRelayPipe();
      final origin = RelayPeer.over(
        remoteId: 'o',
        session: originSfu.getSession('r'),
        transport: pipe.a,
      );
      final downstream = RelayPeer.over(
        remoteId: 'o',
        session: downSfu.getSession('r'),
        transport: pipe.b,
      );

      final stream = ProducerStream(
        kind: 'video', mid: 'v1',
        primarySsrc: 5, rtxSsrc: null,
        cname: 'c', msidStream: 's', msidTrack: 't',
      );
      final local = origin.router.publishRelayedStream(
        kind: MediaKind.video, stream: stream,
      );
      final exp = origin.exportReceiver(local);
      expect(downstream.relayedReceivers, hasLength(1));

      exp.stop();
      expect(exp.isStopped, isTrue);
      expect(origin.exports, isEmpty);
      expect(downstream.relayedReceivers, isEmpty);

      // Subsequent RTP must not crash and must not reach downstream.
      var seen = 0;
      pipe.b.onRtp = (_) => seen++;
      local.deliverRtp(_rtp(ssrc: 5, seq: 1));
      expect(seen, 0);
    });

    test('export forwards simulcast layers preserving rids + ext ids',
        () {
      final originSfu = _sfu();
      final downSfu = _sfu();
      final pipe = InMemoryRelayPipe();
      final origin = RelayPeer.over(
        remoteId: 'o',
        session: originSfu.getSession('r'),
        transport: pipe.a,
      );
      final downstream = RelayPeer.over(
        remoteId: 'o',
        session: downSfu.getSession('r'),
        transport: pipe.b,
      );

      final stream = ProducerStream.simulcast(
        kind: 'video', mid: 'v1',
        layers: const [
          ProducerLayer(rid: 'q', primarySsrc: 100, rtxSsrc: 101),
          ProducerLayer(rid: 'h', primarySsrc: 200, rtxSsrc: 201),
          ProducerLayer(rid: 'f', primarySsrc: 300, rtxSsrc: 301),
        ],
        cname: 'c', msidStream: 's', msidTrack: 't',
        ridExtId: 4, repairedRidExtId: 5,
      );
      final local = origin.router.publishRelayedStream(
        kind: MediaKind.video, stream: stream,
      );
      origin.exportReceiver(local);

      final r = downstream.relayedReceivers.single;
      expect(r.isSimulcast, isTrue);
      expect(r.stream.layers.map((l) => l.rid), ['q', 'h', 'f']);
      expect(r.stream.ridExtId, 4);
      expect(r.stream.repairedRidExtId, 5);
      // All three primary SSRCs index correctly.
      expect(downstream.router.receiverForSsrc(100), r);
      expect(downstream.router.receiverForSsrc(200), r);
      expect(downstream.router.receiverForSsrc(300), r);
      // RTX SSRCs also.
      expect(downstream.router.receiverForSsrc(101), r);
    });

    test('closing the origin RelayPeer stops all exports', () async {
      final originSfu = _sfu();
      final downSfu = _sfu();
      final pipe = InMemoryRelayPipe();
      final origin = RelayPeer.over(
        remoteId: 'o',
        session: originSfu.getSession('r'),
        transport: pipe.a,
      );
      final downstream = RelayPeer.over(
        remoteId: 'o',
        session: downSfu.getSession('r'),
        transport: pipe.b,
      );

      final stream = ProducerStream(
        kind: 'audio', mid: 'a1',
        primarySsrc: 7, rtxSsrc: null,
        cname: 'c', msidStream: 's', msidTrack: 't',
      );
      final local = origin.router.publishRelayedStream(
        kind: MediaKind.audio, stream: stream,
      );
      final exp = origin.exportReceiver(local);
      expect(exp.isStopped, isFalse);

      await origin.close();
      expect(exp.isStopped, isTrue);
      expect(downstream.isClosed, isTrue);
    });

    test('RTCP from the origin Receiver flows to downstream', () {
      final originSfu = _sfu();
      final downSfu = _sfu();
      final pipe = InMemoryRelayPipe();
      final origin = RelayPeer.over(
        remoteId: 'o',
        session: originSfu.getSession('r'),
        transport: pipe.a,
      );
      final downstream = RelayPeer.over(
        remoteId: 'o',
        session: downSfu.getSession('r'),
        transport: pipe.b,
      );
      final stream = ProducerStream(
        kind: 'video', mid: 'v1',
        primarySsrc: 9, rtxSsrc: null,
        cname: 'c', msidStream: 's', msidTrack: 't',
      );
      final local = origin.router.publishRelayedStream(
        kind: MediaKind.video, stream: stream,
      );
      origin.exportReceiver(local);

      // Downstream side surfaces inbound RTCP (NACK/PLI-style) via
      // onUpstreamRtcp on the *origin* — but since the origin is the
      // sender here, we instead observe via the downstream router's
      // receiver delivering it. Use a tap on the downstream Receiver.
      final got = <Uint8List>[];
      downstream.relayedReceivers.single.addRtcpTap(got.add);

      local.deliverRtcp(Uint8List.fromList([0x80, 200, 0, 1, 9, 9, 9, 9]));
      expect(got, hasLength(1));
      expect(got.first[1], 200);
    });
  });
}
