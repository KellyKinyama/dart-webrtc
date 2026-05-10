// rtsp_to_webrtc — live VP8 broadcast to both browsers (WebRTC) and
// RTSP players, sourced from a synthetic frame generator built with the
// `image` package.
//
// Pipeline:
//
//   image.Image  ──►  RGB24  ──►  I420  ──►  VpxEncoder (VP8)
//                                                │
//                                                ▼
//                                         _FrameHub (broadcast)
//                                          │             │
//                                          ▼             ▼
//                                     WebRTC subs   RTSP subs
//
// Each compressed VP8 access unit is delivered exactly once to the hub
// and then mirrored to every subscriber, so adding viewers does not cost
// extra encode time.
//
// Usage:
//   dart run bin/rtsp_to_webrtc.dart \
//       --ip 192.168.56.1 --http-port 8080 --rtsp-port 8554
//
// Open a browser at http://<ip>:8080/ for the WebRTC viewer.
// Open VLC / ffplay at rtsp://<ip>:8554/live for the RTSP viewer.
//
// The RTSP path uses RFC 7826 §14 TCP-interleaved framing
// (`$<channel><len><RTP>`) so it works through firewalls without a
// second UDP socket.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:image/image.dart' as img;
import 'package:pure_dart_webrtc/signal/sdp_v2.dart';
import 'package:pure_dart_webrtc/src/codecs/vpx/vp8_rtp_payloader.dart';
import 'package:pure_dart_webrtc/vpx.dart';
import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

const int _width = 384;
const int _height = 216;
const int _fps = 25;
const int _bitrateKbps = 800;

Future<int> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('ip', defaultsTo: '127.0.0.1')
    ..addOption('http-port', defaultsTo: '8080')
    ..addOption('rtsp-port', defaultsTo: '8554')
    ..addOption('rtp-port',
        defaultsTo: '50000', help: 'first UDP port for SRTP (browser clients)');

  late final ArgResults opts;
  try {
    opts = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    return 64;
  }

  final ip = InternetAddress(opts['ip'] as String);
  final httpPort = int.parse(opts['http-port'] as String);
  final rtspPort = int.parse(opts['rtsp-port'] as String);
  final rtpPort = int.parse(opts['rtp-port'] as String);

  // Single shared frame source.
  final hub = _FrameHub();
  unawaited(_runEncoder(hub));

  // Two independent listeners against the same hub.
  unawaited(_runHttpServer(ip, httpPort, rtpPort, hub));
  unawaited(_runRtspServer(ip, rtspPort, hub));

  stdout.writeln('[main] WebRTC: http://${ip.address}:$httpPort');
  stdout.writeln('[main] RTSP  : rtsp://${ip.address}:$rtspPort/live');

  // Block forever.
  await Completer<void>().future;
  return 0;
}

// ---------------------------------------------------------------------------
// Encoded-frame hub
// ---------------------------------------------------------------------------

class _EncodedFrame {
  final Uint8List data;
  final bool isKeyframe;
  _EncodedFrame(this.data, this.isKeyframe);
}

class _FrameHub {
  final _subs = <StreamController<_EncodedFrame>>{};

  /// Most recent keyframe — handed to brand-new subscribers so VP8
  /// decoders sync immediately instead of waiting up to ~1 s for the
  /// next encoder keyframe.
  _EncodedFrame? lastKeyframe;

  Stream<_EncodedFrame> subscribe() {
    final ctl = StreamController<_EncodedFrame>(sync: true);
    ctl.onCancel = () => _subs.remove(ctl);
    _subs.add(ctl);
    final kf = lastKeyframe;
    if (kf != null) {
      scheduleMicrotask(() {
        if (!ctl.isClosed) ctl.add(kf);
      });
    }
    return ctl.stream;
  }

  void publish(_EncodedFrame frame) {
    if (frame.isKeyframe) lastKeyframe = frame;
    for (final s in _subs.toList()) {
      if (!s.isClosed) s.add(frame);
    }
  }
}

// ---------------------------------------------------------------------------
// Synthetic camera + VP8 encoder
// ---------------------------------------------------------------------------

Future<void> _runEncoder(_FrameHub hub) async {
  final encoder = VpxEncoder(
    codec: VpxCodec.vp8,
    width: _width,
    height: _height,
    fps: _fps,
    bitrateKbps: _bitrateKbps,
    keyframeInterval: _fps * 2, // a keyframe every 2 s
  );
  final period = Duration(microseconds: (1e6 / _fps).round());
  final start = DateTime.now();
  var pts = 0;

  Timer.periodic(period, (_) {
    final elapsed = DateTime.now().difference(start);
    final rgb = _renderFrame(pts, elapsed);
    final i420 = I420Frame.fromRgb24(rgb, _width, _height);
    for (final pkt in encoder.encode(i420, pts: pts)) {
      hub.publish(_EncodedFrame(pkt.data, pkt.isKeyframe));
    }
    pts++;
  });
}

