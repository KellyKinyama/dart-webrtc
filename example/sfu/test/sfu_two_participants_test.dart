// Two-participant end-to-end SFU integration test.
//
// Builds a real BasicSfu, connects two DTLS clients (alice + bob) to it,
// initializes per-client SRTP, has alice send an RTP packet, and verifies
// bob receives the decrypted packet with the SSRC rewritten to its own
// per-receiver value.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/src/dtls/examples/client/dtls_client.dart';
import 'package:pure_dart_webrtc/src/srtp/protection_profiles.dart';
import 'package:pure_dart_webrtc/src/srtp/rtp2.dart';
import 'package:pure_dart_webrtc/src/srtp/srtp_client.dart';
import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:pure_dart_webrtc_sfu_example/basic_sfu.dart';
import 'package:test/test.dart';

void main() {
  test(
    'two participants exchange RTP via the SFU with SSRC rewriting',
    () async {
      final sfu = BasicSfu(
        address: InternetAddress.loopbackIPv4,
        basePort: 0, // OS-allocated; per-port allocation is per addParticipant
      );
      addTearDown(sfu.close);

      final connectedAll = Completer<void>();
      final connected = <String>{};
      sfu.onParticipantConnected = (p) {
        connected.add(p.id);
        if (connected.length == 2 && !connectedAll.isCompleted) {
          connectedAll.complete();
        }
      };

      final alice = await sfu.addParticipant('alice');
      final bob = await sfu.addParticipant('bob');

      // Run a DTLS client against each participant's bound UDP port.
      final aliceClient = DtlsClient(
        InternetAddress.loopbackIPv4,
        alice.transport.port,
      );
      addTearDown(aliceClient.close);

      final bobClient = DtlsClient(
        InternetAddress.loopbackIPv4,
        bob.transport.port,
      );
      addTearDown(bobClient.close);

      await Future.wait([
        aliceClient.connect(),
        bobClient.connect(),
      ]).timeout(const Duration(seconds: 15));

      // Wait until the SFU has observed both DTLS sessions reach
      // connected state.
      await connectedAll.future.timeout(const Duration(seconds: 5));

      expect(alice.pc.connectionState, RTCPeerConnectionState.connected);
      expect(bob.pc.connectionState, RTCPeerConnectionState.connected);

      // Wrap each DTLS client's socket with an SRTP client (client role).
      const profile = ProtectionProfile.aes_128_gcm;
      final ekmLen = 2 * profile.keyLength() + 2 * profile.saltLength();

      final aliceSrtp = SRTPClient.wrap(
        socket: aliceClient.socket,
        remote: InternetAddress.loopbackIPv4,
        remotePort: alice.transport.port,
        protectionProfile: profile,
        subscribeToSocket: false,
      );
      aliceClient.onApplicationDatagram = aliceSrtp.handleDatagram;
      await aliceSrtp.initialize(aliceClient.exportKeyingMaterial(ekmLen));

      final bobSrtp = SRTPClient.wrap(
        socket: bobClient.socket,
        remote: InternetAddress.loopbackIPv4,
        remotePort: bob.transport.port,
        protectionProfile: profile,
        subscribeToSocket: false,
      );
      bobClient.onApplicationDatagram = bobSrtp.handleDatagram;
      await bobSrtp.initialize(bobClient.exportKeyingMaterial(ekmLen));

      // Listen on bob for the forwarded packet.
      const aliceSsrc = 0xAABBCCDD;
      const payload = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      final received = Completer<SrtpPacket>();
      final sub = bobSrtp.packets.listen((p) {
        if (!received.isCompleted) received.complete(p);
      });
      addTearDown(sub.cancel);

      // Send a tiny RTP packet from alice. Build it from raw bytes (V=2,
      // PT=96, seq=1, ts=0, ssrc=aliceSsrc) so the Packet's rawData and
      // headerSize are populated correctly for SRTP encryption.
      final rtpBytes = Uint8List.fromList([
        0x80, // V=2, P=0, X=0, CC=0
        0x60, // M=0, PT=96
        0x00, 0x01, // seq=1
        0x00, 0x00, 0x00, 0x00, // timestamp
        (aliceSsrc >> 24) & 0xff,
        (aliceSsrc >> 16) & 0xff,
        (aliceSsrc >> 8) & 0xff,
        aliceSsrc & 0xff,
        ...payload,
      ]);
      final aliceRtp = Packet.unmarshal(rtpBytes);

      await aliceSrtp.sendRtp(aliceRtp);

      final pkt = await received.future.timeout(const Duration(seconds: 5));

      expect(pkt.packet.payload, payload);
      expect(pkt.packet.header.payloadType, 96);
      expect(
        pkt.packet.header.ssrc,
        isNot(aliceSsrc),
        reason: 'SFU must rewrite SSRC for the receiver',
      );
      expect(sfu.stats.rtpForwarded, greaterThanOrEqualTo(1));
      expect(sfu.stats.ssrcRewrites, greaterThanOrEqualTo(1));

      await aliceSrtp.close();
      await bobSrtp.close();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
