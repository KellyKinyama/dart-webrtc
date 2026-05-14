import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/src/cluster/udp_relay_transport.dart';
import 'package:test/test.dart';

void main() {
  group('UdpRelayHub', () {
    test('plain (no-secret) round-trip: control + RTP + RTCP', () async {
      final a = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: 0,
      );
      final b = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: 0,
      );
      addTearDown(() async {
        await a.close();
        await b.close();
      });

      final aToB = a.endpointTo(InternetAddress.loopbackIPv4, b.port);
      final bToA = b.endpointTo(InternetAddress.loopbackIPv4, a.port);

      final ctlOnB = Completer<Map<String, Object?>>();
      final rtpOnB = Completer<Uint8List>();
      final rtcpOnA = Completer<Uint8List>();

      bToA.onControl = (msg) => ctlOnB.complete(msg);
      bToA.onRtp = (pkt) => rtpOnB.complete(pkt);
      aToB.onRtcp = (pkt) => rtcpOnA.complete(pkt);

      aToB.sendControl({'hello': 'b', 'n': 7});
      aToB.sendRtp(Uint8List.fromList(
          [0x80, 0x60, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 0xab, 0xcd]));
      bToA.sendRtcp(Uint8List.fromList([0x81, 0xc8, 0, 1, 0, 0, 0, 0]));

      final ctl = await ctlOnB.future.timeout(const Duration(seconds: 2));
      expect(ctl['hello'], 'b');
      expect(ctl['n'], 7);

      final rtp = await rtpOnB.future.timeout(const Duration(seconds: 2));
      expect(rtp.length, 14);
      expect(rtp[0], 0x80);

      final rtcp = await rtcpOnA.future.timeout(const Duration(seconds: 2));
      expect(rtcp[0], 0x81);
    });

    test('HMAC-secured round-trip rejects mismatched secret', () async {
      final goodA = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: 0,
        secret: 'shared-secret',
      );
      final goodB = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: 0,
        secret: 'shared-secret',
      );
      final wrongC = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: 0,
        secret: 'other-secret',
      );
      addTearDown(() async {
        await goodA.close();
        await goodB.close();
        await wrongC.close();
      });

      final ctlOnB = Completer<Map<String, Object?>>();
      goodB.endpointTo(InternetAddress.loopbackIPv4, goodA.port).onControl =
          (msg) => ctlOnB.complete(msg);
      goodA
          .endpointTo(InternetAddress.loopbackIPv4, goodB.port)
          .sendControl({'k': 'v'});
      final ctl = await ctlOnB.future.timeout(const Duration(seconds: 2));
      expect(ctl['k'], 'v');

      final ctlOnBFromWrong = <Map<String, Object?>>[];
      goodB.endpointTo(InternetAddress.loopbackIPv4, wrongC.port).onControl =
          ctlOnBFromWrong.add;
      // wrongC sends to goodB with the wrong HMAC; goodB's hub will
      // drop the frame. We allow ample time and assert nothing arrives.
      wrongC
          .endpointTo(InternetAddress.loopbackIPv4, goodB.port)
          .sendControl({'k': 'forged'});
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(ctlOnBFromWrong, isEmpty);
    });

    test('onUnknownPeer fires for previously unseen sender', () async {
      final a = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: 0,
      );
      final b = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: 0,
      );
      addTearDown(() async {
        await a.close();
        await b.close();
      });

      final seen = Completer<int>();
      a.onUnknownPeer = (addr, port, type, payload) => seen.complete(port);

      b.endpointTo(InternetAddress.loopbackIPv4, a.port).sendControl({'hi': 1});
      final p = await seen.future.timeout(const Duration(seconds: 2));
      expect(p, b.port);
    });
  });
}