/// Animated test pattern rendered with the `image` package: SMPTE-ish
/// colour bars, a moving sweep line, an elapsed-time clock and a frame
/// counter. Returns packed RGB24 bytes (R,G,B,R,G,B,...).
Uint8List _renderFrame(int frameIdx, Duration elapsed) {
  final im = img.Image(width: _width, height: _height, numChannels: 3);

  // Colour bars background.
  const bars = <List<int>>[
    [192, 192, 192],
    [192, 192, 0],
    [0, 192, 192],
    [0, 192, 0],
    [192, 0, 192],
    [192, 0, 0],
    [0, 0, 192],
  ];
  final barW = _width ~/ bars.length;
  for (var i = 0; i < bars.length; i++) {
    img.fillRect(
      im,
      x1: i * barW,
      y1: 0,
      x2: (i == bars.length - 1) ? _width - 1 : (i + 1) * barW - 1,
      y2: _height - 1,
      color: img.ColorRgb8(bars[i][0], bars[i][1], bars[i][2]),
    );
  }

  // Moving vertical sweep line.
  final sweepX = (frameIdx * 4) % _width;
  img.drawLine(
    im,
    x1: sweepX,
    y1: 0,
    x2: sweepX,
    y2: _height - 1,
    color: img.ColorRgb8(255, 255, 255),
    thickness: 2,
  );

  // Black info strip.
  img.fillRect(
    im,
    x1: 0,
    y1: _height - 28,
    x2: _width - 1,
    y2: _height - 1,
    color: img.ColorRgb8(0, 0, 0),
  );

  final secs = elapsed.inMilliseconds / 1000.0;
  final label = 'rtsp_to_webrtc  f=$frameIdx  t=${secs.toStringAsFixed(2)}s';
  img.drawString(
    im,
    label,
    font: img.arial14,
    x: 6,
    y: _height - 22,
    color: img.ColorRgb8(255, 255, 255),
  );

  // Pack to RGB24.
  final out = Uint8List(_width * _height * 3);
  var o = 0;
  for (final p in im) {
    out[o++] = p.r.toInt();
    out[o++] = p.g.toInt();
    out[o++] = p.b.toInt();
  }
  return out;
}

// ---------------------------------------------------------------------------
// WebRTC server (HTTP + WebSocket signalling, same shape as play_from_disk)
// ---------------------------------------------------------------------------

int _nextWebrtcPortOffset = 0;

Future<void> _runHttpServer(
  InternetAddress ip,
  int port,
  int rtpBasePort,
  _FrameHub hub,
) async {
  final server = await HttpServer.bind(ip, port);
  await for (final req in server) {
    if (req.uri.path == '/' || req.uri.path == '/index.html') {
      req.response.headers.contentType =
          ContentType('text', 'html', charset: 'utf-8');
      req.response.write(_demoHtml);
      await req.response.close();
      continue;
    }
    if (req.uri.path == '/ws') {
      try {
        final ws = await WebSocketTransformer.upgrade(req);
        unawaited(_handleWebrtcClient(ws, ip, rtpBasePort, hub));
      } catch (e) {
        stderr.writeln('[webrtc] WS upgrade failed: $e');
      }
      continue;
    }
    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }
}

