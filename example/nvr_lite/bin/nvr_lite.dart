// nvr_lite — minimal Network Video Recorder.
//
// For each camera:
//   * pull H.264 over RTSP (reuses `rtsp_pure` from the
//     rtsp_camera_to_webrtc example),
//   * write a rolling series of Annex-B `.h264` segments to
//     `<storage>/<cam-name>/<UTC-iso>.h264`,
//   * delete segments older than `--retain` hours,
//   * also fan the same stream out to a browser viewer over WebRTC
//     (one tile per camera).
//
// The resulting `.h264` files are raw Annex-B bitstreams. They play
// directly in mpv / VLC / ffplay; mux to MP4 with:
//   ffmpeg -framerate 30 -i FILE.h264 -c copy FILE.mp4
//
// Usage:
//   dart run bin/nvr_lite.dart \
//       --ip 192.168.56.1 \
//       --storage ./recordings \
//       --segment 60 --retain 24 \
//       --cam Front=rtsp://... \
//       --cam Back=rtsp://...

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:pure_dart_webrtc/h264.dart';
import 'package:pure_dart_webrtc/signal/sdp_v2.dart' as sdpv2;
import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:pure_dart_webrtc_rtsp_camera_to_webrtc_example/rtsp_pure.dart';

class _Cam {
  _Cam(this.name, this.url);
  final String name;
  final String url;
}

Future<int> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('ip', defaultsTo: '127.0.0.1')
    ..addOption('http-port', defaultsTo: '8080')
    ..addOption('rtp-port', defaultsTo: '50300')
    ..addOption('storage', defaultsTo: './recordings')
    ..addOption('segment', defaultsTo: '60', help: 'segment seconds')
    ..addOption('retain', defaultsTo: '24', help: 'retention hours')
    ..addOption('profile-level-id', defaultsTo: '42e01f')
    ..addMultiOption('cam', abbr: 'c', help: 'NAME=rtsp://...');

  late final ArgResults o;
  try {
    o = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n${parser.usage}');
    return 64;
  }

  final cams = <_Cam>[];
  for (final s in (o['cam'] as List<String>)) {
    final eq = s.indexOf('=');
    if (eq <= 0) {
      stderr.writeln('--cam needs NAME=URL: $s');
      return 64;
    }
    cams.add(_Cam(s.substring(0, eq).trim(), s.substring(eq + 1).trim()));
  }
  for (final url in o.rest) {
    cams.add(_Cam('cam${cams.length}', url));
  }
  if (cams.isEmpty) {
    stderr.writeln('At least one --cam needed.\n${parser.usage}');
    return 64;
  }

  final ip = InternetAddress(o['ip'] as String);
  final httpPort = int.parse(o['http-port'] as String);
  final rtpPort = int.parse(o['rtp-port'] as String);
  final storage = Directory(o['storage'] as String);
  await storage.create(recursive: true);
  final segSecs = int.parse(o['segment'] as String);
  final retainHrs = int.parse(o['retain'] as String);
  final profileLevelId = o['profile-level-id'] as String;

  // Per-camera ingest + recorder.
  final hubs = <AuHub>[];
  for (final cam in cams) {
    final hub = AuHub(name: cam.name);
    hubs.add(hub);
    unawaited(
        RtspClient(url: cam.url, hub: hub, logTag: cam.name).runForever());
    final recorder = _SegmentRecorder(
      camName: cam.name,
      root: storage,
      hub: hub,
      segmentSeconds: segSecs,
      retentionHours: retainHrs,
    );
    unawaited(recorder.run());
  }

  // Browser live-view.
  unawaited(_runHttpServer(
    ip: ip,
    port: httpPort,
    rtpBasePort: rtpPort,
    cams: cams,
    hubs: hubs,
    profileLevelId: profileLevelId,
    storage: storage,
  ));

  stdout.writeln('[nvr] http://${ip.address}:$httpPort  '
      'storage=${storage.path}  segment=${segSecs}s  retain=${retainHrs}h');
  await Completer<void>().future;
  return 0;
}

// ---------------------------------------------------------------------------
// Recorder
// ---------------------------------------------------------------------------

class _SegmentRecorder {
  _SegmentRecorder({
    required this.camName,
    required this.root,
    required this.hub,
    required this.segmentSeconds,
    required this.retentionHours,
  });

