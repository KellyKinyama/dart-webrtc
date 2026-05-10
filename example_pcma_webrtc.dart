// PCMA (G.711 A-law) over RTP through `RTCPeerConnection`.
//
// This example demonstrates how to plug a G.711 A-law audio source and
// sink into the browser-shaped peer connection in
// `lib/webrtc/peer_connection.dart` — both directions:
//
//   * Packetize:   `Int16List PCM → A-law → PcmaRtpPacketizer →
//                   RTCRtpSender.send()`  (SRTP encrypted out the socket)
//   * Depacketize: `RTCRtpReceiver.onRtp → parsePcmaRtpPacket → A-law
//                   decode → Int16List PCM`
//
// The example runs in two parts:
//
//   PART A — in-process loopback sanity check that exercises the codec
//            and packetizer/depacketizer without any networking. Always
//            runs and verifies the encode/decode round-trip is lossless
//            (within G.711's quantization).
//
//   PART B — sets up an `RTCPeerConnection` as the WebRTC answerer
//            (DTLS server), prints the SDP offer it expects and the SDP
//            answer it produced, and wires the PCMA send/receive hooks
//            so that once a real WebRTC client connects (e.g. a browser
//            speaking the SDP from `WebRTC-Simple-SDP-Handshake-Demo/`),
//            outbound tone audio is streamed and inbound audio is
//            decoded.
//
// NOTE: `RtcUdpTransport` currently only implements the DTLS *server*
// role, so two pure-Dart peers can't complete a handshake against each
// other. PART B therefore needs a real client (browser) to drive the
// SRTP keying. PART A doesn't need any of that.
//
// Run:
//   dart run example_pcma_webrtc.dart
//
// Optional flags:
//   --duration=<seconds>   how long to keep the answerer up (default 30)
//   --port=<port>          UDP port to bind                (default 40000)
//   --skip-server          run only PART A and exit

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/src/codecs/g711.dart';
import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

Future<void> main(List<String> args) async {
  final opts = _parseArgs(args);

  await _partALoopback();
  if (opts.skipServer) return;
  await _partBPeerConnection(opts);
}

// =============================================================================
// PART A — self-contained PCMA round-trip (no networking, no peer connection)
// =============================================================================

Future<void> _partALoopback() async {
  print('=== PART A: PCMA codec + RTP packetizer round-trip ===');

  // Synthesize 100 ms of a 440 Hz tone (5 frames × 20 ms).
  const samplesPerFrame = kPcmaSamplesPer20Ms;
  const frames = 5;
  const toneFreq = 440.0;
  const amplitude = 0.4 * 0x7FFF;

  final packetizer = PcmaRtpPacketizer(ssrc: 0xCAFEBABE);
  final twoPiOverSr = (2 * pi * toneFreq) / kPcmaClockRate;
  var phase = 0.0;

  var maxAbsErr = 0;
  for (var f = 0; f < frames; f++) {
    final pcm = Int16List(samplesPerFrame);
    for (var s = 0; s < samplesPerFrame; s++) {
      pcm[s] = (sin(phase) * amplitude).round();
      phase += twoPiOverSr;
      if (phase > 2 * pi) phase -= 2 * pi;
    }

    // Packetize: PCM → A-law → RTP
    final alaw = pcmToAlaw(pcm);
    final rtpBytes = packetizer.packetize(alaw);

    // Depacketize: RTP → A-law → PCM
    final decoded = decodePcmaRtpPayload(rtpBytes);
    if (decoded == null) {
      throw StateError('frame $f: failed to depacketize PCMA RTP');
    }

    // G.711 is lossy (8-bit log-companded), so compare with a tolerance.
    for (var i = 0; i < pcm.length; i++) {
      final err = (pcm[i] - decoded[i]).abs();
      if (err > maxAbsErr) maxAbsErr = err;
    }
  }

  print('  frames round-tripped       : $frames');
  print('  bytes per RTP packet       : ${12 + samplesPerFrame}');
  print('  next sequence number       : ${packetizer.sequenceNumber}');
  print('  next RTP timestamp         : ${packetizer.timestamp}');
  print('  max |PCM error| (G.711 q.) : $maxAbsErr');
  print('  PART A: OK\n');
}

// =============================================================================
// PART B — wire PCMA into a real RTCPeerConnection (answerer / DTLS server)
// =============================================================================