Future<void> _handleWebrtcClient(
  WebSocket ws,
  InternetAddress ip,
  int basePort,
  _FrameHub hub,
) async {
  final port = basePort + _nextWebrtcPortOffset++;
  final pc = RTCPeerConnection(RTCConfiguration(
    defaultVideoCodecs: [Vp8Codec()],
  ));
  final transceiver = pc.addTransceiver(
    trackOrKind: MediaKind.video,
    direction: RTCRtpTransceiverDirection.sendonly,
  );
  await pc.bind(ip, port, announceAddress: ip);
  stdout.writeln('[webrtc] new viewer on UDP $port');

  final ssrc = Random.secure().nextInt(0xFFFFFFFE) + 1;

  pc.onIceCandidate = (cand) {
    if (cand == null) {
      ws.add(jsonEncode({'type': 'candidate', 'candidate': null}));
      return;
    }
    ws.add(jsonEncode({
      'type': 'candidate',
      'candidate': cand.candidate,
      'sdpMid': cand.sdpMid,
      'sdpMLineIndex': cand.sdpMLineIndex,
    }));
  };

  final offer = await pc.createOffer();
  final offerSdp = _addSendOnlySsrc(offer.sdp, ssrc, streamId: 'cam');
  await pc.setLocalDescription(
    RTCSessionDescription(RTCSdpType.offer, offerSdp),
  );
  ws.add(jsonEncode({'type': 'offer', 'sdp': offerSdp}));

  StreamSubscription<_EncodedFrame>? sub;
  var seq = Random.secure().nextInt(0x10000);
  var ts = Random.secure().nextInt(0x80000000);
  const tsStep = 90000 ~/ _fps;

  pc.onConnectionStateChange = (state) {
    if (state == RTCPeerConnectionState.connected && sub == null) {
      stdout.writeln('[webrtc] DTLS connected on $port — subscribing to hub');
      sub = hub.subscribe().listen((frame) async {
        final pkts = packetizeVp8Frame(
          frame: frame.data,
          ssrc: ssrc,
          timestamp: ts & 0xFFFFFFFF,
          startSeq: seq,
        );
        seq = (seq + pkts.length) & 0xFFFF;
        ts = (ts + tsStep) & 0xFFFFFFFF;
        for (final p in pkts) {
          await transceiver.sender.send(p.rawData);
        }
      });
    } else if (state == RTCPeerConnectionState.failed ||
        state == RTCPeerConnectionState.closed ||
        state == RTCPeerConnectionState.disconnected) {
      sub?.cancel();
      sub = null;
    }
  };

  ws.listen((raw) async {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (msg['type']) {
        case 'answer':
          await pc.setRemoteDescription(
            RTCSessionDescription(RTCSdpType.answer, msg['sdp'] as String),
          );
          break;
        case 'candidate':
          final cand = msg['candidate'];
          if (cand == null) break;
          await pc.addIceCandidate(RTCIceCandidate(
            candidate: cand as String,
            sdpMid: msg['sdpMid'] as String?,
            sdpMLineIndex: msg['sdpMLineIndex'] as int?,
          ));
          break;
      }
    } catch (e, st) {
      stderr.writeln('[webrtc] WS error: $e\n$st');
    }
  }, onDone: () async {
    sub?.cancel();
    pc.close();
    stdout.writeln('[webrtc] viewer on $port disconnected');
  }, cancelOnError: true);
}

String _addSendOnlySsrc(String sdp, int ssrc, {required String streamId}) {
  final session = parseSdp(sdp);
  for (final m in session.mediaList) {
    if ((m['type'] as String?) != 'video') continue;
    final ssrcs = (m['ssrcs'] as List?) ?? <Map<String, dynamic>>[];
    final cname = 'rtsp2webrtc-$streamId';
    final track = '$streamId-video';
    ssrcs.add({'id': ssrc, 'attribute': 'cname', 'value': cname});
    ssrcs.add({'id': ssrc, 'attribute': 'msid', 'value': '$streamId $track'});
    m['ssrcs'] = ssrcs;
    break;
  }
  return writeSdp(session);
}

// ---------------------------------------------------------------------------
// RTSP server (RTP/AVP/TCP interleaved, single track, VP8 / RFC 7741)
// ---------------------------------------------------------------------------

Future<void> _runRtspServer(
  InternetAddress ip,
  int port,
  _FrameHub hub,
) async {
  final server = await ServerSocket.bind(ip, port);
  await for (final socket in server) {
    unawaited(_RtspSession(socket, hub).run());
  }
}

/// One TCP connection from an RTSP client (VLC, ffplay, GStreamer, ...).
class _RtspSession {
  final Socket socket;
  final _FrameHub hub;

  static const _streamUrlPath = '/live';
  static const _trackId = 'trackID=1';
  static const _interleavedRtpChannel = 0;
  static const _interleavedRtcpChannel = 1;

  // Built lazily during SETUP.
  String? sessionId;
  StreamSubscription<_EncodedFrame>? _sub;
  var _seq = Random.secure().nextInt(0x10000);
  var _ts = Random.secure().nextInt(0x80000000);
  static const int _tsStep = 90000 ~/ _fps;
  final int _ssrc = Random.secure().nextInt(0xFFFFFFFE) + 1;

  // Buffer for assembling RTSP request lines (everything before PLAY is
  // pure ASCII; once playing the server only writes — it never has to
  // demux interleaved RTCP from the client for this minimal demo).
  final _rxBuf = <int>[];

  _RtspSession(this.socket, this.hub);

  Future<void> run() async {
    final peer = '${socket.remoteAddress.address}:${socket.remotePort}';
    stdout.writeln('[rtsp] client connected: $peer');
    socket.listen(
      _onData,
      onDone: _close,
      onError: (Object e) {
        stderr.writeln('[rtsp] socket error: $e');
        _close();
      },
      cancelOnError: true,
    );
  }

