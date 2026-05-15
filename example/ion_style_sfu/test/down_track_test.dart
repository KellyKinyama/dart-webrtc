// Direct DownTrack tests — exercise the production class via its
// rtpSink fast path so we don't need a live SRTP transport. Covers
// the constructor, PLI throttle, layer-switch refusal, synthetic
// loss simulator, RTX bypass, wrong-layer drop, idempotent close,
// and the no-op behavior of writeRtcp / replay when no peer is bound.

import 'dart:math' show Random;
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
  final out = Uint8List(20); // 12B header + 8B payload
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

class _Harness {
  _Harness(this.dt, this.captured, this.rtcpCaptured, this.pc);
  final DownTrack dt;
  final List<Uint8List> captured;
  final List<Uint8List> rtcpCaptured;
  final RTCPeerConnection pc;
}

_Harness _makeTrack({
  Receiver? receiver,
  int rwPrimary = 9001,
  int? rwRtx = 9002,
}) {
  final r = receiver ?? _videoReceiver();
  final pc = RTCPeerConnection(RTCConfiguration(
    defaultVideoCodecs: [Vp8Codec()],
  ));
  final t = pc.addTransceiver(trackOrKind: MediaKind.video);
  final captured = <Uint8List>[];
  final rtcpCaptured = <Uint8List>[];
  final dt = DownTrack(
    id: r.id,
    receiver: r,
    transceiver: t,
    subscriberPc: pc,
    rewrittenPrimarySsrc: rwPrimary,
    rewrittenRtxSsrc: rwRtx,
    rtpSink: captured.add,
    rtcpSink: rtcpCaptured.add,
  );
  return _Harness(dt, captured, rtcpCaptured, pc);
}

