import 'package:pure_dart_webrtc/signal/sdp_v2.dart';
import 'package:test/test.dart';

const _identity = IceDtlsParams(
  iceUfrag: 'abcd',
  icePwd: '0123456789abcdef0123456789ab',
  fingerprintHash:
      '12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF',
);

void main() {
  group('parseSdp / writeSdp (sdp_transform delegation)', () {
    test('parses an m= line with mid + rtpmap', () {
      const text =
          'v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:0\r\na=rtpmap:96 VP8/90000\r\n';
      final m = parseSdp(text);
      expect(m.mediaList, hasLength(1));
      final v = m.mediaList.first;
      expect(v['type'], 'video');
      expect(v['mid'].toString(), '0');
      expect(v.payloadTypeList, [96]);
      expect(v.rtpmapFor(96)?['codec'], 'VP8');
      expect(v.rtpmapFor(96)?['rate'], 90000);
    });

    test('round-trips a session through write -> parse', () {
      final offer = (SdpOfferBuilder(identity: _identity)
            ..addVideo(mid: '0', codecs: [Vp8Codec()]))
          .build();
      final text = writeSdp(offer);
      final reparsed = parseSdp(text);
      expect(reparsed.mediaList.first.payloadTypeList, [96]);
      expect(reparsed.mediaList.first['mid'].toString(), '0');
    });
  });

  group('SdpOfferBuilder', () {
    test('builds VP8+VP9 video and PCMA+PCMU audio with BUNDLE', () {
      final session = (SdpOfferBuilder(identity: _identity)
            ..addVideo(mid: '0', codecs: [Vp8Codec(), Vp9Codec()])
            ..addAudio(mid: '1', codecs: [PcmaCodec(), PcmuCodec()]))
          .build();
      final text = writeSdp(session);

      expect(session.bundleMids, ['0', '1']);
      expect(text, contains('a=group:BUNDLE 0 1'));
      expect(text, contains('a=msid-semantic'));
      expect(text, contains('a=extmap-allow-mixed'));

      // Video.
      expect(text, contains('m=video 9 UDP/TLS/RTP/SAVPF 96 98'));
      expect(text, contains('a=rtpmap:96 VP8/90000'));
      expect(text, contains('a=rtpmap:98 VP9/90000'));
      expect(text, contains('a=fmtp:98 profile-id=0'));
      expect(text, contains('a=rtcp-fb:96 nack pli'));
      expect(text, contains('a=mid:0'));
      expect(text, contains('a=setup:actpass'));
      expect(text, contains('a=rtcp-mux'));
      expect(text, contains('a=ice-ufrag:abcd'));

      // Audio.
      expect(text, contains('m=audio 9 UDP/TLS/RTP/SAVPF 8 0'));
      expect(text, contains('a=rtpmap:8 PCMA/8000/1'));
      expect(text, contains('a=rtpmap:0 PCMU/8000/1'));
      expect(text, contains('a=mid:1'));
    });

    test('emits ICE candidates', () {
      final text = (SdpOfferBuilder(
        identity: _identity,
        candidates: const [
          IceCandidate(foundation: '1', address: '192.0.2.1', port: 7000),
        ],
      )..addVideo(mid: '0', codecs: [Vp8Codec()]))
          .toSdp();
      expect(text,
          contains('a=candidate:1 1 udp 2113937151 192.0.2.1 7000 typ host'));
    });
  });

  group('SdpAnswerBuilder', () {
    test('answers VP8 offer with VP8 and flips actpass -> passive', () {
      // We only implement the DTLS server side, so an actpass offer must
      // be answered with `passive` (the browser becomes the DTLS client).
      final offer = (SdpOfferBuilder(identity: _identity)
            ..addVideo(mid: '0', codecs: [Vp8Codec(), Vp9Codec()]))
          .build();
      final answer = SdpAnswerBuilder(
        offer: offer,
        identity: _identity,
        supportedCodecs: [Vp8Codec()],
      ).build();
      final text = writeSdp(answer);

      expect(text, contains('m=video 9 UDP/TLS/RTP/SAVPF 96'));
      expect(text, isNot(contains('m=video 9 UDP/TLS/RTP/SAVPF 96 98')));
      expect(text, contains('a=rtpmap:96 VP8/90000'));
      expect(text, contains('a=setup:passive'));
      expect(text, contains('a=ice-lite'));
      expect(text, contains('a=mid:0'));
      expect(text, contains('a=group:BUNDLE 0'));
    });

    test('rejects audio when no compatible codec is offered', () {
      final offer = (SdpOfferBuilder(identity: _identity)
            ..addAudio(mid: '0', codecs: [PcmaCodec()]))
          .build();
      final text = SdpAnswerBuilder(
        offer: offer,
        identity: _identity,
        supportedCodecs: [PcmuCodec()],
      ).toSdp();

      expect(text, contains('m=audio 0 '));
      expect(text, isNot(contains('a=group:BUNDLE')));
    });

    test('mirrors offer direction (sendonly -> recvonly)', () {
      final offer = (SdpOfferBuilder(identity: _identity)
            ..addVideo(
                mid: '0',
                codecs: [Vp8Codec()],
                direction: SdpDirection.sendonly))
          .build();
      final text = SdpAnswerBuilder(
        offer: offer,
        identity: _identity,
        supportedCodecs: [Vp8Codec()],
      ).toSdp();
      expect(text, contains('a=recvonly'));
    });

    test('echoes browser-style RTX entry with apt= mapping', () {
      // Hand-built offer that mirrors what Chrome sends: VP8 (PT 96) plus
      // its RTX companion (PT 97 with apt=96).
      const offerSdp = 'v=0\r\n'
          'o=- 1 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96 97\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'a=setup:actpass\r\n'
          'a=ice-ufrag:xx\r\n'
          'a=ice-pwd:0123456789abcdef0123456789ab\r\n'
          'a=fingerprint:sha-256 12:34\r\n'
          'a=rtpmap:96 VP8/90000\r\n'
          'a=rtpmap:97 rtx/90000\r\n'
          'a=fmtp:97 apt=96\r\n';
      final answer = SdpAnswerBuilder(
        offer: parseSdp(offerSdp),
        identity: _identity,
        supportedCodecs: [Vp8Codec()],
      ).toSdp();
      expect(answer, contains('m=video 9 UDP/TLS/RTP/SAVPF 96 97'));
      expect(answer, contains('a=rtpmap:97 rtx/90000'));
      expect(answer, contains('a=fmtp:97 apt=96'));
    });

    test('echoes header extensions on the allowlist with offer IDs', () {
      const offerSdp = 'v=0\r\n'
          'o=- 1 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'a=setup:actpass\r\n'
          'a=ice-ufrag:xx\r\n'
          'a=ice-pwd:0123456789abcdef0123456789ab\r\n'
          'a=fingerprint:sha-256 12:34\r\n'
          'a=rtpmap:96 VP8/90000\r\n'
          'a=extmap:5 urn:ietf:params:rtp-hdrext:sdes:mid\r\n'
          'a=extmap:7 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\r\n'
          'a=extmap:9 urn:ietf:params:rtp-hdrext:nonsense\r\n';
      final answer = SdpAnswerBuilder(
        offer: parseSdp(offerSdp),
        identity: _identity,
        supportedCodecs: [Vp8Codec()],
      ).toSdp();
      // Allowlisted extensions echoed with the same IDs.
      expect(
          answer, contains('a=extmap:5 urn:ietf:params:rtp-hdrext:sdes:mid'));
      expect(
          answer,
          contains(
              'a=extmap:7 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01'));
      // Unknown extension dropped.
      expect(answer, isNot(contains('nonsense')));
    });
  });

  group('SsrcGroup parsing helpers', () {
    test('parses a=ssrc-group:FID into rtxToPrimarySsrc map', () {
      const offerSdp = 'v=0\r\n'
          'o=- 1 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96 97\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'a=rtpmap:96 VP8/90000\r\n'
          'a=rtpmap:97 rtx/90000\r\n'
          'a=fmtp:97 apt=96\r\n'
          'a=ssrc-group:FID 1111 2222\r\n'
          'a=ssrc:1111 cname:foo\r\n'
          'a=ssrc:2222 cname:foo\r\n';
      final m = parseSdp(offerSdp).mediaList.first;
      expect(m.ssrcGroupList, hasLength(1));
      expect(m.ssrcGroupList.first['semantics'], 'FID');
      expect(m.ssrcGroupList.first['ssrcs'], [1111, 2222]);
      expect(m.rtxToPrimarySsrc, {2222: 1111});
      expect(m.ssrcSet, {1111, 2222});
    });
  });
}