  void _close() {
    _sub?.cancel();
    _sub = null;
    try {
      socket.destroy();
    } catch (_) {}
    stdout.writeln('[rtsp] client disconnected');
  }

  void _onData(Uint8List data) {
    _rxBuf.addAll(data);
    while (true) {
      final end = _findHeaderTerminator(_rxBuf);
      if (end < 0) return;
      final headerBytes = _rxBuf.sublist(0, end);
      _rxBuf.removeRange(0, end + 4);
      final headerText = utf8.decode(headerBytes, allowMalformed: true);
      _handleRequest(headerText);
    }
  }

  static int _findHeaderTerminator(List<int> buf) {
    for (var i = 0; i + 3 < buf.length; i++) {
      if (buf[i] == 0x0d &&
          buf[i + 1] == 0x0a &&
          buf[i + 2] == 0x0d &&
          buf[i + 3] == 0x0a) {
        return i;
      }
    }
    return -1;
  }

  void _handleRequest(String text) {
    final lines = text.split('\r\n');
    if (lines.isEmpty) return;
    final reqLine = lines.first.split(' ');
    if (reqLine.length < 3) return;
    final method = reqLine[0];
    final uri = reqLine[1];

    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      headers[line.substring(0, colon).trim().toLowerCase()] =
          line.substring(colon + 1).trim();
    }
    final cseq = headers['cseq'] ?? '0';

    stdout.writeln('[rtsp] <- $method $uri (CSeq=$cseq)');

    switch (method) {
      case 'OPTIONS':
        _writeReply(cseq, headers: {
          'Public':
              'OPTIONS, DESCRIBE, SETUP, TEARDOWN, PLAY, PAUSE, GET_PARAMETER',
        });
        break;
      case 'DESCRIBE':
        _handleDescribe(cseq, uri);
        break;
      case 'SETUP':
        _handleSetup(cseq, headers);
        break;
      case 'PLAY':
        _handlePlay(cseq);
        break;
      case 'PAUSE':
        _sub?.pause();
        _writeReply(cseq, headers: {'Session': sessionId ?? ''});
        break;
      case 'GET_PARAMETER':
        _writeReply(cseq, headers: {'Session': sessionId ?? ''});
        break;
      case 'TEARDOWN':
        _writeReply(cseq, headers: {'Session': sessionId ?? ''});
        _close();
        break;
      default:
        _writeReply(cseq, status: '405 Method Not Allowed');
    }
  }

  void _handleDescribe(String cseq, String uri) {
    final base = uri.endsWith('/') ? uri : '$uri/';
    final sdp = StringBuffer()
      ..write('v=0\r\n')
      ..write('o=- ${DateTime.now().millisecondsSinceEpoch} 1 IN IP4 '
          '${socket.address.address}\r\n')
      ..write('s=rtsp_to_webrtc\r\n')
      ..write('c=IN IP4 0.0.0.0\r\n')
      ..write('t=0 0\r\n')
      ..write('a=tool:pure_dart_webrtc\r\n')
      ..write('a=range:npt=0-\r\n')
      ..write('m=video 0 RTP/AVP 96\r\n')
      // RFC 7741: VP8 over RTP, dynamic PT, 90 kHz clock.
      ..write('a=rtpmap:96 VP8/90000\r\n')
      ..write('a=framerate:$_fps\r\n')
      ..write('a=control:$base$_trackId\r\n');
    final body = sdp.toString();
    _writeReply(cseq,
        headers: {
          'Content-Base': base,
          'Content-Type': 'application/sdp',
          'Content-Length': '${body.length}',
        },
        body: body);
  }

  void _handleSetup(String cseq, Map<String, String> headers) {
    sessionId ??=
        Random.secure().nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
    // We force interleaved (TCP) transport for this demo regardless of
    // what the client offered — keeps the example single-socket and
    // firewall-friendly. Most clients (VLC, ffplay) accept this.
    _writeReply(cseq, headers: {
      'Session': '$sessionId;timeout=60',
      'Transport': 'RTP/AVP/TCP;unicast;'
          'interleaved=$_interleavedRtpChannel-$_interleavedRtcpChannel'
          ';ssrc=${_ssrc.toRadixString(16).padLeft(8, '0')}',
    });
  }

  void _handlePlay(String cseq) {
    _writeReply(cseq, headers: {
      'Session': sessionId ?? '',
      'Range': 'npt=0.000-',
      'RTP-Info': 'url=rtsp://${socket.address.address}'
          ':${socket.port}$_streamUrlPath/$_trackId'
          ';seq=$_seq;rtptime=$_ts',
    });

    _sub?.cancel();
    _sub = hub.subscribe().listen(_onEncodedFrame);
  }

  void _onEncodedFrame(_EncodedFrame frame) {
    final pkts = packetizeVp8Frame(
      frame: frame.data,
      ssrc: _ssrc,
      timestamp: _ts & 0xFFFFFFFF,
      startSeq: _seq,
    );
    _seq = (_seq + pkts.length) & 0xFFFF;
    _ts = (_ts + _tsStep) & 0xFFFFFFFF;
    for (final p in pkts) {
      _writeInterleaved(_interleavedRtpChannel, p.rawData);
    }
  }

  /// RFC 7826 §14: each interleaved frame is `'$' <ch:1> <len:2 BE> <data>`.
  void _writeInterleaved(int channel, Uint8List rtp) {
    if (rtp.length > 0xFFFF) return; // shouldn't happen with 1200-byte chunks
    final framing = Uint8List(4)
      ..[0] = 0x24
      ..[1] = channel & 0xff;
    ByteData.sublistView(framing).setUint16(2, rtp.length, Endian.big);
    try {
      socket.add(framing);
      socket.add(rtp);
    } catch (e) {
      stderr.writeln('[rtsp] write failed: $e');
      _close();
    }
  }

  void _writeReply(
    String cseq, {
    String status = '200 OK',
    Map<String, String> headers = const {},
    String body = '',
  }) {
    final sb = StringBuffer()
      ..write('RTSP/1.0 $status\r\n')
      ..write('CSeq: $cseq\r\n')
      ..write('Server: pure_dart_webrtc/0.1\r\n');
    headers.forEach((k, v) {
      if (v.isNotEmpty) sb.write('$k: $v\r\n');
    });
    sb.write('\r\n');
    if (body.isNotEmpty) sb.write(body);
    socket.write(sb.toString());
  }
}