void main() {
  group('DownTrack', () {
    test(
        'constructor: simple track, default layer, counters at 0, '
        'rewrite SSRCs as configured', () {
      final h = _makeTrack();
      addTearDown(h.pc.close);
      expect(h.dt.trackType, DownTrackType.simple);
      expect(h.dt.rewrittenPrimarySsrc, 9001);
      expect(h.dt.rewrittenRtxSsrc, 9002);
      expect(h.dt.packetsForwarded, 0);
      expect(h.dt.bytesForwarded, 0);
      expect(h.dt.packetsDroppedWrongLayer, 0);
      expect(h.dt.packetsDroppedSimulator, 0);
      expect(h.dt.layerSwitches, 0);
      expect(h.dt.layerSwitchRejected, 0);
      // Rewriter starts with _resyncOnNext=true (waiting for the first
      // primary on the current layer to baseline its offsets).
      expect(h.dt.switchInFlight, isTrue);
      expect(h.dt.isClosed, isFalse);
      expect(h.dt.currentLayer, h.dt.receiver.stream.defaultLayer.rid);
    });

    test('pliThrottleAllowForTest pure helper', () {
      const gap = Duration(milliseconds: 500);
      expect(pliThrottleAllowForTest(null, DateTime(2024), gap), isTrue);
      final t = DateTime(2024);
      expect(
          pliThrottleAllowForTest(
              t, t.add(const Duration(milliseconds: 100)), gap),
          isFalse);
      expect(pliThrottleAllowForTest(t, t.add(gap), gap), isTrue);
    });

    test('tryConsumePliCredit honors min gap and counts suppressions', () {
      final h = _makeTrack();
      addTearDown(h.pc.close);
      final t0 = DateTime(2024);
      expect(h.dt.tryConsumePliCredit(t0), isTrue);
      expect(h.dt.lastUpstreamPliAt, t0);
      // Within the 500 ms guard.
      expect(
          h.dt.tryConsumePliCredit(
              t0.add(const Duration(milliseconds: 100))),
          isFalse);
      expect(
          h.dt.tryConsumePliCredit(
              t0.add(const Duration(milliseconds: 499))),
          isFalse);
      expect(h.dt.pliRateLimited, 2);
      // Just past the guard.
      expect(
          h.dt.tryConsumePliCredit(
              t0.add(const Duration(milliseconds: 600))),
          isTrue);
    });

    test('setCurrentLayer is a no-op on non-simulcast tracks', () {
      final h = _makeTrack();
      addTearDown(h.pc.close);
      expect(h.dt.trackType, DownTrackType.simple);
      expect(h.dt.setCurrentLayer('q'), isFalse);
      expect(h.dt.setCurrentLayer('h'), isFalse);
      expect(h.dt.setCurrentLayer(''), isFalse);
      expect(h.dt.layerSwitches, 0);
      expect(h.dt.layerSwitchRejected, 0);
    });

    test('writeRtp: happy path forwards primary packets and counts bytes',
        () {
      final h = _makeTrack();
      addTearDown(h.pc.close);
      final layer = h.dt.receiver.layers.first;
      h.dt.writeRtp(layer, false, _vidRtp(seq: 1));
      h.dt.writeRtp(layer, false, _vidRtp(seq: 2));
      h.dt.writeRtp(layer, false, _vidRtp(seq: 3));
      expect(h.captured, hasLength(3));
      expect(h.dt.packetsForwarded, 3);
      expect(h.dt.bytesForwarded, greaterThan(0));
      expect(h.dt.packetsDroppedSimulator, 0);
      expect(h.dt.packetsDroppedWrongLayer, 0);
    });

    test('writeRtp: short packet (<12B) is dropped silently', () {
      final h = _makeTrack();
      addTearDown(h.pc.close);
      final layer = h.dt.receiver.layers.first;
      h.dt.writeRtp(layer, false, Uint8List(8));
      expect(h.captured, isEmpty);
      expect(h.dt.packetsForwarded, 0);
    });

    test('writeRtp: wrong-layer rid increments packetsDroppedWrongLayer', () {
      final h = _makeTrack();
      addTearDown(h.pc.close);
      // A fabricated layer with a rid that doesn't match the rewriter's
      // currentLayer ('' for the non-simulcast default).
      const fake = ProducerLayer(rid: 'q', primarySsrc: 9999, rtxSsrc: null);
      h.dt.writeRtp(fake, false, _vidRtp(seq: 1));
      h.dt.writeRtp(fake, true, _vidRtp(seq: 2));
      expect(h.dt.packetsDroppedWrongLayer, 2);
      expect(h.captured, isEmpty);
    });

    test('writeRtp: dropProbability=1.0 drops every primary; counter reflects',
        () {
      final h = _makeTrack();
      addTearDown(h.pc.close);
      h.dt.dropProbability = 1.0;
      h.dt.lossRng = Random(1);
      final layer = h.dt.receiver.layers.first;
      for (var i = 0; i < 10; i++) {
        h.dt.writeRtp(layer, false, _vidRtp(seq: i));
      }
      expect(h.captured, isEmpty);
      expect(h.dt.packetsDroppedSimulator, 10);
      expect(h.dt.packetsForwarded, 0);
    });

    test('writeRtp: RTX retransmits bypass the loss simulator', () {
      final h = _makeTrack();
      addTearDown(h.pc.close);
      final layer = h.dt.receiver.layers.first;
      // Prime the layer baseline with one primary so the rewriter
      // accepts subsequent RTX (RTX before baseline is dropped).
      h.dt.writeRtp(layer, false, _vidRtp(seq: 1));
      expect(h.dt.packetsForwarded, 1);
      // Now turn on the simulator at 100% — RTX must still flow.
      h.dt.dropProbability = 1.0;
      final captureBefore = h.captured.length;
      h.dt.writeRtp(layer, true, _vidRtp(seq: 2));
      h.dt.writeRtp(layer, true, _vidRtp(seq: 3));
      expect(h.dt.packetsDroppedSimulator, 0);
      // Two RTX packets observed by the sink in addition to the primary.
      expect(h.captured.length - captureBefore, 2);
    });

    test('close() is idempotent and gates further writeRtp/writeRtcp/replay',
        () {
      final h = _makeTrack();
      addTearDown(h.pc.close);
      h.dt.close();
      expect(h.dt.isClosed, isTrue);
      // Idempotent.
      h.dt.close();
      expect(h.dt.isClosed, isTrue);
      // Subsequent writeRtp on a closed track does nothing.
      final layer = h.dt.receiver.layers.first;
      h.dt.writeRtp(layer, false, _vidRtp(seq: 99));
      expect(h.captured, isEmpty);
      // writeRtcp / replay are also gated.
      expect(() => h.dt.writeRtcp(Uint8List(8)), returnsNormally);
      expect(() => h.dt.replay([Uint8List(12)]), returnsNormally);
    });

    test(
        'writeRtcp + replay are no-ops when the subscriber PC has no '
        'active secured peer', () {
      final h = _makeTrack();
      addTearDown(h.pc.close);
      // No bind() was called → subscriberPc.activePeer is null →
      // both methods early-return without throwing.
      expect(h.pc.activePeer, isNull);
      expect(() => h.dt.writeRtcp(Uint8List(8)), returnsNormally);
      expect(() => h.dt.replay([Uint8List(12), Uint8List(12)]),
          returnsNormally);
      // Counters do not move.
      expect(h.dt.packetsForwarded, 0);
    });
  });
}
