// SRTP inbound replay-window protection (RFC 3711 §3.3.2).
//
// Encrypts a tiny RTP stream client-side, then verifies that the
// server-side context:
//   * accepts the first delivery of each packet,
//   * rejects an exact replay,
//   * accepts an out-of-order packet that still falls inside the 64-
//     packet sliding window,
//   * rejects an exact replay of that out-of-order packet,
//   * rejects a packet that's too old (outside the window).

import 'dart:typed_data';

import 'package:pure_dart_webrtc/src/srtp/protection_profiles.dart';
import 'package:pure_dart_webrtc/src/srtp/rtp2.dart';
import 'package:pure_dart_webrtc/src/srtp/srtp_context.dart';
import 'package:pure_dart_webrtc/src/srtp/srtp_manager.dart';
import 'package:test/test.dart';

void main() {
  group('SRTP inbound replay window', () {
    late Uint8List keyingMaterial;
    setUpAll(() {
      keyingMaterial = Uint8List.fromList(List<int>.generate(56, (i) => i));
    });

    SRTPContext makeCtx(SrtpRole role) {
      final ctx = SRTPContext(protectionProfile: ProtectionProfile.aes_128_gcm);
      SRTPManager().initCipherSuiteForRole(ctx, keyingMaterial, role);
      return ctx;
    }

    /// Build a minimal RTP packet (no CSRC/extension/padding) and
    /// encrypt it with [client]. Returns the on-the-wire SRTP bytes.
    Future<Uint8List> encrypt(SRTPContext client,
        {required int seq, int ssrc = 0xCAFEBABE}) async {
      final raw = Uint8List(12 + 4);
      raw[0] = 0x80; // V=2
      raw[1] = 96; // PT
      raw[2] = (seq >> 8) & 0xff;
      raw[3] = seq & 0xff;
      // ts = seq * 100, irrelevant for replay logic
      final ts = seq * 100;
      raw[4] = (ts >> 24) & 0xff;
      raw[5] = (ts >> 16) & 0xff;
      raw[6] = (ts >> 8) & 0xff;
      raw[7] = ts & 0xff;
      raw[8] = (ssrc >> 24) & 0xff;
      raw[9] = (ssrc >> 16) & 0xff;
      raw[10] = (ssrc >> 8) & 0xff;
      raw[11] = ssrc & 0xff;
      // payload: 4 bytes of zeros
      final pkt = Packet.unmarshal(raw);
      return client.encryptRtpPacket(pkt);
    }

    Future<void> deliver(SRTPContext server, Uint8List srtp) async {
      final pkt = Packet.unmarshal(srtp);
      await server.decryptRtpPacket(pkt);
    }

    test('first delivery of each new seq succeeds; exact replay throws',
        () async {
      final c = makeCtx(SrtpRole.client);
      final s = makeCtx(SrtpRole.server);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final p1 = await encrypt(c, seq: 100);
      final p2 = await encrypt(c, seq: 101);
      await deliver(s, p1);
      await deliver(s, p2);
      expect(s.srtpReplayDrops, 0);

      // Exact replay of p1.
      expect(() => deliver(s, p1), throwsA(isA<StateError>()));
      expect(s.srtpReplayDrops, 1);
    });

    test('out-of-order packet inside the 64-window is accepted', () async {
      final c = makeCtx(SrtpRole.client);
      final s = makeCtx(SrtpRole.server);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Encrypt 100..120 in order on the sender side, but only deliver
      // 100, 120 first; then deliver 110 (10 old, well inside 64).
      final pkts = <int, Uint8List>{};
      for (var i = 100; i <= 120; i++) {
        pkts[i] = await encrypt(c, seq: i);
      }
      await deliver(s, pkts[100]!);
      await deliver(s, pkts[120]!);
      await deliver(s, pkts[110]!); // out-of-order, inside window
      expect(s.srtpReplayDrops, 0);

      // Replay 110 — must be rejected.
      expect(() => deliver(s, pkts[110]!), throwsA(isA<StateError>()));
      expect(s.srtpReplayDrops, 1);
    });

    test('packet older than window (> 64 behind top) is rejected', () async {
      final c = makeCtx(SrtpRole.client);
      final s = makeCtx(SrtpRole.server);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Encrypt seq 1 and seq 200; deliver seq 200 first (top=200).
      // Then deliver seq 1 (199 behind, way past the 64-window) — must
      // be rejected.
      final p1 = await encrypt(c, seq: 1);
      final p200 = await encrypt(c, seq: 200);
      await deliver(s, p200);
      expect(() => deliver(s, p1), throwsA(isA<StateError>()));
      expect(s.srtpReplayDrops, 1);
    });

    test('different SSRCs have independent windows', () async {
      final c = makeCtx(SrtpRole.client);
      final s = makeCtx(SrtpRole.server);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final aHi = await encrypt(c, seq: 50, ssrc: 0xAAAA0000);
      final bLo = await encrypt(c, seq: 1, ssrc: 0xBBBB0000);
      await deliver(s, aHi);
      // seq=1 on a *different* ssrc must NOT be considered a replay
      // even though it would be way outside the window for ssrc A.
      await deliver(s, bLo);
      expect(s.srtpReplayDrops, 0);
    });
  });
}