// ---------------------------------------------------------------------------
// Browser viewer
// ---------------------------------------------------------------------------

const _demoHtml = r'''
<!doctype html>
<html><head><meta charset="utf-8"><title>rtsp_to_webrtc</title>
<style>
  body{font:14px sans-serif;margin:1em;background:#111;color:#eee}
  video{width:480px;background:#000;border:1px solid #444}
  #log{font-family:monospace;white-space:pre-wrap;background:#000;padding:.5em;height:8em;overflow:auto;margin-top:.5em}
  code{background:#222;padding:0 .25em}
</style></head><body>
<h2>rtsp_to_webrtc (pure_dart_webrtc)</h2>
<p>Same source is also reachable as RTSP at
<code>rtsp://&lt;host&gt;:8554/live</code> — try
<code>ffplay -rtsp_transport tcp rtsp://&lt;host&gt;:8554/live</code>.</p>
<button id="go">Watch</button>
<div><video id="v" autoplay playsinline muted></video></div>
<div id="log"></div>
<script>
const log = (...a) => {
  document.getElementById('log').textContent += a.join(' ') + '\n';
};
document.getElementById('go').onclick = async () => {
  const ws = new WebSocket(`ws://${location.host}/ws`);
  await new Promise(r => ws.onopen = r);
  const pc = new RTCPeerConnection();
  pc.addTransceiver('video', {direction:'recvonly'});
  pc.ontrack = (e) => {
    document.getElementById('v').srcObject = e.streams[0] ||
        new MediaStream([e.track]);
    log('ontrack', e.track.kind);
  };
  pc.oniceconnectionstatechange = () => log('ice:', pc.iceConnectionState);
  pc.onicecandidate = (e) => {
    if (!e.candidate) return ws.send(JSON.stringify(
      {type:'candidate', candidate:null}));
    ws.send(JSON.stringify({
      type:'candidate', candidate:e.candidate.candidate,
      sdpMid:e.candidate.sdpMid, sdpMLineIndex:e.candidate.sdpMLineIndex,
    }));
  };
  ws.onmessage = async (ev) => {
    const m = JSON.parse(ev.data);
    if (m.type === 'offer') {
      await pc.setRemoteDescription({type:'offer', sdp:m.sdp});
      const ans = await pc.createAnswer();
      await pc.setLocalDescription(ans);
      ws.send(JSON.stringify({type:'answer', sdp:ans.sdp}));
      log('sent answer');
    } else if (m.type === 'candidate' && m.candidate) {
      try { await pc.addIceCandidate(m); } catch (e) { log('ice err:', e); }
    }
  };
};
</script></body></html>
''';
