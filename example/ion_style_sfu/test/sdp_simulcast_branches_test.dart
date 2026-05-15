// Phase B-quick — exercise sdp_helpers.parsePublisherOffer branches:
// the legacy draft-03 `a=simulcast: send rid=q;h;f` form, the
// 2-member SIM group ([h, f] naming), the 4+ member SIM group (l$i
// naming), and the modern-simulcast path with no a=ssrc lines.

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

const _twoMemberSim = '''v=0
o=- 1 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE 0
m=video 9 UDP/TLS/RTP/SAVPF 96
c=IN IP4 0.0.0.0
a=ice-ufrag:abcd
a=ice-pwd:efghefghefghefghefgh
a=fingerprint:sha-256 11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22
a=setup:actpass
a=mid:0
a=sendrecv
a=rtpmap:96 VP8/90000
a=msid:s t
a=ssrc-group:SIM 1001 1002
a=ssrc:1001 cname:user1
a=ssrc:1001 msid:s t
a=ssrc:1002 cname:user1
a=ssrc:1002 msid:s t
''';

const _fourMemberSim = '''v=0
o=- 1 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE 0
m=video 9 UDP/TLS/RTP/SAVPF 96
c=IN IP4 0.0.0.0
a=ice-ufrag:abcd
a=ice-pwd:efghefghefghefghefgh
a=fingerprint:sha-256 11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22
a=setup:actpass
a=mid:0
a=sendrecv
a=rtpmap:96 VP8/90000
a=msid:s t
a=ssrc-group:SIM 1001 1002 1003 1004
a=ssrc:1001 cname:user1
a=ssrc:1001 msid:s t
a=ssrc:1002 cname:user1
a=ssrc:1002 msid:s t
a=ssrc:1003 cname:user1
a=ssrc:1003 msid:s t
a=ssrc:1004 cname:user1
a=ssrc:1004 msid:s t
''';

const _modernSim03Form = '''v=0
o=- 1 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE 0
m=video 9 UDP/TLS/RTP/SAVPF 96
c=IN IP4 0.0.0.0
a=ice-ufrag:abcd
a=ice-pwd:efghefghefghefghefgh
a=fingerprint:sha-256 11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22
a=setup:actpass
a=mid:0
a=sendrecv
a=rtpmap:96 VP8/90000
a=extmap:4 urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id
a=rid:q send
a=rid:h send
a=rid:f send
a=simulcast: send rid=q;h;f
''';

void main() {
  group('parsePublisherOffer simulcast layer-naming branches', () {
    test('2-member SIM group names layers [h, f]', () {
      final streams =
          parsePublisherOffer(peerId: 'user1', offerSdp: _twoMemberSim);
      expect(streams, hasLength(1));
      final s = streams.single;
      expect(s.isSimulcast, isTrue);
      expect(s.layers.map((l) => l.rid).toList(), ['h', 'f']);
      expect(s.layers[0].primarySsrc, 1001);
      expect(s.layers[1].primarySsrc, 1002);
    });

    test('4-member SIM group names layers [l0, l1, l2, l3]', () {
      final streams =
          parsePublisherOffer(peerId: 'user1', offerSdp: _fourMemberSim);
      expect(streams, hasLength(1));
      final s = streams.single;
      expect(s.layers.map((l) => l.rid).toList(), ['l0', 'l1', 'l2', 'l3']);
    });

    test(
        'legacy draft-03 simulcast form (a=simulcast: send rid=q;h;f) '
        'is recognised as modern simulcast', () {
      final streams =
          parsePublisherOffer(peerId: 'user1', offerSdp: _modernSim03Form);
      expect(streams, hasLength(1));
      final s = streams.single;
      expect(s.isSimulcast, isTrue);
      expect(s.layers.map((l) => l.rid).toList(), ['q', 'h', 'f']);
      // Modern simulcast: SSRCs are placeholder (0) until packets arrive.
      expect(s.layers.every((l) => l.primarySsrc == 0), isTrue);
      expect(s.ridExtId, 4);
      // No a=ssrc → falls back to peerId for cname / msids.
      expect(s.cname, 'user1');
      expect(s.msidStream, 'user1');
    });
  });
}
