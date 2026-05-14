// Phase 6 — SFU-to-SFU relay tests.

import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

Sfu _sfu() => Sfu(WebRTCTransportConfig(
      bindAddress: InternetAddress.loopbackIPv4,
      rtpBasePort: 40000,
    ));

/// Build a minimal valid RTP packet (12 bytes) with the given SSRC + seq.
Uint8List _rtp({required int ssrc, required int seq, int pt = 96}) {
  final b = Uint8List(12);
  b[0] = 0x80; // V=2
  b[1] = pt & 0x7f;
  b[2] = (seq >> 8) & 0xff;
  b[3] = seq & 0xff;
  // timestamp [4..7] zero
  b[8] = (ssrc >> 24) & 0xff;
  b[9] = (ssrc >> 16) & 0xff;
  b[10] = (ssrc >> 8) & 0xff;
  b[11] = ssrc & 0xff;
  return b;
}

void main() {
  group('RelayStreamDescriptor', () {
    test('JSON round-trip preserves all fields (single layer)', () {
      const d = RelayStreamDescriptor(
        mid: '0',
        kind: 'video',
        layers: [RelayLayerDescriptor(rid: '', primarySsrc: 1, rtxSsrc: 2)],
        cname: 'cn',
        msidStream: 's',
        msidTrack: 't',
        audioLevelExtId: 3,
      );
      final j = d.toJson();
      final back = RelayStreamDescriptor.fromJson(j);
      expect(back.mid, '0');
      expect(back.kind, 'video');
      expect(back.layers, hasLength(1));
      expect(back.layers.first.primarySsrc, 1);
      expect(back.layers.first.rtxSsrc, 2);
      expect(back.cname, 'cn');
      expect(back.audioLevelExtId, 3);
      expect(back.isSimulcast, isFalse);
    });

    test('JSON round-trip preserves simulcast layers + RID ext ids', () {
      const d = RelayStreamDescriptor(
        mid: '1',
        kind: 'video',
        layers: [
          RelayLayerDescriptor(rid: 'q', primarySsrc: 10, rtxSsrc: 11),
          RelayLayerDescriptor(rid: 'h', primarySsrc: 20, rtxSsrc: 21),
          RelayLayerDescriptor(rid: 'f', primarySsrc: 30, rtxSsrc: 31),
        ],
        cname: 'cn',
        msidStream: 's',
        msidTrack: 't',
        ridExtId: 4,
        repairedRidExtId: 5,
      );
      final back = RelayStreamDescriptor.fromJson(d.toJson());
      expect(back.isSimulcast, isTrue);
      expect(back.layers.map((l) => l.rid), ['q', 'h', 'f']);
      expect(back.layers.map((l) => l.primarySsrc), [10, 20, 30]);
      expect(back.ridExtId, 4);
      expect(back.repairedRidExtId, 5);
    });

    test('toProducerStream produces single-layer stream when rid empty', () {
      const d = RelayStreamDescriptor(
        mid: '0',
        kind: 'audio',
        layers: [RelayLayerDescriptor(rid: '', primarySsrc: 7)],
        cname: 'c',
        msidStream: 's',
        msidTrack: 't',
      );
      final ps = d.toProducerStream();
      expect(ps.isSimulcast, isFalse);
      expect(ps.primarySsrc, 7);
      expect(ps.rtxSsrc, isNull);
    });

    test('toProducerStream produces simulcast stream when multi-layer', () {
      const d = RelayStreamDescriptor(
        mid: '0',
        kind: 'video',
        layers: [
          RelayLayerDescriptor(rid: 'q', primarySsrc: 1),
          RelayLayerDescriptor(rid: 'f', primarySsrc: 2),
        ],
        cname: 'c',
        msidStream: 's',
        msidTrack: 't',
        ridExtId: 4,
      );
      final ps = d.toProducerStream();
      expect(ps.isSimulcast, isTrue);
      expect(ps.layers, hasLength(2));
      expect(ps.ridExtId, 4);
    });
  });

  group('InMemoryRelayPipe', () {
    test('control envelopes round-trip both directions', () {
      final pipe = InMemoryRelayPipe();
      final fromA = <Map<String, Object?>>[];
      final fromB = <Map<String, Object?>>[];
      pipe.b.onControl = fromA.add;
      pipe.a.onControl = fromB.add;
      pipe.a.sendControl({'hello': 1});
      pipe.b.sendControl({'world': 2});
      expect(fromA, [
        {'hello': 1}
      ]);
      expect(fromB, [
        {'world': 2}
      ]);
    });

    test('RTP + RTCP packets round-trip', () {
      final pipe = InMemoryRelayPipe();
      final rtpAtB = <Uint8List>[];
      final rtcpAtA = <Uint8List>[];
      pipe.b.onRtp = rtpAtB.add;
      pipe.a.onRtcp = rtcpAtA.add;
      pipe.a.sendRtp(Uint8List.fromList([1, 2, 3]));
      pipe.b.sendRtcp(Uint8List.fromList([9, 9]));
      expect(rtpAtB, hasLength(1));
      expect(rtpAtB.first, [1, 2, 3]);
      expect(rtcpAtA, hasLength(1));
      expect(rtcpAtA.first, [9, 9]);
    });

    test('after close, traffic is dropped', () async {
      final pipe = InMemoryRelayPipe();
      var got = 0;
      pipe.b.onRtp = (_) => got++;
      await pipe.a.close();
      pipe.a.sendRtp(Uint8List(1));
      expect(got, 0);
    });
  });

  group('RelayPeer', () {
    test('hello handshake establishes both sides', () {
      final sfuA = _sfu();
      final sfuB = _sfu();
      final sessA = sfuA.getSession('room');
      final sessB = sfuB.getSession('room');
      final pipe = InMemoryRelayPipe();

      final origin = RelayPeer.over(
        remoteId: 'origin',
        session: sessA,
        transport: pipe.a,
      );
      final downstream = RelayPeer.over(
        remoteId: 'downstream',
        session: sessB,
        transport: pipe.b,
      );
      origin.start(); // sends 'hello'
      expect(downstream.established, isTrue);
      expect(origin.established, isTrue);
    });

    test('announce publishes a Receiver into the downstream session', () {
      final sfu = _sfu();
      final sess = sfu.getSession('room');
      final pipe = InMemoryRelayPipe();

      RelayPeer.over(
        remoteId: 'origin',
        session: _sfu().getSession('x'),
        transport: pipe.a,
      );
      final downstream = RelayPeer.over(
        remoteId: 'origin',
        session: sess,
        transport: pipe.b,
      );

      Receiver? notified;
      downstream.onRelayedStream = (r) => notified = r;

      // Origin side sends an announce envelope directly.
      pipe.a.sendControl({
        'type': RelayMsgType.announce,
        'stream': const RelayStreamDescriptor(
          mid: 'v1',
          kind: 'video',
          layers: [
            RelayLayerDescriptor(rid: '', primarySsrc: 0xAAAA, rtxSsrc: 0xBBBB),
          ],
          cname: 'cn',
          msidStream: 's',
          msidTrack: 't',
        ).toJson(),
      });

      expect(notified, isNotNull);
      expect(notified!.id, 'origin:v1');
      expect(downstream.relayedReceivers, hasLength(1));
      expect(downstream.router.receiverForSsrc(0xAAAA), notified);
      expect(downstream.router.receiverForSsrc(0xBBBB), notified);
    });

    test('announce + RTP packet routes through the downstream router', () {
      final sfu = _sfu();
      final sess = sfu.getSession('room');
      final pipe = InMemoryRelayPipe();

      RelayPeer.over(
        remoteId: 'origin',
        session: _sfu().getSession('x'),
        transport: pipe.a,
      );
      final downstream = RelayPeer.over(
        remoteId: 'origin',
        session: sess,
        transport: pipe.b,
      );

      pipe.a.sendControl({
        'type': RelayMsgType.announce,
        'stream': const RelayStreamDescriptor(
          mid: 'v1',
          kind: 'video',
          layers: [RelayLayerDescriptor(rid: '', primarySsrc: 42)],
          cname: 'c',
          msidStream: 's',
          msidTrack: 't',
        ).toJson(),
      });

      // Send 3 RTP packets with a gap: seqs 1, 2, 5.
      pipe.a.sendRtp(_rtp(ssrc: 42, seq: 1));
      pipe.a.sendRtp(_rtp(ssrc: 42, seq: 2));

      // No upstream feedback yet (no gap).
      final upstream = <Uint8List>[];
      pipe.a.onRtcp = upstream.add;
      pipe.a.sendRtp(_rtp(ssrc: 42, seq: 5));

      // Gap detected → router emits NACK → relay ships it back to origin.
      expect(upstream, isNotEmpty, reason: 'expected upstream NACK after gap');
      // First byte: V=2 P=0 FMT=1 → 0x81. Second byte PT=205.
      expect(upstream.first[1], 205);
      expect(downstream.router.receiverForSsrc(42), isNotNull);
    });

    test('remove tears the relayed receiver down', () {
      final sfu = _sfu();
      final sess = sfu.getSession('room');
      final pipe = InMemoryRelayPipe();
      RelayPeer.over(
        remoteId: 'origin',
        session: _sfu().getSession('x'),
        transport: pipe.a,
      );
      final downstream = RelayPeer.over(
        remoteId: 'origin',
        session: sess,
        transport: pipe.b,
      );

      pipe.a.sendControl({
        'type': RelayMsgType.announce,
        'stream': const RelayStreamDescriptor(
          mid: 'v1',
          kind: 'video',
          layers: [RelayLayerDescriptor(rid: '', primarySsrc: 9)],
          cname: 'c',
          msidStream: 's',
          msidTrack: 't',
        ).toJson(),
      });
      expect(downstream.relayedReceivers, hasLength(1));

      pipe.a.sendControl({'type': RelayMsgType.remove, 'mid': 'v1'});
      expect(downstream.relayedReceivers, isEmpty);
      expect(downstream.router.receiverForSsrc(9), isNull);
    });

    test('duplicate announce for same mid is a no-op', () {
      final sfu = _sfu();
      final sess = sfu.getSession('room');
      final pipe = InMemoryRelayPipe();
      RelayPeer.over(
        remoteId: 'origin',
        session: _sfu().getSession('x'),
        transport: pipe.a,
      );
      final downstream = RelayPeer.over(
        remoteId: 'origin',
        session: sess,
        transport: pipe.b,
      );

      var fired = 0;
      downstream.onRelayedStream = (_) => fired++;
      final desc = const RelayStreamDescriptor(
        mid: 'v1',
        kind: 'video',
        layers: [RelayLayerDescriptor(rid: '', primarySsrc: 1)],
        cname: 'c',
        msidStream: 's',
        msidTrack: 't',
      ).toJson();
      pipe.a.sendControl({'type': RelayMsgType.announce, 'stream': desc});
      pipe.a.sendControl({'type': RelayMsgType.announce, 'stream': desc});
      expect(fired, 1);
      expect(downstream.relayedReceivers, hasLength(1));
    });

    test('bye message closes the downstream peer', () async {
      final sfu = _sfu();
      final sess = sfu.getSession('room');
      final pipe = InMemoryRelayPipe();
      RelayPeer.over(
        remoteId: 'origin',
        session: _sfu().getSession('x'),
        transport: pipe.a,
      );
      final downstream = RelayPeer.over(
        remoteId: 'origin',
        session: sess,
        transport: pipe.b,
      );
      pipe.a.sendControl({'type': RelayMsgType.bye});
      expect(downstream.isClosed, isTrue);
    });

    test('origin side surfaces inbound RTCP via onUpstreamRtcp', () {
      final pipe = InMemoryRelayPipe();
      final origin = RelayPeer.over(
        remoteId: 'origin',
        session: _sfu().getSession('x'),
        transport: pipe.a,
      );
      final got = <Uint8List>[];
      origin.onUpstreamRtcp = got.add;
      pipe.b.sendRtcp(Uint8List.fromList([0x81, 205, 0, 0]));
      expect(got, hasLength(1));
      expect(got.first[1], 205);
    });
  });
}
