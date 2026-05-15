// Coverage tests for DownTrack — simulcast layer switching, the
// SSRC-listener callback, the TWCC-stamp branch in the sink fast
// path, and the rewriter's "dropped" branch (RTX before primary
// baseline). Complements down_track_test.dart, which exercises the
// simple-track sink path; everything here drives the simulcast
// trackType + the per-layer offset machinery + the receiver→
// downtrack SSRC-binding hook.

import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart' show MediaKind;
import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

// ----- helpers -------------------------------------------------------

/// Build a 2-layer SIM-style ProducerStream with concrete SSRCs (no
/// RID extension needed — every layer is pre-bound at construction).
ProducerStream _simStream({int? twccExtId}) => ProducerStream.simulcast(
      kind: 'video',
      mid: '0',
      cname: 'cn',
      msidStream: 'sim',
      msidTrack: 'simT',
      twccExtId: twccExtId,
      layers: const [
        ProducerLayer(rid: 'q', primarySsrc: 0xA10001, rtxSsrc: 0xA10002),
        ProducerLayer(rid: 'h', primarySsrc: 0xA20001, rtxSsrc: 0xA20002),
      ],
    );

Receiver _simReceiver({int? twccExtId}) => Receiver(
      id: 'user1:0',
      peerId: 'user1',
      kind: MediaKind.video,
      codecs: const [],
      stream: _simStream(twccExtId: twccExtId),
    );

