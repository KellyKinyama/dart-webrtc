import 'package:pure_dart_webrtc/signal/sdp_v2.dart';
import 'package:test/test.dart';

const _identity = IceDtlsParams(
  iceUfrag: 'abcd',
  icePwd: '0123456789abcdef0123456789ab',
  fingerprintHash:
      '12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF',
);

void main() {
  group('SdpSession parser', () {
    test('round-trips a minimal offer', () {
      final text =
          'v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:0\r\na=rtpmap:96 VP8/90000\r\n';
      final s = SdpSession.parse(text);
      expect(s.media, hasLength(1));
      expect(s.media[0].type, 'video');
      expect(s.media[0].payloadTypes, [96]);
      expect(s.media[0].mid, '0');
      expect(s.media[0].rtpmapFor(96)?.encoding, 'VP8');
      expect(s.media[0].rtpmapFor(96)?.clockRate, 90000);
    });

    test('extracts BUNDLE group', () {
      final s = SdpSession.parse('v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\ns=-\r\n'
          't=0 0\r\na=group:BUNDLE 0 1\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'a=mid:0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 8\r\na=mid:1\r\n');
      expect(s.bundleMids, ['0', '1']);
    });
  });

  group('SdpOfferBuilder', () {
    test('builds VP8+VP9 video and PCMA+PCMU audio with BUNDLE', () {
      final offer = (SdpOfferBuilder(identity: _identity)
            ..addVideo(mid: '0', codecs: [Vp8Codec(), Vp9Codec()])
            ..addAudio(mid: '1', codecs: [PcmaCodec(), PcmuCodec()]))
          .build();
      final text = offer.write();

      // Session-level wiring.
      expect(text, contains('a=group:BUNDLE 0 1'));
      expect(text, contains('a=msid-semantic:'));
      expect(text, contains('a=extmap-allow-mixed'));

      // Video section.
      expect(text, contains('m=video 9 UDP/TLS/RTP/SAVPF 96 98'));
      expect(text, contains('a=rtpmap:96 VP8/90000'));
      expect(text, contains('a=rtpmap:98 VP9/90000'));
      expect(text, contains('a=fmtp:98 profile-id=0'));
      expect(text, contains('a=rtcp-fb:96 nack pli'));
      expect(text, contains('a=mid:0'));
      expect(text, contains('a=setup:actpass'));
      expect(text, contains('a=rtcp-mux'));
      expect(text, contains('a=ice-ufrag:abcd'));

      // Audio section.
      expect(text, contains('m=audio 9 UDP/TLS/RTP/SAVPF 8 0'));
      expect(text, contains('a=rtpmap:8 PCMA/8000/1'));
      expect(text, contains('a=rtpmap:0 PCMU/8000/1'));
      expect(text, contains('a=mid:1'));
    });

    test('emits ICE candidates', () {
      final offer = (SdpOfferBuilder(
        identity: _identity,
        candidates: const [
          IceCandidate(foundation: '1', address: '192.0.2.1', port: 7000),
        ],
      )..addVideo(mid: '0', codecs: [Vp8Codec()]))
          .build();
      expect(offer.write(),
          contains('a=candidate:1 1 udp 2113937151 192.0.2.1 7000 typ host'));
    });
  });

  group('SdpAnswerBuilder', () {
    test('answers VP8 offer with VP8 and flips actpass -> active', () {
      final offer = (SdpOfferBuilder(identity: _identity)
            ..addVideo(mid: '0', codecs: [Vp8Codec(), Vp9Codec()]))
          .build();
      final answer = SdpAnswerBuilder(
        offer: offer,
        identity: _identity,
        supportedCodecs: [Vp8Codec()],
      ).build();
      final text = answer.write();
      expect(text, contains('m=video 9 UDP/TLS/RTP/SAVPF 96'));
      expect(text, isNot(contains(' 98'))); // VP9 not selected
      expect(text, contains('a=rtpmap:96 VP8/90000'));
      expect(text, contains('a=setup:active'));
      expect(text, contains('a=mid:0'));
      expect(text, contains('a=group:BUNDLE 0'));
    });

    test('rejects audio when no compatible codec is offered', () {
      final offer = (SdpOfferBuilder(identity: _identity)
            ..addAudio(mid: '0', codecs: [PcmaCodec()]))
          .build();
      final answer = SdpAnswerBuilder(
        offer: offer,
        identity: _identity,
        supportedCodecs: [PcmuCodec()],
      ).build();
      final text = answer.write();
      // Rejected sections are emitted with port = 0.
      expect(text, contains('m=audio 0 '));
      // No BUNDLE because the only section was rejected.
      expect(text, isNot(contains('a=group:BUNDLE')));
    });

    test('mirrors offer direction (sendonly -> recvonly)', () {
      final offer = (SdpOfferBuilder(identity: _identity)
            ..addVideo(
                mid: '0',
                codecs: [Vp8Codec()],
                direction: SdpDirection.sendonly))
          .build();
      final answer = SdpAnswerBuilder(
        offer: offer,
        identity: _identity,
        supportedCodecs: [Vp8Codec()],
      ).build();
      expect(answer.write(), contains('a=recvonly'));
    });
  });
}
