// Phase B-quick — drive Subscriber's upstream NACK / PLI senders and
// the simulcast register/setPreferredLayer paths through public test
// seams. Covers lines that previously required a publisher with
// active DTLS (now routed through upstreamRtcpSinkForTest).

import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

Sfu _sfu({int rtpBase = 51900}) => Sfu(WebRTCTransportConfig(
      bindAddress: InternetAddress.loopbackIPv4,
      rtpBasePort: rtpBase,
      defaultVideoCodecs: [Vp8Codec()],
      defaultAudioCodecs: [PcmaCodec()],
    ));

ProducerStream _videoStream({int primary = 0xCE0001, int? rtx = 0xCE0002}) =>
    ProducerStream(
      kind: 'video',
      mid: 'v0',
      primarySsrc: primary,
      rtxSsrc: rtx,
      cname: 'cn',
      msidStream: 's',
      msidTrack: 't',
    );

ProducerStream _simulcastStream() => ProducerStream.simulcast(
      kind: 'video',
      mid: 'v0',
      cname: 'cn',
      msidStream: 's',
      msidTrack: 't',
      layers: [
        ProducerLayer(rid: 'q', primarySsrc: 0xDD0001, rtxSsrc: 0xDD0002),
        ProducerLayer(rid: 'h', primarySsrc: 0xDD0003, rtxSsrc: 0xDD0004),
        ProducerLayer(rid: 'f', primarySsrc: 0xDD0005, rtxSsrc: 0xDD0006),
      ],
    );

void main() {
  group('Subscriber upstream feedback seam', () {
    late Sfu sfu;
    late Peer publisher;
    late Peer subscriber;

    setUp(() async {
      sfu = _sfu();
      publisher = Peer(sfu);
      await publisher.join(
        sid: 'sub-up-room',
        uid: 'pub',
        joinConfig: const PeerJoinConfig(noSubscribe: true),
      );
      subscriber = Peer(sfu);
      await subscriber.join(
        sid: 'sub-up-room',
        uid: 'sub',
        joinConfig: const PeerJoinConfig(noPublish: true),
      );
    });

    tearDown(() async {
      await subscriber.close();
      await publisher.close();
      await sfu.close();
    });

    test('NACK from subscriber → upstream NACK routed through seam', () {
      final published = publisher.publisher!.router.publishRelayedStream(
        kind: MediaKind.video,
        stream: _videoStream(),
      );
      subscriber.subscriber!.addReceiver(published);
      final dt = subscriber.subscriber!.downTracks.single;
      final captured = <(DownTrack, Uint8List)>[];
      subscriber.subscriber!.upstreamRtcpSinkForTest =
          (d, pkt) => captured.add((d, pkt));
      // Inbound NACK with all-missing seqs → escalates upstream.
      subscriber.subscriber!.deliverRtcpForTest(
        buildNack(0x1111, dt.rewrittenPrimarySsrc, [10, 11, 12]),
      );
      expect(captured.length, 1);
      expect(captured.single.$1, same(dt));
      // PT=205 (RTPFB), FMT=1 (Generic NACK)
      expect(captured.single.$2[1], 205);
      expect(captured.single.$2[0] & 0x1f, 1);
    });

    test('PLI from subscriber → upstream PLI routed through seam', () {
      final published = publisher.publisher!.router.publishRelayedStream(
        kind: MediaKind.video,
        stream: _videoStream(primary: 0xCE0011, rtx: 0xCE0012),
      );
      subscriber.subscriber!.addReceiver(published);
      final dt = subscriber.subscriber!.downTracks.single;
      final captured = <Uint8List>[];
      subscriber.subscriber!.upstreamRtcpSinkForTest =
          (_, pkt) => captured.add(pkt);
      subscriber.subscriber!.deliverRtcpForTest(
        buildPli(0x1111, dt.rewrittenPrimarySsrc),
      );
      expect(captured.length, 1);
      // PT=206 (PSFB), FMT=1 (PLI)
      expect(captured.single[1], 206);
      expect(captured.single[0] & 0x1f, 1);
    });

    test(
        'simulcast addReceiver registers with layerSelector + setPreferredLayer '
        'fires upstream PLI', () {
      final published = publisher.publisher!.router.publishRelayedStream(
        kind: MediaKind.video,
        stream: _simulcastStream(),
      );
      expect(published.isSimulcast, isTrue);
      final captured = <Uint8List>[];
      subscriber.subscriber!.upstreamRtcpSinkForTest =
          (_, pkt) => captured.add(pkt);
      subscriber.subscriber!.addReceiver(published);
      final dt = subscriber.subscriber!.downTracks.single;
      expect(dt.currentLayer, 'f');
      // Baseline the rewriter so the next setCurrentLayer isn't
      // rejected for switchInFlight. Route through the test seam
      // since the subscriber PC has no active DTLS peer.
      dt.transportSinkForTest = (_, __) {};
      final fLayer = dt.receiver.layers.firstWhere((l) => l.rid == 'f');
      final rtp = Uint8List(20);
      rtp[0] = 0x80;
      rtp[1] = 96;
      rtp[8] = (fLayer.primarySsrc >> 24) & 0xff;
      rtp[9] = (fLayer.primarySsrc >> 16) & 0xff;
      rtp[10] = (fLayer.primarySsrc >> 8) & 0xff;
      rtp[11] = fLayer.primarySsrc & 0xff;
      dt.writeRtp(fLayer, false, rtp);
      expect(dt.switchInFlight, isFalse);
      // Now switching to 'q' is permitted.
      final ok =
          subscriber.subscriber!.setPreferredLayer(published.id, 'q');
      expect(ok, isTrue);
      // Setting the layer fires _sendUpstreamPli → seam captures it.
      expect(captured.length, 1);
      expect(captured.single[1], 206);
    });

    test('setPreferredLayer for unknown receiverId returns false', () {
      final ok = subscriber.subscriber!.setPreferredLayer('no-such', 'q');
      expect(ok, isFalse);
    });
  });
}
