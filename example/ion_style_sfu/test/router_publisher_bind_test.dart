// Coverage tests for the Router publisher-binding flow + RID-discovery
// fan-out, and for Publisher.answerOffer's full SDP exchange. These
// exercise paths that the existing publisher_subscriber_router_test.dart
// stops short of (it only ever calls the high-level Peer.join with
// stub SDPs that throw in answerPublisherOffer).

import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

const _publisherOffer = '''v=0
o=- 1 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE 0 1
m=video 9 UDP/TLS/RTP/SAVPF 96 97
c=IN IP4 0.0.0.0
a=ice-ufrag:abcd
a=ice-pwd:efghefghefghefghefgh
a=fingerprint:sha-256 11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22
a=setup:actpass
a=mid:0
a=sendrecv
a=rtpmap:96 VP8/90000
a=rtpmap:97 rtx/90000
a=fmtp:97 apt=96
a=msid:vstream vtrack
a=ssrc-group:FID 3001 3002
a=ssrc:3001 cname:userP
a=ssrc:3001 msid:vstream vtrack
a=ssrc:3002 cname:userP
a=ssrc:3002 msid:vstream vtrack
m=audio 9 UDP/TLS/RTP/SAVPF 8
c=IN IP4 0.0.0.0
a=ice-ufrag:abcd
a=ice-pwd:efghefghefghefghefgh
a=fingerprint:sha-256 11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22
a=setup:actpass
a=mid:1
a=sendrecv
a=rtpmap:8 PCMA/8000
a=msid:astream atrack
a=ssrc:3010 cname:userP
a=ssrc:3010 msid:astream atrack
''';

const _modernSimulcastOffer = '''v=0
o=- 1 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE 0
m=video 9 UDP/TLS/RTP/SAVPF 96 97
c=IN IP4 0.0.0.0
a=ice-ufrag:abcd
a=ice-pwd:efghefghefghefghefgh
a=fingerprint:sha-256 11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22
a=setup:actpass
a=mid:0
a=sendrecv
a=rtpmap:96 VP8/90000
a=rtpmap:97 rtx/90000
a=fmtp:97 apt=96
a=extmap:4 urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id
a=extmap:5 urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id
a=rid:q send
a=rid:h send
a=simulcast:send q;h
a=msid:simStream simTrack
''';

Sfu _sfu({int rtpBase = 50950}) => Sfu(WebRTCTransportConfig(
      bindAddress: InternetAddress.loopbackIPv4,
      rtpBasePort: rtpBase,
      defaultVideoCodecs: [Vp8Codec()],
      defaultAudioCodecs: [PcmaCodec()],
    ));

Uint8List _rtpWithRid({
  required int ssrc,
  required int extId,
  required String rid,
  int seq = 1,
}) {
  final ridBytes = rid.codeUnits;
  final hdr = ((extId & 0x0f) << 4) | ((ridBytes.length - 1) & 0x0f);
  final ext = <int>[hdr, ...ridBytes];
  while (ext.length % 4 != 0) {
    ext.add(0);
  }
  final out = Uint8List(12 + 4 + ext.length + 4);
  out[0] = 0x90;
  out[1] = 96;
  out[2] = (seq >> 8) & 0xff;
  out[3] = seq & 0xff;
  out[8] = (ssrc >> 24) & 0xff;
  out[9] = (ssrc >> 16) & 0xff;
  out[10] = (ssrc >> 8) & 0xff;
  out[11] = ssrc & 0xff;
  out[12] = 0xBE;
  out[13] = 0xDE;
  final lenWords = ext.length ~/ 4;
  out[14] = (lenWords >> 8) & 0xff;
  out[15] = lenWords & 0xff;
  out.setAll(16, ext);
  return out;
}

