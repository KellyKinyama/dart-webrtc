// whip_publisher — push a VP8 video file to any WHIP ingest endpoint.
//
// WHIP (RFC 9725, "WebRTC-HTTP Ingestion Protocol") is the standard way
// to publish a stream into a WebRTC server using nothing but HTTP. The
// publisher does:
//
//     POST   <whip-url>             Content-Type: application/sdp
//                                   Authorization: Bearer <token>
//                                   <offer SDP>
//
//     201 Created                   Content-Type: application/sdp
//     Location: /resource/abc123
//     <answer SDP>
//
//     ... media flows ...
//
//     DELETE <Location>             Authorization: Bearer <token>
//
// This example reads a VP8 .ivf file (such as the bundled example.ivf or
// example_vp9.ivf — VP9 also works if the server accepts it), builds a
// sendonly PeerConnection, gathers ICE candidates locally, then POSTs the
// resulting offer to the WHIP endpoint.
//
// Usage:
//   dart run bin/whip_publisher.dart \
//       --url   https://your-whip-server/whip/endpoint \
//       --token <bearer-or-empty> \
//       --file  ../../example.ivf \
//       [--loop]
//
// Compatible servers (tested against the WHIP spec):
//   * Broadcast Box           https://github.com/Glimesh/broadcast-box
//   * simple-whip-server      https://github.com/lminiero/simple-whip-server
//   * OvenMediaEngine         https://airensoft.gitbook.io/ovenmediaengine
//   * Cloudflare Stream Live  (commercial, WHIP ingest)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:pure_dart_webrtc/signal/sdp_v2.dart' as sdpv2;
import 'package:pure_dart_webrtc/vpx.dart';
import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:pure_dart_webrtc/src/codecs/vpx/vp8_rtp_payloader.dart';

