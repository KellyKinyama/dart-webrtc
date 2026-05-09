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

  test(
    'SFU sends a PLI to alice when bob connects with alice already producing',
    () async {
      final sfu = BasicSfu(
        address: InternetAddress.loopbackIPv4,
        basePort: 0,
      );
      addTearDown(sfu.close);

      final alice = await sfu.addParticipant('alice');
      final aliceConnected = Completer<void>();
      final bobConnected = Completer<void>();
      sfu.onParticipantConnected = (p) {
        if (p.id == 'alice' && !aliceConnected.isCompleted) {
          aliceConnected.complete();
        }
        if (p.id == 'bob' && !bobConnected.isCompleted) {
          bobConnected.complete();
        }
      };

      // Wire alice's DTLS+SRTP first so she's a fully-connected producer
      // before bob arrives.
      final aliceClient = DtlsClient(
        InternetAddress.loopbackIPv4,
        alice.transport.port,
      );
      addTearDown(aliceClient.close);
      await aliceClient.connect().timeout(const Duration(seconds: 15));
      await aliceConnected.future.timeout(const Duration(seconds: 5));

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

      const aliceSsrc = 0x12345678;
      // Register a video producer for alice in the SFU (as the WS server
      // would after parsing her offer SDP).
      final aliceOffer = 'v=0\r\n'
          'o=- 1 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'a=rtpmap:96 VP8/90000\r\n'
          'a=ssrc:$aliceSsrc cname:alice\r\n';
      sfu.learnSsrcMappingFromOffer('alice', aliceOffer);

      // Listen for the inbound PLI on alice. We expect either:
      //   * the auto-PLI fired by learnSsrcMappingFromOffer above, OR
      //   * the auto-PLI fired when bob's DTLS reaches connected.
      final pliReceived = Completer<Uint8List>();
      final sub = aliceSrtp.rtcpPackets.listen((p) {
        if (pliReceived.isCompleted) return;
        // PSFB PT=206, FMT=1 (PLI) on the media SSRC.
        for (var off = 0; off + 4 <= p.rtcp.length;) {
          final pt = p.rtcp[off + 1];
          final lenWords =
              ByteData.sublistView(p.rtcp, off + 2, off + 4).getUint16(0);
          final subLen = (lenWords + 1) * 4;
          if (subLen <= 0 || off + subLen > p.rtcp.length) break;
          final fmt = p.rtcp[off] & 0x1F;
          if (pt == 206 && fmt == 1) {
            pliReceived
                .complete(Uint8List.sublistView(p.rtcp, off, off + subLen));
            return;
          }
          off += subLen;
        }
      });
      addTearDown(sub.cancel);

      // Now bring bob up. His connect handler should fire requestKeyframe
      // for alice, which the SFU forwards as a PLI on alice's primary SSRC.
      final bob = await sfu.addParticipant('bob');
      final bobClient = DtlsClient(
        InternetAddress.loopbackIPv4,
        bob.transport.port,
      );
      addTearDown(bobClient.close);
      await bobClient.connect().timeout(const Duration(seconds: 15));
      await bobConnected.future.timeout(const Duration(seconds: 5));

      final pli = await pliReceived.future.timeout(const Duration(seconds: 5));
      expect(pli.length, 12);
      expect(pli[1], 206);
      expect(pli[0] & 0x1F, 1);
      // Media SSRC field (bytes 8..12) must point at alice's primary.
      final mediaSsrc = ByteData.sublistView(pli).getUint32(8, Endian.big);
      expect(mediaSsrc, aliceSsrc);
      expect(sfu.stats.pliSent, greaterThanOrEqualTo(1));

      await aliceSrtp.close();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
