import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

const _simulcastOffer = '''v=0
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
a=msid:simStream simTrack
a=ssrc-group:SIM 3001 3002 3003
a=ssrc-group:FID 3001 3011
a=ssrc-group:FID 3002 3012
a=ssrc-group:FID 3003 3013
a=ssrc:3001 cname:user1
a=ssrc:3001 msid:simStream simTrack
a=ssrc:3011 cname:user1
a=ssrc:3011 msid:simStream simTrack
a=ssrc:3002 cname:user1
a=ssrc:3002 msid:simStream simTrack
a=ssrc:3012 cname:user1
a=ssrc:3012 msid:simStream simTrack
a=ssrc:3003 cname:user1
a=ssrc:3003 msid:simStream simTrack
a=ssrc:3013 cname:user1
a=ssrc:3013 msid:simStream simTrack
''';

void main() {
  group('parsePublisherOffer SIM groups', () {
    test('emits a single ProducerStream with three layers q/h/f', () {
      final streams =
          parsePublisherOffer(peerId: 'user1', offerSdp: _simulcastOffer);
      expect(streams, hasLength(1));
      final s = streams.single;
      expect(s.isSimulcast, isTrue);
      expect(s.layers, hasLength(3));
      expect(s.layers.map((l) => l.rid).toList(), ['q', 'h', 'f']);
    });

    test('layers carry their own primary + RTX SSRCs from FID groups', () {
      final s = parsePublisherOffer(peerId: 'user1', offerSdp: _simulcastOffer)
          .single;
      expect(s.layers[0].primarySsrc, 3001);
      expect(s.layers[0].rtxSsrc, 3011);
      expect(s.layers[1].primarySsrc, 3002);
      expect(s.layers[1].rtxSsrc, 3012);
      expect(s.layers[2].primarySsrc, 3003);
      expect(s.layers[2].rtxSsrc, 3013);
    });

    test('default-layer accessors point at the highest layer', () {
      final s = parsePublisherOffer(peerId: 'user1', offerSdp: _simulcastOffer)
          .single;
      expect(s.primarySsrc, 3003);
      expect(s.rtxSsrc, 3013);
      expect(s.defaultLayer.rid, 'f');
    });

    test('allPrimarySsrcs / allRtxSsrcs enumerate every layer', () {
      final s = parsePublisherOffer(peerId: 'user1', offerSdp: _simulcastOffer)
          .single;
      expect(s.allPrimarySsrcs.toList(), [3001, 3002, 3003]);
      expect(s.allRtxSsrcs.toList(), [3011, 3012, 3013]);
    });

    test('msid is preserved across layers', () {
      final s = parsePublisherOffer(peerId: 'user1', offerSdp: _simulcastOffer)
          .single;
      expect(s.msidStream, 'simStream');
      expect(s.msidTrack, 'simTrack');
      expect(s.cname, 'user1');
    });
  });

  group('ProducerStream factories', () {
    test('single-layer factory yields layers.length == 1, not simulcast', () {
      final s = ProducerStream(
        kind: 'video',
        mid: '0',
        primarySsrc: 4001,
        rtxSsrc: 4002,
        cname: 'c',
        msidStream: 's',
        msidTrack: 't',
      );
      expect(s.isSimulcast, isFalse);
      expect(s.layers, hasLength(1));
      expect(s.layers.single.rid, '');
      expect(s.primarySsrc, 4001);
      expect(s.rtxSsrc, 4002);
    });

    test('simulcast factory exposes its layers immutably', () {
      final s = ProducerStream.simulcast(
        kind: 'video',
        mid: '0',
        layers: [
          const ProducerLayer(rid: 'q', primarySsrc: 1, rtxSsrc: null),
          const ProducerLayer(rid: 'f', primarySsrc: 2, rtxSsrc: null),
        ],
        cname: 'c',
        msidStream: 's',
        msidTrack: 't',
      );
      expect(s.isSimulcast, isTrue);
      expect(
          () => s.layers.add(
                const ProducerLayer(rid: 'x', primarySsrc: 3, rtxSsrc: null),
              ),
          throwsUnsupportedError);
    });
  });
}