Future<int> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('url', help: 'WHIP endpoint URL (POST target)', mandatory: true)
    ..addOption('token', defaultsTo: '', help: 'Bearer token (optional)')
    ..addOption('file', defaultsTo: '../../example.ivf', help: 'VP8 .ivf file')
    ..addOption('bind-ip',
        defaultsTo: '0.0.0.0', help: 'Local UDP bind for ICE')
    ..addOption('announce-ip',
        defaultsTo: '',
        help: 'Public IP to advertise in candidates (defaults to bind-ip)')
    ..addOption('rtp-port', defaultsTo: '50100')
    ..addFlag('loop', defaultsTo: true, help: 'Restart file at EOF');

  late final ArgResults opts;
  try {
    opts = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n${parser.usage}');
    return 64;
  }

  final whipUrl = Uri.parse(opts['url'] as String);
  final token = opts['token'] as String;
  final file = File(opts['file'] as String);
  if (!file.existsSync()) {
    stderr.writeln('File not found: ${file.path}');
    return 66;
  }
  final bindIp = InternetAddress(opts['bind-ip'] as String);
  final announce = (opts['announce-ip'] as String).isEmpty
      ? bindIp
      : InternetAddress(opts['announce-ip'] as String);
  final rtpPort = int.parse(opts['rtp-port'] as String);
  final loop = opts['loop'] as bool;

  final reader = IvfReader.open(file);
  stdout.writeln('[whip] source: ${file.path} '
      '${reader.codec.fourcc} ${reader.width}x${reader.height} @${reader.fps}fps');

  final pc = RTCPeerConnection(RTCConfiguration(
    defaultVideoCodecs: [Vp8Codec()],
  ));
  final tx = pc.addTransceiver(
    trackOrKind: MediaKind.video,
    direction: RTCRtpTransceiverDirection.sendonly,
  );
  await pc.bind(bindIp, rtpPort, announceAddress: announce);
  stdout.writeln('[whip] local UDP $rtpPort, announcing ${announce.address}');

  // WHIP servers typically do NOT support trickle ICE — they want a
  // complete offer. Buffer all candidates locally and inject them into
  // the offer SDP before POSTing.
  final candidates = <RTCIceCandidate>[];
  final gatheringDone = Completer<void>();
  pc.onIceCandidate = (cand) {
    if (cand == null) {
      if (!gatheringDone.isCompleted) gatheringDone.complete();
      return;
    }
    candidates.add(cand);
  };

  final ssrc = Random.secure().nextInt(0xFFFFFFFE) + 1;
  final offer = await pc.createOffer();
  final offerSdp = _withSendOnlySsrc(offer.sdp, ssrc, streamId: 'whip');
  await pc.setLocalDescription(
    RTCSessionDescription(RTCSdpType.offer, offerSdp),
  );

  // Don't wait forever for gathering — 3s is plenty on a LAN, and on
  // a public host with no STUN we won't get any srflx candidates anyway.
  await gatheringDone.future.timeout(
    const Duration(seconds: 3),
    onTimeout: () =>
        stderr.writeln('[whip] ice gathering timeout — proceeding'),
  );
  final fullOffer = _injectCandidates(offerSdp, candidates);
  stdout.writeln('[whip] gathered ${candidates.length} candidate(s)');

  // POST the offer.
  final client = HttpClient();
  Uri? resourceUrl;
  try {
    final req = await client.postUrl(whipUrl);
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/sdp');
    if (token.isNotEmpty) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    req.contentLength = utf8.encode(fullOffer).length;
    req.write(fullOffer);
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != HttpStatus.created) {
      stderr.writeln('[whip] POST failed: ${resp.statusCode}\n$body');
      return 1;
    }
    final loc = resp.headers.value(HttpHeaders.locationHeader);
    if (loc != null) {
      resourceUrl =
          loc.startsWith('http') ? Uri.parse(loc) : whipUrl.resolve(loc);
      stdout.writeln('[whip] resource: $resourceUrl');
    }
    await pc.setRemoteDescription(
      RTCSessionDescription(RTCSdpType.answer, body),
    );
    stdout.writeln('[whip] answer set, waiting for DTLS...');
  } catch (e) {
    stderr.writeln('[whip] POST error: $e');
    return 1;
  }

  // Pump frames once DTLS is up.
  final connected = Completer<void>();
  pc.onConnectionStateChange = (s) {
    stdout.writeln('[whip] state: $s');
    if (s == RTCPeerConnectionState.connected && !connected.isCompleted) {
      connected.complete();
    } else if ((s == RTCPeerConnectionState.failed ||
            s == RTCPeerConnectionState.closed) &&
        !connected.isCompleted) {
      connected.completeError('connection $s');
    }
  };

  // Graceful shutdown: DELETE the resource so the server tears down.
  Future<void> shutdown() async {
    stdout.writeln('[whip] shutting down...');
    if (resourceUrl != null) {
      try {
        final req = await client.deleteUrl(resourceUrl);
        if (token.isNotEmpty) {
          req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
        final r = await req.close();
        await r.drain<void>();
        stdout.writeln('[whip] DELETE ${r.statusCode}');
      } catch (e) {
        stderr.writeln('[whip] DELETE failed: $e');
      }
    }
    client.close(force: true);
    pc.close();
    reader.close();
  }

  ProcessSignal.sigint.watch().listen((_) async {
    await shutdown();
    exit(0);
  });

  try {
    await connected.future.timeout(const Duration(seconds: 15));
  } catch (e) {
    stderr.writeln('[whip] never connected: $e');
    await shutdown();
    return 1;
  }
  stdout.writeln('[whip] CONNECTED — streaming ${reader.codec.fourcc}');

  var pt = 96;
  for (final c in tx.codecs) {
    if (c is Vp8Codec) {
      pt = c.payloadType;
      break;
    }
  }
  final fps = reader.fps == 0 ? 30 : reader.fps;
  final frameMs = (1000 / fps).round();
  final tsStep = 90000 ~/ fps;
  var seq = Random.secure().nextInt(0x10000);
  var ts = Random.secure().nextInt(0x80000000);

  while (true) {
    for (final frame in reader.frames()) {
      final pkts = packetizeVp8Frame(
        frame: frame.data,
        ssrc: ssrc,
        timestamp: ts & 0xFFFFFFFF,
        startSeq: seq,
        payloadType: pt,
      );
      seq = (seq + pkts.length) & 0xFFFF;
      ts = (ts + tsStep) & 0xFFFFFFFF;
      for (final p in pkts) {
        await tx.sender.send(p.rawData);
      }
      await Future<void>.delayed(Duration(milliseconds: frameMs));
    }
    if (!loop) break;
    reader.close();
    final r2 = IvfReader.open(file);
    // Reuse same fields by replacing reader-bound state — simplest is to
    // start over from the new reader's iterator inline.
    for (final frame in r2.frames()) {
      final pkts = packetizeVp8Frame(
        frame: frame.data,
        ssrc: ssrc,
        timestamp: ts & 0xFFFFFFFF,
        startSeq: seq,
        payloadType: pt,
      );
      seq = (seq + pkts.length) & 0xFFFF;
      ts = (ts + tsStep) & 0xFFFFFFFF;
      for (final p in pkts) {
        await tx.sender.send(p.rawData);
      }
      await Future<void>.delayed(Duration(milliseconds: frameMs));
    }
    r2.close();
  }
  await shutdown();
  return 0;
}

/// Add `a=ssrc:<ssrc> cname:<...>` and `a=ssrc:<ssrc> msid:<...>` to the
/// first video m= section of [sdp]. WHIP servers usually require msid.
String _withSendOnlySsrc(String sdp, int ssrc, {required String streamId}) {
  final session = sdpv2.parseSdp(sdp);
  for (final m in session.mediaList) {
    if ((m['type'] as String?) != 'video') continue;
    final list = (m['ssrcs'] as List?) ?? <Map<String, dynamic>>[];
    list.add({'id': ssrc, 'attribute': 'cname', 'value': 'whip-publisher'});
    list.add({
      'id': ssrc,
      'attribute': 'msid',
      'value': '$streamId $streamId-video'
    });
    m['ssrcs'] = list;
    break;
  }
  return sdpv2.writeSdp(session);
}

/// Inject collected ICE candidates as `a=candidate:` lines into the SDP
/// (one set per media section).
String _injectCandidates(String sdp, List<RTCIceCandidate> cands) {
  if (cands.isEmpty) return sdp;
  final lines = sdp.split(RegExp(r'\r?\n'));
  final out = <String>[];
  bool inMedia = false;
  bool injected = false;
  for (final line in lines) {
    if (line.startsWith('m=')) {
      if (inMedia && !injected) {
        for (final c in cands) {
          out.add('a=${c.candidate}');
        }
        out.add('a=end-of-candidates');
        injected = true;
      }
      inMedia = true;
      injected = false;
      out.add(line);
      continue;
    }
    out.add(line);
  }
  if (inMedia && !injected) {
    for (final c in cands) {
      out.add('a=${c.candidate}');
    }
    out.add('a=end-of-candidates');
  }
  return out.join('\r\n');
}