Future<void> _partBPeerConnection(_Opts opts) async {
  print('=== PART B: RTCPeerConnection answerer with PCMA ===');

  final pc = RTCPeerConnection(RTCConfiguration(
    defaultAudioCodecs: [PcmaCodec()],
  ));
  final tx = pc.addTransceiver(trackOrKind: MediaKind.audio);

  // Bind the UDP socket. This installs the sender hook on `tx.sender` so
  // that `tx.sender.send(rtpBytes)` will SRTP-encrypt and emit on the wire
  // once a peer has completed DTLS.
  final transport = await pc.bind(InternetAddress.anyIPv4, opts.port);
  print('  listening on udp:0.0.0.0:${transport.port}');

  // Receive side: depacketize inbound PCMA RTP.
  final rxStats = _RxStats();
  final rxSub = tx.receiver.onRtp.listen((rtpBytes) {
    final pkt = parsePcmaRtpPacket(rtpBytes);
    if (pkt == null) {
      rxStats.malformed++;
      return;
    }
    if (pkt.payloadType != kPcmaPayloadType) {
      // Some other audio codec arrived — ignore.
      return;
    }
    final pcm = alawToPcm(pkt.payload);
    rxStats.packets++;
    rxStats.samples += pcm.length;
    for (final s in pcm) {
      final a = s.abs();
      if (a > rxStats.peak) rxStats.peak = a;
    }
  });

  // Surface SDP so a caller can connect (e.g. via the demo HTML page in
  // `WebRTC-Simple-SDP-Handshake-Demo/`). Real signaling would carry
  // these over a websocket / HTTP channel.
  final placeholderOffer = await pc.createOffer();
  print('\n--- SDP this answerer would offer (for inspection) ---');
  print(placeholderOffer.sdp);

  // Outbound packetizer + tone generator. Packets are queued via
  // `sender.send()`; until DTLS completes the call returns false and the
  // packet is dropped (which the loop below counts).
  final packetizer = PcmaRtpPacketizer(
    ssrc: Random().nextInt(0x7FFFFFFF),
  );
  final twoPiOverSr = (2 * pi * 440.0) / kPcmaClockRate;
  var phase = 0.0;
  var sent = 0, dropped = 0;

  final connected = Completer<void>();
  pc.onConnectionStateChange = (state) {
    print('  [pc] connectionState=$state');
    if (state == RTCPeerConnectionState.connected && !connected.isCompleted) {
      connected.complete();
    }
  };

  final endAt = DateTime.now().add(opts.duration);
  print('\n  streaming PCMA tone for ${opts.duration.inSeconds}s '
      '(packets dropped until a peer completes DTLS)\n');

  final pcmFrame = Int16List(kPcmaSamplesPer20Ms);
  while (DateTime.now().isBefore(endAt)) {
    for (var s = 0; s < pcmFrame.length; s++) {
      pcmFrame[s] = (sin(phase) * (0.4 * 0x7FFF)).round();
      phase += twoPiOverSr;
      if (phase > 2 * pi) phase -= 2 * pi;
    }
    final rtp = packetizer.packetize(pcmToAlaw(pcmFrame));
    final ok = await tx.sender.send(rtp);
    if (ok) {
      sent++;
    } else {
      dropped++;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  print('\n--- PART B done ---');
  print('  packets sent            : $sent');
  print('  packets dropped (no key): $dropped');
  print('  packets received        : ${rxStats.packets}');
  print('  PCM samples decoded     : ${rxStats.samples}');
  print('  malformed RTP           : ${rxStats.malformed}');
  print('  peak inbound |sample|   : ${rxStats.peak}');

  await rxSub.cancel();
  pc.close();
}

class _RxStats {
  int packets = 0;
  int samples = 0;
  int malformed = 0;
  int peak = 0;
}

class _Opts {
  final Duration duration;
  final int port;
  final bool skipServer;
  _Opts(this.duration, this.port, this.skipServer);
}

_Opts _parseArgs(List<String> args) {
  var seconds = 30;
  var port = 40000;
  var skipServer = false;
  for (final a in args) {
    if (a.startsWith('--duration=')) {
      seconds = int.parse(a.substring('--duration='.length));
    } else if (a.startsWith('--port=')) {
      port = int.parse(a.substring('--port='.length));
    } else if (a == '--skip-server') {
      skipServer = true;
    }
  }
  return _Opts(Duration(seconds: seconds), port, skipServer);
}