void main() {
  group('Router.bindToRemoteOffer', () {
    late Sfu sfu;
    late Session session;

    setUp(() {
      sfu = _sfu(rtpBase: 50950);
      session = sfu.getSession('room-bind');
    });

    tearDown(() async {
      await sfu.close();
    });

    test(
        'parses publisher offer, registers one Receiver per m= line, '
        'and indexes primary + RTX SSRCs', () async {
      final pc = RTCPeerConnection(RTCConfiguration(
        defaultVideoCodecs: [Vp8Codec()],
        defaultAudioCodecs: [PcmaCodec()],
      ));
      addTearDown(pc.close);
      // setRemoteDescription + transceivers must exist before
      // bindToRemoteOffer (it pulls transceivers from the PC).
      await pc.setRemoteDescription(
        RTCSessionDescription(RTCSdpType.offer, _publisherOffer),
      );
      final router = Router(peerId: 'pubX', session: session);
      addTearDown(router.close);

      router.bindToRemoteOffer(pc, _publisherOffer);
      expect(router.receivers, hasLength(2));
      expect(router.receiverForSsrc(3001 /* video primary */), isNotNull);
      expect(router.receiverForSsrc(3002 /* video RTX */), isNotNull);
      expect(router.receiverForSsrc(3010 /* audio primary */), isNotNull);
      // Idempotent: re-running with the same offer is a no-op.
      router.bindToRemoteOffer(pc, _publisherOffer);
      expect(router.receivers, hasLength(2));
    });

    test('empty offer (no streams) is a no-op', () {
      final pc = RTCPeerConnection(RTCConfiguration());
      addTearDown(pc.close);
      final router = Router(peerId: 'pubE', session: session);
      addTearDown(router.close);
      router.bindToRemoteOffer(
          pc,
          'v=0\r\no=- 1 2 IN IP4 0.0.0.0\r\ns=-\r\n'
          't=0 0\r\n');
      expect(router.receivers, isEmpty);
    });

    test('bindToRemoteOffer on a closed router is a no-op', () async {
      final pc = RTCPeerConnection(RTCConfiguration(
        defaultVideoCodecs: [Vp8Codec()],
        defaultAudioCodecs: [PcmaCodec()],
      ));
      addTearDown(pc.close);
      await pc.setRemoteDescription(
        RTCSessionDescription(RTCSdpType.offer, _publisherOffer),
      );
      final router = Router(peerId: 'pubC', session: session);
      router.close();
      router.bindToRemoteOffer(pc, _publisherOffer);
      expect(router.receivers, isEmpty);
    });
  });

  group('Router.routeRtp RID-discovery fallback', () {
    late Sfu sfu;
    late Session session;
    late Router router;
    late RTCPeerConnection pc;

    setUp(() async {
      sfu = _sfu(rtpBase: 51000);
      session = sfu.getSession('room-rid');
      pc = RTCPeerConnection(RTCConfiguration(
        defaultVideoCodecs: [Vp8Codec()],
      ));
      await pc.setRemoteDescription(
        RTCSessionDescription(RTCSdpType.offer, _modernSimulcastOffer),
      );
      router = Router(peerId: 'pubR', session: session);
      router.bindToRemoteOffer(pc, _modernSimulcastOffer);
    });

    tearDown(() async {
      router.close();
      pc.close();
      await sfu.close();
    });

    test('binds an unknown SSRC via the RID extension on first packet', () {
      // Receiver was registered with placeholder SSRC=0 layers.
      // First packet on a brand-new SSRC carries RID 'q' → bind.
      expect(router.receiverForSsrc(0x77770001), isNull);
      router.routeRtp(
        _rtpWithRid(ssrc: 0x77770001, extId: 4, rid: 'q', seq: 1),
      );
      // Receiver should now own that SSRC.
      expect(router.receiverForSsrc(0x77770001), isNotNull);
      // A second packet on the same SSRC takes the fast path
      // (no RID-fallback walk).
      router.routeRtp(
        _rtpWithRid(ssrc: 0x77770001, extId: 4, rid: 'q', seq: 2),
      );
      expect(router.receivers.single.packetsReceived, 2);
    });

    test('packet whose RID does not match any layer is dropped silently', () {
      router.routeRtp(
        _rtpWithRid(ssrc: 0x88880001, extId: 4, rid: 'zzz', seq: 1),
      );
      // No receiver was bound to that SSRC.
      expect(router.receiverForSsrc(0x88880001), isNull);
    });
  });

  group('Publisher.answerOffer (full SDP exchange)', () {
    late Sfu sfu;

    setUp(() {
      sfu = _sfu(rtpBase: 51050);
    });

    tearDown(() async {
      await sfu.close();
    });

    test('returns an SDP answer and populates the router with two receivers',
        () async {
      final p = Peer(sfu);
      await p.join(sid: 'room-ao', uid: 'pubAO');
      final ans = await p.answerPublisherOffer(_publisherOffer);
      expect(ans.type, RTCSdpType.answer);
      expect(ans.sdp, contains('m=video'));
      expect(ans.sdp, contains('m=audio'));
      // Router was populated by bindToRemoteOffer inside answerOffer.
      expect(p.publisher!.router.receivers, hasLength(2));
      expect(p.publisher!.router.receiverForSsrc(3001), isNotNull);
      expect(p.publisher!.router.receiverForSsrc(3010), isNotNull);
      await p.close();
    });
  });
}
