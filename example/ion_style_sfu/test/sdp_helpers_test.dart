import 'package:pure_dart_webrtc/signal/sdp_v2.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

const _publisherOffer = '''v=0
o=- 4611732850425945080 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE 0 1
m=audio 9 UDP/TLS/RTP/SAVPF 111
c=IN IP4 0.0.0.0
a=rtcp:9 IN IP4 0.0.0.0
a=ice-ufrag:abcd
a=ice-pwd:efghefghefghefghefgh
a=fingerprint:sha-256 11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22
a=setup:actpass
a=mid:0
a=sendrecv
a=rtpmap:111 opus/48000/2
a=msid:audioStream audioTrack
a=ssrc:1001 cname:user1
a=ssrc:1001 msid:audioStream audioTrack
m=video 9 UDP/TLS/RTP/SAVPF 96 97
c=IN IP4 0.0.0.0
a=rtcp:9 IN IP4 0.0.0.0
a=ice-ufrag:abcd
a=ice-pwd:efghefghefghefghefgh
a=fingerprint:sha-256 11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22
a=setup:actpass
a=mid:1
a=sendrecv
a=rtpmap:96 VP8/90000
a=rtpmap:97 rtx/90000
a=fmtp:97 apt=96
a=msid:videoStream videoTrack
a=ssrc-group:FID 2001 2002
a=ssrc:2001 cname:user1
a=ssrc:2001 msid:videoStream videoTrack
a=ssrc:2002 cname:user1
a=ssrc:2002 msid:videoStream videoTrack
''';

void main() {
  group('parsePublisherOffer', () {
    test('extracts audio + video streams with RTX pairing', () {
      final streams =
          parsePublisherOffer(peerId: 'user1', offerSdp: _publisherOffer);
      expect(streams, hasLength(2));

      final audio = streams.firstWhere((s) => s.kind == 'audio');
      expect(audio.primarySsrc, 1001);
      expect(audio.rtxSsrc, isNull);
      expect(audio.cname, 'user1');
      expect(audio.msidStream, 'audioStream');
      expect(audio.msidTrack, 'audioTrack');

      final video = streams.firstWhere((s) => s.kind == 'video');
      expect(video.primarySsrc, 2001);
      expect(video.rtxSsrc, 2002);
      expect(video.msidStream, 'videoStream');
    });

    test('does NOT emit a stream for the RTX-only SSRC', () {
      final streams =
          parsePublisherOffer(peerId: 'user1', offerSdp: _publisherOffer);
      expect(streams.where((s) => s.primarySsrc == 2002), isEmpty);
    });
  });

  group('augmentSubscriberOffer', () {
    /// A minimal subscriber offer (no a=ssrc lines), as pure_dart_webrtc
    /// generates today.
    String subOffer() => '''v=0
o=- 1 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE 0 1
m=audio 9 UDP/TLS/RTP/SAVPF 111
c=IN IP4 0.0.0.0
a=ice-ufrag:abcd
a=ice-pwd:efghefghefghefghefgh
a=fingerprint:sha-256 11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22
a=setup:actpass
a=mid:0
a=sendonly
a=rtpmap:111 opus/48000/2
m=video 9 UDP/TLS/RTP/SAVPF 96 97
c=IN IP4 0.0.0.0
a=ice-ufrag:abcd
a=ice-pwd:efghefghefghefghefgh
a=fingerprint:sha-256 11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22
a=setup:actpass
a=mid:1
a=sendonly
a=rtpmap:96 VP8/90000
a=rtpmap:97 rtx/90000
a=fmtp:97 apt=96
''';

    test('injects a=ssrc + FID + msid for each producer stream', () {
      final streams =
          parsePublisherOffer(peerId: 'user1', offerSdp: _publisherOffer);
      final allocator = SsrcAllocator();
      final out = augmentSubscriberOffer(
        subscriberId: 'subA',
        allocator: allocator,
        streams: streams,
        offerSdp: subOffer(),
      );

      // Audio stream: rewritten primary SSRC carries cname + msid.
      final rwAudio = allocator.rewrite('subA', 1001);
      expect(out, contains('a=ssrc:$rwAudio cname:user1'));
      expect(out, contains('a=ssrc:$rwAudio msid:audioStream audioTrack'));

      // Video: primary + RTX, both with cname/msid, plus FID group.
      final rwVPrim = allocator.rewrite('subA', 2001);
      final rwVRtx = allocator.rewrite('subA', 2002);
      expect(out, contains('a=ssrc:$rwVPrim cname:user1'));
      expect(out, contains('a=ssrc:$rwVRtx cname:user1'));
      expect(out, contains('a=ssrc-group:FID $rwVPrim $rwVRtx'));
      expect(out, contains('a=msid:videoStream videoTrack'));
    });

    test('writeSdp output is parseable', () {
      final streams =
          parsePublisherOffer(peerId: 'user1', offerSdp: _publisherOffer);
      final out = augmentSubscriberOffer(
        subscriberId: 'subA',
        allocator: SsrcAllocator(),
        streams: streams,
        offerSdp: subOffer(),
      );
      final reparsed = parseSdp(out);
      expect(reparsed.mediaList, hasLength(2));
    });

    test('re-running with same allocator+streams is idempotent in SSRCs', () {
      final streams =
          parsePublisherOffer(peerId: 'user1', offerSdp: _publisherOffer);
      final allocator = SsrcAllocator();
      augmentSubscriberOffer(
        subscriberId: 'subA',
        allocator: allocator,
        streams: streams,
        offerSdp: subOffer(),
      );
      final rwBefore = allocator.rewrite('subA', 2001);
      augmentSubscriberOffer(
        subscriberId: 'subA',
        allocator: allocator,
        streams: streams,
        offerSdp: subOffer(),
      );
      final rwAfter = allocator.rewrite('subA', 2001);
      expect(rwAfter, equals(rwBefore));
    });

    test('returns input unchanged when streams list is empty', () {
      final input = subOffer();
      final out = augmentSubscriberOffer(
        subscriberId: 'subA',
        allocator: SsrcAllocator(),
        streams: const [],
        offerSdp: input,
      );
      expect(out, equals(input));
    });
  });
}