  final String camName;
  final Directory root;
  final AuHub hub;
  final int segmentSeconds;
  final int retentionHours;

  Future<void> run() async {
    final dir = Directory('${root.path}/$camName')..createSync(recursive: true);
    IOSink? sink;
    DateTime segStart = DateTime.fromMillisecondsSinceEpoch(0);
    String segPath = '';
    int segBytes = 0;

    Future<void> rotate(AccessUnit auForFirstFrame) async {
      // Only start a new segment on a keyframe so the file is playable.
      if (sink != null) {
        await sink!.flush();
        await sink!.close();
        stdout.writeln('[nvr/$camName] closed $segPath ($segBytes bytes)');
      }
      segStart = DateTime.now().toUtc();
      final ts =
          segStart.toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      segPath = '${dir.path}/$ts.h264';
      sink = File(segPath).openWrite();
      segBytes = 0;
      // Always lead with SPS+PPS+IDR so the file can be decoded standalone.
      final sps = hub.sps;
      final pps = hub.pps;
      if (sps != null) segBytes += _writeNalu(sink!, sps);
      if (pps != null) segBytes += _writeNalu(sink!, pps);
      for (final n in auForFirstFrame.nalus) {
        segBytes += _writeNalu(sink!, n);
      }
    }

    void writeAu(AccessUnit au) {
      if (sink == null) return;
      for (final n in au.nalus) {
        segBytes += _writeNalu(sink!, n);
      }
    }

    final retentionTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _prune(dir, retentionHours);
    });

    await for (final au in hub.subscribe()) {
      final now = DateTime.now().toUtc();
      final elapsed = now.difference(segStart).inSeconds;
      if (sink == null && au.hasKeyframeSlice) {
        await rotate(au);
        continue;
      }
      if (au.hasKeyframeSlice && elapsed >= segmentSeconds) {
        await rotate(au);
        continue;
      }
      writeAu(au);
    }
    retentionTimer.cancel();
  }

  static int _writeNalu(IOSink s, Uint8List nalu) {
    s.add(const [0, 0, 0, 1]);
    s.add(nalu);
    return 4 + nalu.length;
  }

  static void _prune(Directory dir, int retentionHours) {
    final cutoff = DateTime.now().subtract(Duration(hours: retentionHours));
    for (final f in dir.listSync().whereType<File>()) {
      try {
        if (f.statSync().modified.isBefore(cutoff)) {
          f.deleteSync();
        }
      } catch (_) {}
    }
  }
}

// ---------------------------------------------------------------------------
// HTTP + WebRTC live view (mirrors multicam_pure_to_webrtc + /api endpoints)
// ---------------------------------------------------------------------------

int _nextWebrtcPortOffset = 0;

