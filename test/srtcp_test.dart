import 'dart:typed_data';

import 'package:pure_dart_webrtc/src/srtp/protection_profiles.dart';
import 'package:pure_dart_webrtc/src/srtp/srtp_context.dart';
import 'package:pure_dart_webrtc/src/srtp/srtp_manager.dart';
import 'package:test/test.dart';

void main() {
  group('SRTCP AES-128-GCM', () {
    late Uint8List keyingMaterial;

    setUpAll(() {
      // 56 bytes: clientKey(16) || serverKey(16) || clientSalt(12) || serverSalt(12)
      keyingMaterial = Uint8List.fromList(List<int>.generate(56, (i) => i));
    });

    SRTPContext makeCtx(SrtpRole role) {
      final ctx = SRTPContext(protectionProfile: ProtectionProfile.aes_128_gcm);
      SRTPManager().initCipherSuiteForRole(ctx, keyingMaterial, role);
      return ctx;
    }

    test('client outbound -> server inbound round-trip RR', () async {
      // Build a minimal RR: V=2, P=0, RC=0, PT=201, len=1, SSRC=0xdeadbeef
      final rtcp = Uint8List(8);
      final bd = ByteData.view(rtcp.buffer);
      rtcp[0] = 0x80;
      rtcp[1] = 201;
      bd.setUint16(2, 1, Endian.big);
      bd.setUint32(4, 0xdeadbeef, Endian.big);

      final clientCtx = makeCtx(SrtpRole.client);
      final serverCtx = makeCtx(SrtpRole.server);
      // Allow async key derivation to complete.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final srtcp = await clientCtx.encryptRtcpPacket(rtcp);
      // 8 header + 0 plaintext body + 16 tag + 4 trailer = 28 bytes.
      expect(srtcp.length, equals(28));

      final decoded = await serverCtx.decryptRtcpPacket(srtcp);
      expect(decoded, equals(rtcp));
    });

    test('SRTCP index increments per encrypt', () async {
      final rtcp = Uint8List(8);
      ByteData.view(rtcp.buffer)
        ..setUint8(0, 0x80)
        ..setUint8(1, 201)
        ..setUint16(2, 1, Endian.big)
        ..setUint32(4, 0x11223344, Endian.big);

      final ctx = makeCtx(SrtpRole.client);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final a = await ctx.encryptRtcpPacket(rtcp);
      final b = await ctx.encryptRtcpPacket(rtcp);

      final idxA = ByteData.sublistView(a, a.length - 4).getUint32(0, Endian.big)
          & 0x7FFFFFFF;
      final idxB = ByteData.sublistView(b, b.length - 4).getUint32(0, Endian.big)
          & 0x7FFFFFFF;
      expect(idxB, equals(idxA + 1));
      // Different ciphertexts since IV differs.
      expect(a, isNot(equals(b)));
    });
  });
}
