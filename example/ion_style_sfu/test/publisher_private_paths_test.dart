// Phase B-quick — exercise Publisher's private inbound-media and
// upstream-feedback paths via the test seams + the public
// router.onUpstreamFeedback callback. Covers _sendUpstream's
// no-active-peer short-circuit, _onPublisherRtp's first-packet +
// every-500th log/route, and _onPublisherRtcp's first-packet log.

import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

Sfu _sfu({int rtpBase = 51600}) => Sfu(WebRTCTransportConfig(
      bindAddress: InternetAddress.loopbackIPv4,
      rtpBasePort: rtpBase,
      defaultVideoCodecs: [Vp8Codec()],
      defaultAudioCodecs: [PcmaCodec()],
    ));

Uint8List _rtp({required int ssrc, required int seq}) {
  final b = Uint8List(20);
  b[0] = 0x80;
  b[1] = 96;
  b[2] = (seq >> 8) & 0xff;
  b[3] = seq & 0xff;
  b[8] = (ssrc >> 24) & 0xff;
  b[9] = (ssrc >> 16) & 0xff;
  b[10] = (ssrc >> 8) & 0xff;
  b[11] = ssrc & 0xff;
  return b;
}

void main() {
  group('Publisher private paths', () {
    late Sfu sfu;
    late Peer peer;

    setUp(() async {
      sfu = _sfu();
      peer = Peer(sfu);
      await peer.join(
        sid: 'pub-priv-room',
        uid: 'pub',
        joinConfig: const PeerJoinConfig(noSubscribe: true),
      );
    });

    tearDown(() async {
      await peer.close();
      await sfu.close();
    });

    test('_sendUpstream is a no-op when no active secured peer', () {
      // router.onUpstreamFeedback was wired to Publisher._sendUpstream
      // in the constructor. With no DTLS peer up, activePeer is null
      // and the helper short-circuits before hitting transport.sendRtcp.
      final pub = peer.publisher!;
      // Must not throw; exercises lines 50-53 of publisher.dart.
      pub.router.onUpstreamFeedback
          ?.call(Uint8List.fromList([0x80, 0xcd, 0, 1]));
    });

    test('deliverRtpForTest increments _rtpCount and routes to the router', () {
      final pub = peer.publisher!;
      pub.deliverRtpForTest(_rtp(ssrc: 0xAA0001, seq: 1));
      // No public counter; we just assert no throw + a second packet works.
      pub.deliverRtpForTest(_rtp(ssrc: 0xAA0001, seq: 2));
    });

    test('deliverRtpForTest tolerates short packets (length < 12)', () {
      final pub = peer.publisher!;
      // Goes through the `len < 12` ssrc=0 branch on the first-packet log.
      pub.deliverRtpForTest(Uint8List(8));
    });

    test('deliverRtpForTest fires the every-500th log without throwing', () {
      final pub = peer.publisher!;
      for (var i = 1; i <= 500; i++) {
        pub.deliverRtpForTest(_rtp(ssrc: 0xAA0002, seq: i));
      }
    });

    test('deliverRtcpForTest increments _rtcpCount and routes', () {
      final pub = peer.publisher!;
      // RTCP type 200 (SR), len 0 (one 32-bit word total). Just enough
      // bytes to satisfy the router's rtcpHeader pickup.
      final sr = Uint8List.fromList([0x80, 200, 0, 0, 0, 0, 0, 0]);
      pub.deliverRtcpForTest(sr);
      pub.deliverRtcpForTest(sr);
    });

    test('deliverRtpForTest is a no-op after publisher close', () async {
      final pub = peer.publisher!;
      await peer.close();
      // Should silently return; no exception.
      pub.deliverRtpForTest(_rtp(ssrc: 0xAA0003, seq: 1));
      pub.deliverRtcpForTest(Uint8List.fromList([0x80, 200, 0, 0, 0, 0, 0, 0]));
    });
  });
}