Future<void> _runHttpServer({
  required InternetAddress ip,
  required int port,
  required int rtpBasePort,
  required List<_Cam> cams,
  required List<AuHub> hubs,
  required String profileLevelId,
  required Directory storage,
}) async {
  final server = await HttpServer.bind(ip, port);
  await for (final req in server) {
    try {
      final p = req.uri.path;
      if (p == '/' || p == '/index.html') {
        req.response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        req.response.write(_renderHtml(cams));
        await req.response.close();
      } else if (p == '/api/recordings') {
        await _serveRecordingList(req, storage, cams);
      } else if (p.startsWith('/recordings/')) {
        await _serveRecordingFile(req, storage, p);
      } else if (p == '/ws') {
        final ws = await WebSocketTransformer.upgrade(req);
        unawaited(_handleViewer(
          ws: ws,
          ip: ip,
          basePort: rtpBasePort,
          cams: cams,
          hubs: hubs,
          profileLevelId: profileLevelId,
        ));
      } else {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      }
    } catch (e) {
      stderr.writeln('[http] $e');
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }
}

Future<void> _serveRecordingList(
    HttpRequest req, Directory storage, List<_Cam> cams) async {
  final out = <String, List<Map<String, Object>>>{};
  for (final c in cams) {
    final dir = Directory('${storage.path}/${c.name}');
    if (!dir.existsSync()) {
      out[c.name] = [];
      continue;
    }
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    out[c.name] = [
      for (final f in files)
        {
          'name': f.uri.pathSegments.last,
          'size': f.lengthSync(),
          'mtime': f.statSync().modified.toUtc().toIso8601String(),
        }
    ];
  }
  req.response.headers.contentType = ContentType.json;
  req.response.write(jsonEncode(out));
  await req.response.close();
}

Future<void> _serveRecordingFile(
    HttpRequest req, Directory storage, String path) async {
  final rel = path.substring('/recordings/'.length);
  // Block path traversal.
  if (rel.contains('..') || rel.contains('\\')) {
    req.response.statusCode = HttpStatus.forbidden;
    await req.response.close();
    return;
  }
  final f = File('${storage.path}/$rel');
  if (!f.existsSync()) {
    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
    return;
  }
  req.response.headers.contentType = ContentType('video', 'h264');
  req.response.headers.set('Content-Disposition',
      'attachment; filename="${f.uri.pathSegments.last}"');
  await f.openRead().pipe(req.response);
}

Future<void> _handleViewer({
  required WebSocket ws,
  required InternetAddress ip,
  required int basePort,
  required List<_Cam> cams,
  required List<AuHub> hubs,
  required String profileLevelId,
}) async {
  final port = basePort + _nextWebrtcPortOffset++;
  final pc = RTCPeerConnection(RTCConfiguration(
    defaultVideoCodecs: [H264Codec(profileLevelId: profileLevelId)],
  ));
  final txs = <RTCRtpTransceiver>[];
  final ssrcs = <int>[];
  for (var i = 0; i < cams.length; i++) {
    txs.add(pc.addTransceiver(
      trackOrKind: MediaKind.video,
      direction: RTCRtpTransceiverDirection.sendonly,
    ));
    ssrcs.add(Random.secure().nextInt(0xFFFFFFFE) + 1);
  }
  await pc.bind(ip, port, announceAddress: ip);

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
  final sdp = _addPerCameraSsrcs(offer.sdp, cams, ssrcs);
  await pc.setLocalDescription(RTCSessionDescription(RTCSdpType.offer, sdp));
  ws.add(jsonEncode({
    'type': 'offer',
    'sdp': sdp,
    'cams': [for (var i = 0; i < cams.length; i++) cams[i].name],
  }));

  final subs = <StreamSubscription<AccessUnit>>[];
  pc.onConnectionStateChange = (state) {
    if (state == RTCPeerConnectionState.connected && subs.isEmpty) {
      for (var i = 0; i < cams.length; i++) {
        final tx = txs[i];
        final ssrc = ssrcs[i];
        final hub = hubs[i];
        var pt = 102;
        for (final c in tx.codecs) {
          if (c is H264Codec) {
            pt = c.payloadType;
            break;
          }
        }
        var seq = Random.secure().nextInt(0x10000);
        final tsBase = Random.secure().nextInt(0x80000000);
        var n = 0;
        subs.add(hub.subscribe().listen((au) async {
          final ts = (tsBase + n * 3000) & 0xffffffff;
          n++;
          final pkts = packetizeH264AccessUnit(
            nalus: au.nalus,
            ssrc: ssrc,
            timestamp: ts,
            startSeq: seq,
            payloadType: pt,
          );
          seq = (seq + pkts.length) & 0xffff;
          for (final p in pkts) {
            await tx.sender.send(p.rawData);
          }
        }));
      }
    } else if (state == RTCPeerConnectionState.failed ||
        state == RTCPeerConnectionState.closed ||
        state == RTCPeerConnectionState.disconnected) {
      for (final s in subs) {
        s.cancel();
      }
      subs.clear();
    }
  };

  ws.listen((raw) async {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (msg['type']) {
        case 'answer':
          await pc.setRemoteDescription(
              RTCSessionDescription(RTCSdpType.answer, msg['sdp'] as String));
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
    } catch (e) {
      stderr.writeln('[ws] $e');
    }
  }, onDone: () {
    for (final s in subs) {
      s.cancel();
    }
    pc.close();
  });
}

String _addPerCameraSsrcs(String sdp, List<_Cam> cams, List<int> ssrcs) {
  final session = sdpv2.parseSdp(sdp);
  var idx = 0;
  for (final m in session.mediaList) {
    if ((m['type'] as String?) != 'video') continue;
    if (idx >= cams.length) break;
    final cam = cams[idx];
    final ssrc = ssrcs[idx];
    idx++;
    final list = (m['ssrcs'] as List?) ?? <Map<String, dynamic>>[];
    list.add({'id': ssrc, 'attribute': 'cname', 'value': 'nvr-${cam.name}'});
    list.add({
      'id': ssrc,
      'attribute': 'msid',
      'value': '${cam.name} ${cam.name}-video',
    });
    m['ssrcs'] = list;
  }
  return sdpv2.writeSdp(session);
}

String _renderHtml(List<_Cam> cams) {
  final tiles = StringBuffer();
  for (final c in cams) {
    tiles.write('<div class="tile" data-cam="${c.name}">'
        '<h3>${c.name}</h3>'
        '<video id="v-${c.name}" autoplay playsinline muted></video>'
        '<details><summary>recordings</summary>'
        '<ul id="rec-${c.name}"></ul></details></div>');
  }
  return _htmlShell.replaceAll('<!--TILES-->', tiles.toString());
}

const _htmlShell = r'''
<!doctype html><html><head><meta charset="utf-8"><title>nvr_lite</title>
<style>
  body{font:14px sans-serif;background:#111;color:#eee;margin:1em}
  .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(360px,1fr));gap:.75em}
  .tile{background:#000;border:1px solid #333;padding:.4em}
  .tile h3{margin:.2em 0 .4em;font-size:13px;color:#9cf}
  video{width:100%;background:#000;display:block}
  details{margin-top:.4em;font-size:12px;color:#bbb}
  ul{margin:.3em 0 0 1em;padding:0}
  li{list-style:none;font-family:monospace}
  a{color:#9cf}
  #log{font-family:monospace;white-space:pre-wrap;background:#000;padding:.5em;height:7em;overflow:auto;margin-top:.75em;font-size:12px}
  button{font:14px sans-serif;padding:.4em 1em;margin-bottom:.5em}
</style></head><body>
<h2>nvr_lite</h2>
<button id="go">Connect live</button>
<button id="refresh">Refresh recordings</button>
<div class="grid"><!--TILES--></div>
<div id="log"></div>
<script>
const log=(...a)=>{document.getElementById('log').textContent+=a.join(' ')+'\n'};
async function loadRecordings(){
  const res = await fetch('/api/recordings').then(r=>r.json());
  for(const cam in res){
    const ul = document.getElementById('rec-'+cam);
    if(!ul) continue;
    ul.innerHTML='';
    for(const f of res[cam]){
      const li=document.createElement('li');
      const a=document.createElement('a');
      a.href='/recordings/'+cam+'/'+f.name;
      a.textContent=f.name+' ('+(f.size/1024/1024).toFixed(1)+' MB)';
      li.appendChild(a); ul.appendChild(li);
    }
  }
}
document.getElementById('refresh').onclick=loadRecordings;
loadRecordings();
document.getElementById('go').onclick=async()=>{
  const ws=new WebSocket(`ws://${location.host}/ws`);
  await new Promise(r=>ws.onopen=r);
  const pc=new RTCPeerConnection();
  pc.ontrack=e=>{const v=document.getElementById('v-'+e.streams[0].id);if(v)v.srcObject=e.streams[0]};
  pc.oniceconnectionstatechange=()=>log('ice:',pc.iceConnectionState);
  pc.onicecandidate=e=>{if(!e.candidate)return ws.send(JSON.stringify({type:'candidate',candidate:null}));ws.send(JSON.stringify({type:'candidate',candidate:e.candidate.candidate,sdpMid:e.candidate.sdpMid,sdpMLineIndex:e.candidate.sdpMLineIndex}))};
  ws.onmessage=async ev=>{const m=JSON.parse(ev.data);if(m.type==='offer'){for(let i=0;i<m.cams.length;i++)pc.addTransceiver('video',{direction:'recvonly'});await pc.setRemoteDescription({type:'offer',sdp:m.sdp});const ans=await pc.createAnswer();await pc.setLocalDescription(ans);ws.send(JSON.stringify({type:'answer',sdp:ans.sdp}));log('answered',m.cams.length,'cams')}else if(m.type==='candidate'&&m.candidate){try{await pc.addIceCandidate(m)}catch(e){log('ice err:',e)}}};
};
</script></body></html>
''';
