// End-to-end demo: DTLS handshake + SRTP send-only VP8 client.
//
// What this does:
//   1. Performs a DTLS 1.2 handshake against the existing server example
//      (`bin/srtp_webrtc2.dart`), which listens on UDP and runs
//      `HandshakeManager` from `lib/src/dtls3/handshaker/server/srtp_server.dart`.
//   2. Exports `2*keyLen + 2*saltLen` bytes (56 for SRTP_AEAD_AES_128_GCM)
//      of keying material via RFC 5705.
//   3. Hands the same UDP socket and the keying material to an [SRTPClient].
//   4. Reads VP8 frames from an IVF file, packetizes them per RFC 7741 and
//      sends each packet through SRTP at the file's frame rate.
//
// Run order:
//   # terminal A — start the existing server demo
//   dart run bin/srtp_webrtc2.dart
//
//   # terminal B — start this client (host:port must match the server)
//   dart run bin/srtp_client.dart --host 192.168.56.1 --port 4444 \
//       --ivf vp80-00-comprehensive-001.ivf
//
// Note: `bin/srtp_webrtc2.dart` also expects a STUN binding step before
// DTLS in a real WebRTC flow. For a pure DTLS+SRTP smoke test against the
// server, comment out the STUN gate or run this demo on its own port.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/src/codecs/vpx/ivf.dart';
import 'package:pure_dart_webrtc/src/codecs/vpx/vp8_rtp_payloader.dart';
import 'package:pure_dart_webrtc/src/dtls/examples/client/dtls_client.dart';
import 'package:pure_dart_webrtc/src/srtp/protection_profiles.dart';
import 'package:pure_dart_webrtc/src/srtp/srtp_client.dart';

Future<int> main(List<String> args) async {
  String host = '127.0.0.1';
  int port = 4444;
  String ivfPath = 'vp80-00-comprehensive-001.ivf';
  int ssrc = 0x1234ABCD;
  int payloadType = 96;
  bool loop = false;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--host' && i + 1 < args.length) {
      host = args[++i];
    } else if (a == '--port' && i + 1 < args.length) {
      port = int.parse(args[++i]);
    } else if (a == '--ivf' && i + 1 < args.length) {
      ivfPath = args[++i];
    } else if (a == '--ssrc' && i + 1 < args.length) {
      ssrc = int.parse(args[++i]);
    } else if (a == '--pt' && i + 1 < args.length) {
      payloadType = int.parse(args[++i]);
    } else if (a == '--loop') {
      loop = true;
    } else if (a == '-h' || a == '--help') {
      stdout.writeln(
          'Usage: srtp_client [--host H] [--port P] [--ivf F] [--ssrc N] [--pt N] [--loop]');
      return 0;
    }
  }

  final ivf = File(ivfPath);
  if (!ivf.existsSync()) {
    stderr.writeln('IVF file not found: $ivfPath');
    return 66;
  }

  // 1) DTLS handshake.
  final dtls = DtlsClient(InternetAddress(host), port);
  print('[demo] dialing dtls://$host:$port');
  await dtls.connect();
  await dtls.done;
  print('[demo] DTLS handshake complete');

  // 2) Export keying material (56 bytes for SRTP_AEAD_AES_128_GCM).
  const profile = ProtectionProfile.aes_128_gcm;
  final ekmLen = 2 * profile.keyLength() + 2 * profile.saltLength();
  final keyingMaterial = dtls.exportKeyingMaterial(ekmLen);
  print('[demo] exported $ekmLen bytes of keying material');

  // 3) Hand the same UDP socket to the SRTP client (don't detach: keep the
  //    DTLS client's existing subscription, route inbound application
  //    datagrams through `onApplicationDatagram`).
  final srtp = SRTPClient.wrap(
    socket: dtls.socket,
    remote: InternetAddress(host),
    remotePort: port,
    protectionProfile: profile,
    subscribeToSocket: false,
  );
  dtls.onApplicationDatagram = srtp.handleDatagram;
  await srtp.initialize(keyingMaterial);
  print('[demo] SRTP client ready (role=client, profile=$profile)');

  // Drain any inbound RTP just so the stream has a listener.
  srtp.packets.listen((p) {
    print('[demo] <-- ${p.packet.payload.length} byte VP8 RTP from '
        '${p.remoteAddress.address}:${p.remotePort}');
  });
  srtp.rtcpPackets.listen((p) {
    final pt = p.rtcp.length >= 2 ? (p.rtcp[1] & 0x7f) : -1;
    print('[demo] <-- ${p.rtcp.length} byte RTCP (pt=$pt) from '
        '${p.remoteAddress.address}:${p.remotePort}');
  });

  // 4a) Send a small RTCP Receiver Report before media to exercise SRTCP.
  final rr = _buildEmptyRtcpRr(ssrc);
  final n = await srtp.sendRtcp(rr);
  print('[demo] sent $n byte SRTCP RR (ssrc=0x${ssrc.toRadixString(16)})');

  // 4) Send VP8 frames from the IVF file.
  do {
    await _sendIvf(ivf, srtp, ssrc: ssrc, payloadType: payloadType);
  } while (loop);

  await Future<void>.delayed(const Duration(milliseconds: 500));
  await srtp.close();
  await dtls.close();
  return 0;
}

