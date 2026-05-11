// whip_server — minimal pure-Dart WHIP + WHEP server.
//
//   POST /whip      — publisher ingest (WHIP, RFC 9725)
//   POST /whep      — viewer playback (WHEP, RFC 9725)
//   DELETE <Location>  — tear down a session
//   GET  /          — built-in HTML player (for smoke testing)
//
// Topology: one publisher → N viewers. The publisher's incoming RTP
// packets are forwarded to every viewer's sender, with the SSRC field
// rewritten to match what we announced in that viewer's SDP answer.
//
// Codec: VP8 only. (Trivial to extend — the forwarder is codec-agnostic
// once the SDP negotiates the right PT.)
//
// Run:
//   dart run bin/whip_server.dart --ip 192.168.56.1
//   # then publish:
//   dart run ../whip_publisher/bin/whip_publisher.dart \
//     --url http://192.168.56.1:8080/whip --file ../../example.ivf
//   # and open http://192.168.56.1:8080/ in a browser to view.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:pure_dart_webrtc/signal/sdp_v2.dart' as sdpv2;
import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

Future<int> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('ip', defaultsTo: '127.0.0.1')
    ..addOption('http-port', defaultsTo: '8080')
    ..addOption('rtp-port',
        defaultsTo: '50200',
        help: 'Base UDP port; each PC takes the next free port');

  late final ArgResults opts;
  try {
    opts = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n${parser.usage}');
    return 64;
  }

  final ip = InternetAddress(opts['ip'] as String);
  final httpPort = int.parse(opts['http-port'] as String);
  final rtpBase = int.parse(opts['rtp-port'] as String);

  final hub = _Hub();
  final server = _Server(ip: ip, rtpBase: rtpBase, hub: hub);

  final http = await HttpServer.bind(ip, httpPort);
  stdout.writeln('[whip_server] http://${ip.address}:$httpPort');
  stdout.writeln('  WHIP ingest:   POST http://${ip.address}:$httpPort/whip');
  stdout.writeln('  WHEP playback: POST http://${ip.address}:$httpPort/whep');
  stdout.writeln('  built-in player: http://${ip.address}:$httpPort/');

  await for (final req in http) {
    try {
      await server.handle(req);
    } catch (e, st) {
      stderr.writeln('[http] $e\n$st');
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Hub: routes RTP packets from the publisher to every viewer.
// ---------------------------------------------------------------------------

class _Hub {
  final _viewers = <_Viewer>{};

  void addViewer(_Viewer v) => _viewers.add(v);
  void removeViewer(_Viewer v) => _viewers.remove(v);
  int get viewerCount => _viewers.length;

  /// Forward a publisher RTP packet to every viewer (rewriting SSRC).
  void forward(Uint8List rtp) {
    for (final v in _viewers.toList()) {
      v.send(rtp);
    }
  }
}

class _Viewer {
  _Viewer({required this.id, required this.tx, required this.ssrc});
  final String id;
  final RTCRtpTransceiver tx;
  final int ssrc;

  void send(Uint8List rtp) {
    if (rtp.length < 12) return;
    // Copy + rewrite SSRC bytes 8-11 (big-endian) so the viewer's
    // browser sees the SSRC we announced in the SDP answer.
    final out = Uint8List.fromList(rtp);
    final bd = ByteData.sublistView(out);
    bd.setUint32(8, ssrc, Endian.big);
    // Fire-and-forget; sender.send returns false silently if not keyed.
    tx.sender.send(out);
  }
}

// ---------------------------------------------------------------------------
// HTTP server with WHIP + WHEP endpoints.
// ---------------------------------------------------------------------------

class _Server {
  _Server({required this.ip, required this.rtpBase, required this.hub});
  final InternetAddress ip;
  final int rtpBase;
  final _Hub hub;

  int _nextPort = 0;
  RTCPeerConnection? _publisherPc;
  String? _publisherResource;

  // Viewer resources by id.
  final _viewerPcs = <String, RTCPeerConnection>{};
  final _viewerObjs = <String, _Viewer>{};

  Future<void> handle(HttpRequest req) async {
    final path = req.uri.path;
    if (req.method == 'GET' && (path == '/' || path == '/index.html')) {
      req.response.headers.contentType =
          ContentType('text', 'html', charset: 'utf-8');
      req.response.write(_playerHtml);
      await req.response.close();
      return;
    }
    if (req.method == 'POST' && path == '/whip') {
      await _onWhip(req);
      return;
    }
    if (req.method == 'POST' && path == '/whep') {
      await _onWhep(req);
      return;
    }
    if (req.method == 'DELETE' && path.startsWith('/resource/')) {
      await _onDelete(req, path.substring('/resource/'.length));
      return;
    }
    if (req.method == 'OPTIONS') {
      _cors(req.response);
      req.response.statusCode = HttpStatus.noContent;
      await req.response.close();
      return;
    }
    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }

  void _cors(HttpResponse r) {
    r.headers.set('Access-Control-Allow-Origin', '*');
    r.headers.set('Access-Control-Allow-Methods', 'POST, DELETE, OPTIONS');
    r.headers.set('Access-Control-Allow-Headers',
        'Content-Type, Authorization, If-Match');
    r.headers.set('Access-Control-Expose-Headers', 'Location, ETag');
  }

  // ---- WHIP ingest --------------------------------------------------

  Future<void> _onWhip(HttpRequest req) async {
    final offer = await utf8.decoder.bind(req).join();
    if (_publisherPc != null) {
      stderr.writeln('[whip] replacing existing publisher');
      try {
        _publisherPc!.close();
      } catch (_) {}
      _publisherPc = null;
    }
    final port = rtpBase + _nextPort++;
    final pc = RTCPeerConnection(RTCConfiguration(
      defaultVideoCodecs: [Vp8Codec()],
    ));
    _publisherPc = pc;

    pc.onTrack = (e) {
      stdout.writeln('[whip] publisher track: ${e.track.kind}');
      e.receiver.onRtp.listen(hub.forward);
    };
    pc.onConnectionStateChange = (s) {
      stdout.writeln('[whip] publisher state: $s');
      if (s == RTCPeerConnectionState.failed ||
          s == RTCPeerConnectionState.closed ||
          s == RTCPeerConnectionState.disconnected) {
        if (identical(_publisherPc, pc)) _publisherPc = null;
      }
    };

    await pc.bind(ip, port, announceAddress: ip);

    final cands = <RTCIceCandidate>[];
    final gathered = Completer<void>();
    pc.onIceCandidate = (c) {
      if (c == null) {
        if (!gathered.isCompleted) gathered.complete();
        return;
      }
      cands.add(c);
    };

    await pc.setRemoteDescription(
      RTCSessionDescription(RTCSdpType.offer, offer),
    );
    final ans = await pc.createAnswer();
    await pc.setLocalDescription(ans);
    await gathered.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    final ansSdp = _injectCandidates(ans.sdp, cands);

    final id = _newId();
    _publisherResource = id;
    _writeSdpResponse(req.response, ansSdp, id);
    stdout.writeln('[whip] publisher resource=$id, UDP $port');
  }

  // ---- WHEP playback ------------------------------------------------

  Future<void> _onWhep(HttpRequest req) async {
    final offer = await utf8.decoder.bind(req).join();
    final port = rtpBase + _nextPort++;
    final pc = RTCPeerConnection(RTCConfiguration(
      defaultVideoCodecs: [Vp8Codec()],
    ));

    pc.onConnectionStateChange = (s) {
      stdout.writeln('[whep] viewer state: $s');
    };

    await pc.bind(ip, port, announceAddress: ip);

    final cands = <RTCIceCandidate>[];
    final gathered = Completer<void>();
    pc.onIceCandidate = (c) {
      if (c == null) {
        if (!gathered.isCompleted) gathered.complete();
        return;
      }
      cands.add(c);
    };

    await pc.setRemoteDescription(
      RTCSessionDescription(RTCSdpType.offer, offer),
    );

    // Find the (first) video transceiver the viewer asked us to send on.
    RTCRtpTransceiver? videoTx;
    for (final t in pc.getTransceivers()) {
      if (t.kind == MediaKind.video) {
        videoTx = t;
        break;
      }
    }
    if (videoTx == null) {
      req.response.statusCode = HttpStatus.badRequest;
      req.response.write('no video m= section in WHEP offer');
      await req.response.close();
      return;
    }

    final ssrc = Random.secure().nextInt(0xFFFFFFFE) + 1;
    final id = _newId();
    final ans = await pc.createAnswer();
    final ansWithSsrc = _withSendOnlySsrc(ans.sdp, ssrc, streamId: 'whep-$id');
    await pc.setLocalDescription(
      RTCSessionDescription(RTCSdpType.answer, ansWithSsrc),
    );
    await gathered.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    final ansSdp = _injectCandidates(ansWithSsrc, cands);

    final viewer = _Viewer(id: id, tx: videoTx, ssrc: ssrc);
    hub.addViewer(viewer);
    _viewerPcs[id] = pc;
    _viewerObjs[id] = viewer;

    pc.onConnectionStateChange = (s) {
      stdout.writeln('[whep/$id] state: $s');
      if (s == RTCPeerConnectionState.failed ||
          s == RTCPeerConnectionState.closed ||
          s == RTCPeerConnectionState.disconnected) {
        hub.removeViewer(viewer);
        _viewerPcs.remove(id);
        _viewerObjs.remove(id);
      }
    };

    _writeSdpResponse(req.response, ansSdp, id);
    stdout.writeln('[whep] viewer resource=$id, UDP $port '
        '(${hub.viewerCount} viewer(s))');
  }

  // ---- DELETE -------------------------------------------------------

  Future<void> _onDelete(HttpRequest req, String id) async {
    if (id == _publisherResource) {
      try {
        _publisherPc?.close();
      } catch (_) {}
      _publisherPc = null;
      _publisherResource = null;
      stdout.writeln('[whip] publisher $id deleted');
    } else if (_viewerPcs.containsKey(id)) {
      try {
        _viewerPcs.remove(id)?.close();
      } catch (_) {}
      final v = _viewerObjs.remove(id);
      if (v != null) hub.removeViewer(v);
      stdout.writeln('[whep] viewer $id deleted');
    } else {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    _cors(req.response);
    req.response.statusCode = HttpStatus.ok;
    await req.response.close();
  }

  void _writeSdpResponse(HttpResponse r, String sdp, String id) {
    _cors(r);
    r.statusCode = HttpStatus.created;
    r.headers.contentType = ContentType('application', 'sdp');
    r.headers.set('Location', '/resource/$id');
    r.write(sdp);
    r.close();
  }

  String _newId() {
    final b = Random.secure();
    return List.generate(16, (_) => b.nextInt(16).toRadixString(16)).join();
  }
}

// ---------------------------------------------------------------------------
// SDP helpers (shared with whip_publisher in spirit)
// ---------------------------------------------------------------------------

String _withSendOnlySsrc(String sdp, int ssrc, {required String streamId}) {
  final session = sdpv2.parseSdp(sdp);
  for (final m in session.mediaList) {
    if ((m['type'] as String?) != 'video') continue;
    final list = (m['ssrcs'] as List?) ?? <Map<String, dynamic>>[];
    list.add({'id': ssrc, 'attribute': 'cname', 'value': 'whep-server'});
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

// ---------------------------------------------------------------------------
// Built-in WHEP player (HTML)
// ---------------------------------------------------------------------------

const _playerHtml = r'''
<!doctype html>
<html><head><meta charset="utf-8"><title>WHEP player</title>
<style>
  body{font:14px sans-serif;background:#111;color:#eee;margin:1em}
  video{width:100%;max-width:960px;background:#000;display:block;margin:.5em 0}
  #log{font-family:monospace;white-space:pre-wrap;background:#000;padding:.5em;height:10em;overflow:auto}
  button{font:14px sans-serif;padding:.4em 1em}
</style></head><body>
<h2>WHEP player</h2>
<button id="go">Play</button>
<button id="stop" disabled>Stop</button>
<video id="v" autoplay playsinline muted controls></video>
<div id="log"></div>
<script>
const log = (...a) => {
  const l = document.getElementById('log');
  l.textContent += a.join(' ') + '\n';
  l.scrollTop = l.scrollHeight;
};
let pc, resourceUrl;
document.getElementById('go').onclick = async () => {
  document.getElementById('go').disabled = true;
  pc = new RTCPeerConnection();
  pc.ontrack = (e) => {
    log('ontrack', e.track.kind);
    document.getElementById('v').srcObject = e.streams[0];
  };
  pc.oniceconnectionstatechange = () => log('ice:', pc.iceConnectionState);
  pc.addTransceiver('video', {direction:'recvonly'});
  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  // Wait for ICE gathering — simplest WHEP clients don't trickle.
  await new Promise(r => {
    if (pc.iceGatheringState === 'complete') return r();
    pc.addEventListener('icegatheringstatechange', () => {
      if (pc.iceGatheringState === 'complete') r();
    });
  });
  const resp = await fetch('/whep', {
    method:'POST',
    headers:{'Content-Type':'application/sdp'},
    body: pc.localDescription.sdp,
  });
  if (resp.status !== 201) {
    log('WHEP failed', resp.status, await resp.text());
    return;
  }
  resourceUrl = resp.headers.get('Location');
  log('resource', resourceUrl);
  const ans = await resp.text();
  await pc.setRemoteDescription({type:'answer', sdp:ans});
  document.getElementById('stop').disabled = false;
};
document.getElementById('stop').onclick = async () => {
  document.getElementById('stop').disabled = true;
  if (resourceUrl) await fetch(resourceUrl, {method:'DELETE'}).catch(()=>{});
  if (pc) pc.close();
  document.getElementById('go').disabled = false;
};
</script></body></html>
''';
