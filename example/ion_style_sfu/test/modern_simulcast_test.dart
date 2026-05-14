// Phase 3c — modern-Chrome simulcast (no SIM group, no per-layer
// SSRCs in SDP; routing relies entirely on the RID header extension)
// SDP-parsing tests + Receiver runtime SSRC binding.

import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart' show MediaKind;
import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

const _modernOffer = '''v=0
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
a=rid:f send
a=simulcast:send q;h;f
a=msid:simStream simTrack
''';

/// Build an RTP packet with an SSRC and a one-byte RID extension whose
/// extmap id is [extId] and whose payload is the rid string [rid].
Uint8List _rtpWithRid({
  required int ssrc,
  required int extId,
  required String rid,
}) {
  // One-byte form: header byte = (extId<<4) | (len-1). Append rid bytes
  // and pad to 4-byte multiple.
  final ridBytes = rid.codeUnits;
  final hdr = ((extId & 0x0f) << 4) | ((ridBytes.length - 1) & 0x0f);
  final ext = <int>[hdr, ...ridBytes];
  while (ext.length % 4 != 0) {
    ext.add(0);
  }
  final out = Uint8List(12 + 4 + ext.length + 4);
  out[0] = 0x90; // V=2, X=1
  out[1] = 96;
  out[2] = 0;
  out[3] = 1; // seq=1
  // ts=0
  // ssrc
  out[8] = (ssrc >> 24) & 0xff;
  out[9] = (ssrc >> 16) & 0xff;
  out[10] = (ssrc >> 8) & 0xff;
  out[11] = ssrc & 0xff;
  // ext header
  out[12] = 0xBE;
  out[13] = 0xDE;
  final lenWords = ext.length ~/ 4;
  out[14] = (lenWords >> 8) & 0xff;
  out[15] = lenWords & 0xff;
  out.setAll(16, ext);
  // 4 bytes of opaque payload follow
  return out;
}

void main() {
  group('parsePublisherOffer modern simulcast (no SIM group)', () {
    test('builds one ProducerStream with 3 placeholder layers + ridExtId',
        () {
      final streams =
          parsePublisherOffer(peerId: 'user1', offerSdp: _modernOffer);
      expect(streams, hasLength(1));
      final s = streams.single;
      expect(s.isSimulcast, isTrue);
      expect(s.layers.map((l) => l.rid).toList(), ['q', 'h', 'f']);
      // Placeholder SSRCs until first packet binds them.
      expect(s.layers.every((l) => l.primarySsrc == 0), isTrue);
      expect(s.ridExtId, 4);
      expect(s.repairedRidExtId, 5);
    });
  });

  group('Receiver RID-extension binding', () {
    Receiver build() {
      final stream = parsePublisherOffer(
        peerId: 'user1',
        offerSdp: _modernOffer,
      ).single;
      return Receiver(
        id: 'user1:0',
        peerId: 'user1',
        kind: MediaKind.video,
        codecs: const [],
        stream: stream,
      );
    }

    test('first packet on an unknown SSRC binds it to the matching RID',
        () {
      final r = build();
      final learned = <(int, String, bool)>[];
      r.onSsrcLearned = (ssrc, layer, {required bool isRtx}) {
        learned.add((ssrc, layer.rid, isRtx));
      };
      r.deliverRtp(_rtpWithRid(ssrc: 0xa1a1a1a1, extId: 4, rid: 'q'));
      r.deliverRtp(_rtpWithRid(ssrc: 0xb2b2b2b2, extId: 4, rid: 'h'));
      r.deliverRtp(_rtpWithRid(ssrc: 0xc3c3c3c3, extId: 4, rid: 'f'));
      expect(learned, [
        (0xa1a1a1a1, 'q', false),
        (0xb2b2b2b2, 'h', false),
        (0xc3c3c3c3, 'f', false),
      ]);
    });

    test('subsequent packets on a bound SSRC do not re-fire the hook',
        () {
      final r = build();
      var fires = 0;
      r.onSsrcLearned = (_, __, {required bool isRtx}) => fires++;
      r.deliverRtp(_rtpWithRid(ssrc: 0xdeadbeef, extId: 4, rid: 'h'));
      r.deliverRtp(_rtpWithRid(ssrc: 0xdeadbeef, extId: 4, rid: 'h'));
      r.deliverRtp(_rtpWithRid(ssrc: 0xdeadbeef, extId: 4, rid: 'h'));
      expect(fires, 1);
    });

    test('repaired-RID binds an RTX SSRC', () {
      final r = build();
      final learned = <(int, String, bool)>[];
      r.onSsrcLearned = (ssrc, layer, {required bool isRtx}) {
        learned.add((ssrc, layer.rid, isRtx));
      };
      // Two-byte form not needed; use one-byte for repaired-rid id=5.
      r.deliverRtp(_rtpWithRid(ssrc: 0x99999999, extId: 5, rid: 'f'));
      expect(learned, [(0x99999999, 'f', true)]);
    });

    test('packet with an unknown RID is dropped (no binding, no fanout)',
        () {
      final r = build();
      var fires = 0;
      r.onSsrcLearned = (_, __, {required bool isRtx}) => fires++;
      r.deliverRtp(_rtpWithRid(ssrc: 0x11111111, extId: 4, rid: 'x'));
      expect(fires, 0);
    });
  });
}
