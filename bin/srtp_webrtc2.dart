import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/src/dtls/dtls_message.dart' as dtls;
import 'package:pure_dart_webrtc/src/dtls3/enums.dart';
import 'package:pure_dart_webrtc/src/dtls3/handshaker/server/srtp_server.dart';
import 'package:pure_dart_webrtc/src/srtp/protection_profiles.dart';
import 'package:pure_dart_webrtc/src/srtp/rtp2.dart';
import 'package:pure_dart_webrtc/src/srtp/srtp_context.dart';
import 'package:pure_dart_webrtc/src/srtp/srtp_manager.dart';
import 'package:pure_dart_webrtc/src/stun3/stun_server8.dart' as stun;

bool isRtpPacket(Uint8List buf, int offset, int arrayLen) {
  // Initial segment of RTP header; 7 bit payload
  // type; values 0...35 and 96...127 usually used
  final payloadType = buf[offset + 1] & 127;
  return (payloadType <= 35) || (payloadType >= 96 && payloadType <= 127);
}

void main(List<String> arguments) {
  String ip = "192.168.56.1";
  // String ip = "127.0.0.1";
  int port = 4444;

  RawDatagramSocket.bind(InternetAddress(ip), port)
      .then((RawDatagramSocket socket) {
    //print('UDP Echo ready to receive');
    print('listening on udp:${socket.address.address}:${socket.port}');

    final handshaker = HandshakeManager(socket);

    SRTPContext srtpContext = SRTPContext(
        //addr: socket.address,
        //conn: socket,
        protectionProfile: ProtectionProfile.aes_128_gcm);
    final srtpManager = SRTPManager();

    bool initSrtp = false;

    socket.listen((RawSocketEvent e) {
      Datagram? d = socket.receive();

      if (d != null) {
        // print("recieved data ${d.data}");

        if (stun.StunMessage.isStunMessage(d.data)) {
          stun.StunServer.handleDatagram(d,
              socket: socket, serverPassword: "05iMxO9GujD2fUWXSoi0ByNd");
        } else if (dtls.isDtlsPacket(d.data, 0, d.data.length)) {
          // Handle DTLS packet
          print("DTLS packet received");
          // Once the handshake has completed, ignore any stray DTLS-shaped
          // datagrams (retransmissions, duplicate Finished, peer
          // close_notify, etc.) instead of feeding them back into the
          // handshake state machine — which would crash on `Null message`.
          if (handshaker.client?.dTLSState == DTLSState.connected) {
            print("DTLS already connected — ignoring extra record");
          } else {
            try {
              handshaker.handleDtlsMessage(d);
            } catch (e, st) {
              print("handleDtlsMessage failed: $e\n$st");
            }
          }
          if (handshaker.client?.dTLSState == DTLSState.connected &&
              !initSrtp) {
            print("DTLS state: ${handshaker.client!.dTLSState}");
            final keyLength = srtpContext.protectionProfile.keyLength();
            final saltLength = srtpContext.protectionProfile.saltLength();
            final keyingMaterial = handshaker.client!
                .exportKeyingMaterial(keyLength * 2 + saltLength * 2);

            print("Srtp keying material: $keyingMaterial");

            // Initialize for *both* directions; for a server, outbound uses
            // server keys/salt and inbound uses client keys/salt.
            srtpManager.initCipherSuiteForRole(
                srtpContext, keyingMaterial, SrtpRole.server);
            initSrtp = true;
          }
        } else if (isRtpPacket(d.data, 0, d.data.length)) {
          print("encrypted data: ${d.data}");
          final packet = Packet.unmarshal(d.data);
          print("encrypted: $packet");

          if (initSrtp && srtpContext.gcm != null) {
            srtpContext.decryptRtpPacket(packet).then((decrypted) {
              print("decrypted: $decrypted");
              final decryptedPacket = Packet.unmarshal(decrypted);
              print("decrypted packet: $decryptedPacket");

              srtpContext.encryptRtpPacket(packet).then((encrypted) {
                socket.send(encrypted, d.address, d.port);
              });
            });
          }
          if (handshaker.client?.dTLSState == DTLSState.connected &&
              !initSrtp) {
            print("DTLS state: ${handshaker.client!.dTLSState}");
            final keyLength = srtpContext.protectionProfile.keyLength();
            final saltLength = srtpContext.protectionProfile.saltLength();
            final keyingMaterial = handshaker.client!
                .exportKeyingMaterial(keyLength * 2 + saltLength * 2);

            print("Srtp keying material: $keyingMaterial");

            srtpManager.initCipherSuiteForRole(
                srtpContext, keyingMaterial, SrtpRole.server);
            initSrtp = true;
          }
        } else {
          print("Unknown packet type received: ");
        }

        // HandshakeContext context = HandshakeContext();
        // final dtlsMsg =
        //     DecodeDtlsMessageResult.decode(context, d.data, 0, d.data.length);

        // print("DTLS msg: $stunMessage");
      }
    });
  });
}
