// Phase B-quick — exercise DownTrack's real-transport branch logic
// via the transportSinkForTest seam (without standing up a live DTLS
// peer). Also covers the rtcpSink wiring in writeRtcp and the pacer
// engagement path inside writeRtp/replay.

import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

const _videoOffer = '''v=0
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
a=msid:videoStream videoTrack
a=ssrc-group:FID 2001 2002
a=ssrc:2001 cname:user1
a=ssrc:2001 msid:videoStream videoTrack
a=ssrc:2002 cname:user1
a=ssrc:2002 msid:videoStream videoTrack
''';

Receiver _videoReceiver() {
  final s = parsePublisherOffer(peerId: 'user1', offerSdp: _videoOffer).single;
  return Receiver(
    id: 'user1:0',
    peerId: 'user1',
    kind: MediaKind.video,
    codecs: const [],
    stream: s,
  );
}

Uint8List _vidRtp({required int seq, int ts = 0, int ssrc = 2001}) {
  final out = Uint8List(20);
  out[0] = 0x80;
  out[1] = 96;
  out[2] = (seq >> 8) & 0xff;
  out[3] = seq & 0xff;
  out[4] = (ts >> 24) & 0xff;
  out[5] = (ts >> 16) & 0xff;
  out[6] = (ts >> 8) & 0xff;
  out[7] = ts & 0xff;
  out[8] = (ssrc >> 24) & 0xff;
  out[9] = (ssrc >> 16) & 0xff;
  out[10] = (ssrc >> 8) & 0xff;
  out[11] = ssrc & 0xff;
  return out;
}

Uint8List _rtxRtp(
    {required int seq, int ts = 0, int ssrc = 2002, int osn = 1}) {
  final out = Uint8List(22); // 12B header + 2B OSN + 8B payload
  out[0] = 0x80;
  out[1] = 97;
  out[2] = (seq >> 8) & 0xff;
  out[3] = seq & 0xff;
  out[4] = (ts >> 24) & 0xff;
  out[5] = (ts >> 16) & 0xff;
  out[6] = (ts >> 8) & 0xff;
  out[7] = ts & 0xff;
  out[8] = (ssrc >> 24) & 0xff;
  out[9] = (ssrc >> 16) & 0xff;
  out[10] = (ssrc >> 8) & 0xff;
  out[11] = ssrc & 0xff;
  out[12] = (osn >> 8) & 0xff;
  out[13] = osn & 0xff;
  return out;
}

DownTrack _track({
  void Function(Uint8List, bool)? sink,
  void Function(Uint8List)? rtcpSink,
  LeakyBucketPacer? pacer,
  int rwPrimary = 9001,
  int? rwRtx = 9002,
}) {
  final r = _videoReceiver();
  final pc = RTCPeerConnection(RTCConfiguration(
    defaultVideoCodecs: [Vp8Codec()],
  ));
  final t = pc.addTransceiver(trackOrKind: MediaKind.video);
  final dt = DownTrack(
    id: r.id,
    receiver: r,
    transceiver: t,
    subscriberPc: pc,
    rewrittenPrimarySsrc: rwPrimary,
    rewrittenRtxSsrc: rwRtx,
    rtcpSink: rtcpSink,
    pacer: pacer,
  );
  dt.transportSinkForTest = sink;
  addTearDown(pc.close);
  return dt;
}

void main() {
  group('DownTrack — transportSinkForTest seam (real branch)', () {
    test('writeRtp routes through testSend, bumps counters, releases RTX', () {
      final captured = <(Uint8List, bool)>[];
      final dt = _track(sink: (out, isRtx) => captured.add((out, isRtx)));
      final layer = dt.receiver.layers.first;
      // Two primaries (first one is the keyframe baseline) + one RTX.
      dt.writeRtp(layer, false, _vidRtp(seq: 100));
      dt.writeRtp(layer, false, _vidRtp(seq: 101, ts: 3000));
      dt.writeRtp(layer, true, _rtxRtp(seq: 50, osn: 100));
      expect(captured.length, 3);
      expect(captured[0].$2, isFalse);
      expect(captured[1].$2, isFalse);
      expect(captured[2].$2, isTrue);
      expect(dt.packetsForwarded, 3);
      expect(dt.bytesForwarded,
          captured.map((c) => c.$1.length).fold<int>(0, (a, b) => a + b));
    });

    test('writeRtp wrong-layer drop bypasses egress', () {
      final captured = <(Uint8List, bool)>[];
      final dt = _track(sink: (o, r) => captured.add((o, r)));
      // Synthesize a fake layer whose rid != currentLayer.
      final wrong = ProducerLayer(
        rid: 'no-such',
        primarySsrc: 9999,
        rtxSsrc: null,
      );
      dt.writeRtp(wrong, false, _vidRtp(seq: 1));
      expect(captured, isEmpty);
      expect(dt.packetsDroppedWrongLayer, 1);
    });

    test('writeRtp engages pacer when both pacer and seam are set', () {
      final captured = <Uint8List>[];
      final pacer = LeakyBucketPacer(
        targetBitrateBps: 1000000,
        sink: (rtp, {required bool isRtx}) => captured.add(rtp),
      );
      addTearDown(pacer.close);
      final dt = _track(
        sink: (_, __) => fail('seam should be bypassed when pacer is set'),
        pacer: pacer,
      );
      final layer = dt.receiver.layers.first;
      dt.writeRtp(layer, false, _vidRtp(seq: 200));
      // Drain: leaky bucket releases on each tick. Force a manual drain.
      pacer.drainForTest();
      expect(captured.length, 1);
      expect(dt.packetsForwarded, 1);
    });

    test('replay routes through testSend', () {
      final captured = <Uint8List>[];
      final dt = _track(sink: (out, _) => captured.add(out));
      dt.replay([Uint8List(12), Uint8List(12), Uint8List(12)]);
      expect(captured.length, 3);
    });

    test('replay engages pacer over the seam', () {
      final paced = <Uint8List>[];
      final pacer = LeakyBucketPacer(
        targetBitrateBps: 1000000,
        sink: (rtp, {required bool isRtx}) => paced.add(rtp),
      );
      addTearDown(pacer.close);
      final dt = _track(
        sink: (_, __) => fail('seam should be bypassed when pacer is set'),
        pacer: pacer,
      );
      dt.replay([Uint8List(12), Uint8List(12)]);
      pacer.drainForTest();
      expect(paced.length, 2);
    });

    test('writeRtcp routes through rtcpSink, bypasses peer guard', () {
      final captured = <Uint8List>[];
      final dt = _track(rtcpSink: captured.add);
      // Minimal RR (PT=201) header — rewriter passes unknown SSRCs
      // through unchanged, which is fine for this dispatch test.
      final rr = Uint8List(8);
      rr[0] = 0x80;
      rr[1] = 201;
      rr[2] = 0;
      rr[3] = 1;
      dt.writeRtcp(rr);
      expect(captured.length, 1);
    });
  });
}