/// Build a minimal RTCP Receiver Report (RFC 3550 §6.4.2) with no report
/// blocks. 8 bytes total: header (V=2,P=0,RC=0,PT=201,len=1) + sender SSRC.
Uint8List _buildEmptyRtcpRr(int ssrc) {
  final b = Uint8List(8);
  final bd = ByteData.view(b.buffer);
  b[0] = 0x80; // V=2, P=0, RC=0
  b[1] = 201; // PT=RR
  bd.setUint16(2, 1, Endian.big); // length in 32-bit words minus 1
  bd.setUint32(4, ssrc, Endian.big);
  return b;
}

Future<void> _sendIvf(File ivfFile, SRTPClient srtp,
    {required int ssrc, required int payloadType}) async {
  final reader = IvfReader.open(ivfFile);
  final fps = reader.fps == 0 ? 30 : reader.fps;
  final frameInterval = Duration(microseconds: (1000000 / fps).round());
  // 90 kHz RTP clock for VP8.
  final tsStep = (90000 / fps).round();

  print('[demo] streaming ${ivfFile.path} '
      '(${reader.codec.fourcc} ${reader.width}x${reader.height} ${fps}fps, '
      'pt=$payloadType, ssrc=0x${ssrc.toRadixString(16)})');

  int seq = DateTime.now().millisecondsSinceEpoch & 0xffff;
  int timestamp = DateTime.now().millisecondsSinceEpoch & 0xffffffff;
  int sentFrames = 0;
  int sentPackets = 0;
  int sentBytes = 0;

  for (final frame in reader.frames()) {
    final packets = packetizeVp8Frame(
      frame: Uint8List.fromList(frame.data),
      ssrc: ssrc,
      timestamp: timestamp,
      startSeq: seq,
      payloadType: payloadType,
    );
    for (final pkt in packets) {
      try {
        final n = await srtp.sendRtp(pkt);
        sentBytes += n;
        sentPackets++;
      } catch (e) {
        stderr.writeln('[demo] sendRtp failed: $e');
      }
    }
    seq = (seq + packets.length) & 0xffff;
    timestamp = (timestamp + tsStep) & 0xffffffff;
    sentFrames++;

    if (sentFrames % 30 == 0) {
      print('[demo] sent $sentFrames frames / '
          '$sentPackets packets / $sentBytes bytes');
    }
    await Future<void>.delayed(frameInterval);
  }
  reader.close();
  print('[demo] done: $sentFrames frames / $sentPackets packets / '
      '$sentBytes bytes');
}
