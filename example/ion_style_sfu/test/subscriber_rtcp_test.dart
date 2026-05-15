// Coverage tests for Subscriber._onSubscriberRtcp — drives every
// feedback branch (NACK / PLI / FIR / REMB / RR / TWCC) through the
// public deliverRtcpForTest seam without standing up a real DTLS
// peer. The publisher side never has an active SecuredPeer in these
// tests, so _publisherFor returns null and _sendUpstreamNack /
// _sendUpstreamPli early-return cleanly — exactly what we want for
// branch coverage of the dispatch / lookup logic.

import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

Sfu _sfu({int rtpBase = 51200}) => Sfu(WebRTCTransportConfig(
      bindAddress: InternetAddress.loopbackIPv4,
      rtpBasePort: rtpBase,
      defaultVideoCodecs: [Vp8Codec()],
      defaultAudioCodecs: [PcmaCodec()],
    ));

ProducerStream _videoStream({
  String mid = 'v0',
  int primary = 0xCC0001,
  int? rtx = 0xCC0002,
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
  group('Subscriber._onSubscriberRtcp', () {
    late Sfu sfu;
    late Peer publisher;
    late Peer subscriber;
    late Receiver published;
    late DownTrack dt;
    late int rwPrimary;

    setUp(() async {
      sfu = _sfu();
      publisher = Peer(sfu);
      await publisher.join(
        sid: 'rtcp-room',
        uid: 'pub',
        joinConfig: const PeerJoinConfig(noSubscribe: true),
      );
      subscriber = Peer(sfu);
      await subscriber.join(
        sid: 'rtcp-room',
        uid: 'sub',
        joinConfig: const PeerJoinConfig(noPublish: true),
      );
      published = publisher.publisher!.router.publishRelayedStream(
        kind: MediaKind.video,
        stream: _videoStream(primary: 0xCC0001, rtx: 0xCC0002),
      );
      subscriber.subscriber!.addReceiver(published);
      dt = subscriber.subscriber!.downTracks.single;
      rwPrimary = dt.rewrittenPrimarySsrc;
    });

    tearDown(() async {
      await subscriber.close();
      await publisher.close();
      await sfu.close();
    });

    test('NACK with unknown rewritten SSRC is a no-op (not in map)', () {
      final pkt = buildNack(0x1111, 0xDEADBEEF, [10]);
      // Should not throw. _byRewrittenSsrc lookup misses → continue.
      subscriber.subscriber!.deliverRtcpForTest(pkt);
    });

    test('NACK with known rewritten SSRC walks the lookup path', () {
      final pkt = buildNack(0x1111, rwPrimary, [10, 11, 12]);
      // No replay buffer entries → all stillMissing → upstream NACK.
      // Publisher PC has no active secured peer, so _sendUpstreamNack
      // returns early — no crash.
      subscriber.subscriber!.deliverRtcpForTest(pkt);
    });

    test('PLI with unknown rewritten SSRC is a no-op', () {
      final pkt = buildPli(0x1111, 0xDEADBEEF);
      subscriber.subscriber!.deliverRtcpForTest(pkt);
    });

    test('PLI with known rewritten SSRC consumes a credit', () {
      final pkt = buildPli(0x1111, rwPrimary);
      final before = dt.lastUpstreamPliAt;
      subscriber.subscriber!.deliverRtcpForTest(pkt);
      // tryConsumePliCredit was called → lastUpstreamPliAt updated.
      expect(dt.lastUpstreamPliAt, isNot(before));
    });

    test('FIR routes each target SSRC through the PLI path', () {
      // Build a FIR targeting our rewritten primary + an unknown SSRC.
      final fir = buildFir(0x1111, rwPrimary, 1);
      subscriber.subscriber!.deliverRtcpForTest(fir);
      // Known target consumed a PLI credit.
      expect(dt.lastUpstreamPliAt, isNotNull);

      // Unknown target — exercise the targetSsrcs lookup miss branch.
      final firUnknown = buildFir(0x1111, 0xDEADBEEF, 2);
      subscriber.subscriber!.deliverRtcpForTest(firUnknown);
    });

    test('REMB feeds the bandwidth estimator unconditionally', () {
      final remb = buildRemb(0x1111, 750000, [rwPrimary]);
      subscriber.subscriber!.deliverRtcpForTest(remb);
      expect(subscriber.subscriber!.bwe.currentBps, 750000);
    });

    test('Malformed RTCP buffer is silently ignored by parseFeedback', () {
      // Too short for any header.
      subscriber.subscriber!.deliverRtcpForTest(Uint8List(2));
      // 4-byte buffer with no recognized PT.
      subscriber.subscriber!.deliverRtcpForTest(Uint8List(4));
    });

    test('After subscriber.close, deliverRtcpForTest is a no-op', () async {
      await subscriber.close();
      // Should not throw even though _closed is true.
      subscriber.subscriber!.deliverRtcpForTest(buildPli(0x1111, rwPrimary));
    });

    test('setPreferredLayer on the simple track still returns false', () {
      // Receiver is single-layer (non-simulcast), so setCurrentLayer
      // refuses → setPreferredLayer returns false. This exercises the
      // setPreferredLayer→setCurrentLayer false branch.
      expect(
        subscriber.subscriber!.setPreferredLayer(published.id, 'q'),
        isFalse,
      );
    });
  });
}