Uint8List _vidRtp({
  required int seq,
  int ts = 0,
  required int ssrc,
}) {
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

/// Primary RTP packet carrying a one-byte BEDE extension slot for
/// [twccExtId] (2-byte payload = transport-cc seq, initially zero).
Uint8List _vidRtpWithTwccSlot({
  required int seq,
  required int ssrc,
  required int twccExtId,
}) {
  // Layout: 12-byte fixed header, 4-byte BEDE header (0xBE 0xDE 0x00
  // 0x01), 4-byte ext block ([id<<4|1, 0, 0, 0]), 4-byte payload.
  final out = Uint8List(12 + 4 + 4 + 4);
  out[0] = 0x90; // V=2, X=1
  out[1] = 96;
  out[2] = (seq >> 8) & 0xff;
  out[3] = seq & 0xff;
  out[8] = (ssrc >> 24) & 0xff;
  out[9] = (ssrc >> 16) & 0xff;
  out[10] = (ssrc >> 8) & 0xff;
  out[11] = ssrc & 0xff;
  out[12] = 0xBE;
  out[13] = 0xDE;
  out[14] = 0x00;
  out[15] = 0x01; // 1 ext word follows
  out[16] = ((twccExtId & 0x0f) << 4) | 0x01; // len-1 = 1 → 2-byte data
  // out[17..18] = seq placeholder (TwccStamper writes here)
  // out[19] = padding (0)
  return out;
}

class _Harness {
  _Harness(this.dt, this.captured, this.pc);
  final DownTrack dt;
  final List<Uint8List> captured;
  final RTCPeerConnection pc;
}

_Harness _makeSimTrack({TwccStamper? stamper, int? twccExtId}) {
  final r = _simReceiver(twccExtId: twccExtId);
  final pc = RTCPeerConnection(RTCConfiguration(
    defaultVideoCodecs: [Vp8Codec()],
  ));
  final t = pc.addTransceiver(trackOrKind: MediaKind.video);
  final captured = <Uint8List>[];
  final dt = DownTrack(
    id: r.id,
    receiver: r,
    transceiver: t,
    subscriberPc: pc,
    rewrittenPrimarySsrc: 0xBB0001,
    rewrittenRtxSsrc: 0xBB0002,
    twccStamper: stamper,
    rtpSink: captured.add,
    rtcpSink: (_) {},
  );
  return _Harness(dt, captured, pc);
}

// Modern (RID-based) simulcast offer reused for the SSRC-listener
// test. Layers start with placeholder SSRCs that get bound on the
// first packet carrying the RID extension.
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

Uint8List _rtpWithRid({
  required int ssrc,
  required int extId,
  required String rid,
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
  out[2] = 0;
  out[3] = 1;
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

// ----- tests ---------------------------------------------------------

void main() {
  group('DownTrack simulcast layer switching', () {
    test('trackType is simulcast when receiver carries multiple layers', () {
      final h = _makeSimTrack();
      addTearDown(h.pc.close);
      expect(h.dt.trackType, DownTrackType.simulcast);
      expect(h.dt.currentLayer, 'h'); // last layer is the default
    });

    test('setCurrentLayer to an unknown rid returns false (exists check)', () {
      final h = _makeSimTrack();
      addTearDown(h.pc.close);
      expect(h.dt.setCurrentLayer('zzz'), isFalse);
      expect(h.dt.layerSwitches, 0);
      expect(h.dt.layerSwitchRejected, 0);
    });

    test('setCurrentLayer is rejected while a switch is in flight', () {
      final h = _makeSimTrack();
      addTearDown(h.pc.close);
      // Construction leaves _resyncOnNext=true → switchInFlight=true.
      expect(h.dt.switchInFlight, isTrue);
      expect(h.dt.setCurrentLayer('q'), isFalse);
      expect(h.dt.layerSwitchRejected, 1);
      expect(h.dt.layerSwitches, 0);
    });

    test('setCurrentLayer succeeds once a primary baselines the rewriter', () {
      final h = _makeSimTrack();
      addTearDown(h.pc.close);
      final hLayer = h.dt.receiver.layers.last; // 'h' is current
      // Send one primary on the current layer to clear _resyncOnNext.
      h.dt.writeRtp(hLayer, false, _vidRtp(seq: 1, ssrc: hLayer.primarySsrc));
      expect(h.dt.switchInFlight, isFalse);
      // Now a real switch is allowed.
      expect(h.dt.setCurrentLayer('q'), isTrue);
      expect(h.dt.layerSwitches, 1);
      expect(h.dt.currentLayer, 'q');
      // _resyncOnNext is set again by setCurrentLayer.
      expect(h.dt.switchInFlight, isTrue);
    });

    test('setCurrentLayer to the SAME currentLayer returns false (no-op)', () {
      final h = _makeSimTrack();
      addTearDown(h.pc.close);
      // Baseline first so the in-flight guard doesn't fire.
      final hLayer = h.dt.receiver.layers.last;
      h.dt.writeRtp(hLayer, false, _vidRtp(seq: 1, ssrc: hLayer.primarySsrc));
      expect(h.dt.setCurrentLayer('h'), isFalse);
      expect(h.dt.layerSwitches, 0);
      expect(h.dt.layerSwitchRejected, 0);
    });
  });

  group('DownTrack TWCC stamping in the sink path', () {
    test('packet WITH the twcc ext slot is stamped (counter increments)', () {
      final stamper = TwccStamper();
      final h = _makeSimTrack(stamper: stamper, twccExtId: 3);
      addTearDown(h.pc.close);
      final hLayer = h.dt.receiver.layers.last;
      final pkt = _vidRtpWithTwccSlot(
        seq: 1,
        ssrc: hLayer.primarySsrc,
        twccExtId: 3,
      );
      h.dt.writeRtp(hLayer, false, pkt);
      expect(h.dt.packetsForwarded, 1);
      expect(h.dt.packetsTwccStamped, 1);
      expect(stamper.totalStamped, 1);
    });

    test('packet WITHOUT the twcc ext slot still flows; counter stays 0', () {
      final stamper = TwccStamper();
      final h = _makeSimTrack(stamper: stamper, twccExtId: 3);
      addTearDown(h.pc.close);
      final hLayer = h.dt.receiver.layers.last;
      // No BEDE header at all.
      h.dt.writeRtp(hLayer, false, _vidRtp(seq: 1, ssrc: hLayer.primarySsrc));
      expect(h.dt.packetsForwarded, 1);
      expect(h.dt.packetsTwccStamped, 0);
      expect(stamper.missingExtensionDrops, 1);
    });

    test('RTX packet bypasses the stamper even when extId is configured', () {
      final stamper = TwccStamper();
      final h = _makeSimTrack(stamper: stamper, twccExtId: 3);
      addTearDown(h.pc.close);
      final hLayer = h.dt.receiver.layers.last;
      // Prime the layer baseline with a primary first so the rewriter
      // accepts the RTX (RTX before baseline is dropped).
      h.dt.writeRtp(hLayer, false, _vidRtp(seq: 1, ssrc: hLayer.primarySsrc));
      final priorStamps = stamper.totalStamped;
      h.dt.writeRtp(
        hLayer,
        true,
        _vidRtpWithTwccSlot(
          seq: 2,
          ssrc: hLayer.rtxSsrc!,
          twccExtId: 3,
        ),
      );
      expect(stamper.totalStamped, priorStamps); // unchanged
    });
  });

  group('DownTrack jitter buffer eviction', () {
    test('onEvict releases evicted packet back to the pool', () {
      // Capacity 1 means every new primary evicts the previous.
      final r = _simReceiver();
      final pc = RTCPeerConnection(RTCConfiguration(
        defaultVideoCodecs: [Vp8Codec()],
      ));
      addTearDown(pc.close);
      final t = pc.addTransceiver(trackOrKind: MediaKind.video);
      final dt = DownTrack(
        id: r.id,
        receiver: r,
        transceiver: t,
        subscriberPc: pc,
        rewrittenPrimarySsrc: 0xBB0001,
        rewrittenRtxSsrc: 0xBB0002,
        jitterCapacity: 1,
        rtpSink: (_) {},
      );
      final hLayer = r.layers.last;
      // Two primaries → second evicts the first → onEvict fires.
      dt.writeRtp(hLayer, false, _vidRtp(seq: 1, ssrc: hLayer.primarySsrc));
      dt.writeRtp(hLayer, false, _vidRtp(seq: 2, ssrc: hLayer.primarySsrc));
      expect(dt.packetsForwarded, 2);
    });
  });

  group('DownTrack rewriter "dropped" branch', () {
    test('RTX before any primary baseline is rejected by the rewriter', () {
      final h = _makeSimTrack();
      addTearDown(h.pc.close);
      final hLayer = h.dt.receiver.layers.last;
      // RTX with no prior primary on the current layer → rewriter
      // returns dropped → DownTrack increments packetsDroppedWrongLayer.
      h.dt.writeRtp(
        hLayer,
        true,
        _vidRtp(seq: 1, ssrc: hLayer.rtxSsrc!),
      );
      expect(h.dt.packetsDroppedWrongLayer, 1);
      expect(h.captured, isEmpty);
      expect(h.dt.packetsForwarded, 0);
    });
  });

  group('DownTrack receiver SSRC-listener callback', () {
    test('binding a new primary SSRC via RID extension fans out to DownTrack',
        () {
      final stream =
          parsePublisherOffer(peerId: 'user1', offerSdp: _modernOffer).single;
      final r = Receiver(
        id: 'user1:0',
        peerId: 'user1',
        kind: MediaKind.video,
        codecs: const [],
        stream: stream,
      );
      final pc = RTCPeerConnection(RTCConfiguration(
        defaultVideoCodecs: [Vp8Codec()],
      ));
      addTearDown(pc.close);
      final t = pc.addTransceiver(trackOrKind: MediaKind.video);
      final dt = DownTrack(
        id: r.id,
        receiver: r,
        transceiver: t,
        subscriberPc: pc,
        rewrittenPrimarySsrc: 0xCC0001,
        rewrittenRtxSsrc: 0xCC0002,
        rtpSink: (_) {},
      );
      // Independent listener so we can assert the receiver actually
      // fanned out (and therefore the DownTrack's _onReceiverSsrcLearned
      // ran too — they share the same _ssrcListeners list).
      final fired = <(int, String, bool)>[];
      r.addSsrcListener(
          (s, l, {required isRtx}) => fired.add((s, l.rid, isRtx)));
      r.deliverRtp(_rtpWithRid(ssrc: 0xAAAA0001, extId: 4, rid: 'q'));
      r.deliverRtp(_rtpWithRid(ssrc: 0xBBBB0002, extId: 5, rid: 'q'));
      expect(fired, [
        (0xAAAA0001, 'q', false),
        (0xBBBB0002, 'q', true),
      ]);
      // close removes the DownTrack's listener; subsequent deliveries
      // do not crash.
      dt.close();
      expect(dt.isClosed, isTrue);
      r.deliverRtp(_rtpWithRid(ssrc: 0xCCCC0003, extId: 4, rid: 'h'));
    });
  });
}
