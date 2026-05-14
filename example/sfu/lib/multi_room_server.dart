// Main-isolate router for the multi-room SFU.
//
// Spawns N worker isolates (each running [roomWorkerEntry]), tracks
// their HTTP ports, and exposes a discovery endpoint
// `GET /room/:id/locate` that hashes the room id to a worker and
// returns its WebSocket URL. Clients connect directly to the worker.
//
// See [MULTI_ROOM_ARCHITECTURE.md](../MULTI_ROOM_ARCHITECTURE.md).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'room_worker.dart';

/// Configuration for [runMultiRoomServer]. Plain value object so it can
/// be partially captured into [RoomWorkerInit] before isolate spawn.
class MultiRoomServerConfig {
  /// Address every HTTP / UDP socket binds on.
  final String ip;

  /// Main router HTTP port. Workers listen on separate, OS-picked ports.
  final int routerPort;

  /// Address advertised in `/room/:id/locate` and in worker ICE
  /// candidates. When [ip] is a wildcard, picks the host's first
  /// non-loopback IPv4.
  final String? announceIp;

  /// How many worker isolates to spawn. Defaults to
  /// [Platform.numberOfProcessors].
  final int workerCount;

  /// Optional shared bearer for `/ws/...` upgrades. Forwarded into every
  /// worker.
  final String? authToken;

  /// Per-worker hard cap on rooms.
  final int maxRoomsPerWorker;

  /// Per-room hard cap on participants.
  final int maxParticipantsPerRoom;

  /// Per-receiver outbound queue cap (bytes).
  final int maxInFlightBytesPerReceiver;

  /// Forwarded to every [BasicSfu] the workers create.
  final int maxAudioForwarded;
  final int maxVideoForwarded;
  final bool nackEnabled;

  /// Print one line per worker event.
  final bool verbose;

  /// Idle-room reaper config, forwarded to workers.
  final Duration roomIdleTimeout;
  final Duration roomIdleSweepInterval;

  const MultiRoomServerConfig({
    this.ip = '0.0.0.0',
    this.routerPort = 8080,
    this.announceIp,
    int? workerCount,
    this.authToken,
    this.maxRoomsPerWorker = 0,
    this.maxParticipantsPerRoom = 0,
    this.maxInFlightBytesPerReceiver = 0,
    this.maxAudioForwarded = 3,
    this.maxVideoForwarded = -1,
    this.nackEnabled = false,
    this.verbose = false,
    this.roomIdleTimeout = const Duration(minutes: 5),
    this.roomIdleSweepInterval = const Duration(minutes: 1),
  }) : workerCount = workerCount ?? 0; // 0 → defer to Platform at runtime.
}

/// Handle returned by [runMultiRoomServer]. Holds the bound HTTP server
/// and every spawned worker isolate so callers (and tests) can shut the
/// whole thing down cleanly.
class MultiRoomServerHandle {
  final HttpServer router;
  final List<_WorkerHandle> _workers;

  MultiRoomServerHandle._(this.router, this._workers);

  int get port => router.port;
  List<int> get workerPorts => List.unmodifiable(_workers.map((w) => w.port));

  Future<void> close() async {
    for (final w in _workers) {
      w.control.send(const RoomWorkerShutdown());
    }
    await router.close(force: true);
    // Give workers a beat to shut down their HTTP servers cleanly, then
    // kill anything still alive.
    await Future.delayed(const Duration(milliseconds: 200));
    for (final w in _workers) {
      w.isolate.kill(priority: Isolate.immediate);
    }
  }
}

class _WorkerHandle {
  final String label;
  final Isolate isolate;
  int port; // mutable: respawn writes a new port here
  SendPort control;

  // Latest load report (purely for /health aggregation).
  int rooms = 0;
  int participants = 0;

  _WorkerHandle({
    required this.label,
    required this.isolate,
    required this.port,
    required this.control,
  });
}

/// Boot the full multi-room stack. Returns once every worker isolate has
/// reported its bound port and the router HTTP socket is listening.
Future<MultiRoomServerHandle> runMultiRoomServer(
    MultiRoomServerConfig cfg) async {
  final workerCount =
      cfg.workerCount > 0 ? cfg.workerCount : Platform.numberOfProcessors;

  String advertised;
  final isWildcard = cfg.ip == '0.0.0.0' || cfg.ip == '::' || cfg.ip.isEmpty;
  if (cfg.announceIp != null) {
    advertised = cfg.announceIp!;
  } else if (isWildcard) {
    advertised = await _firstNonLoopbackIPv4() ?? '127.0.0.1';
  } else {
    advertised = cfg.ip;
  }

  final workers = <_WorkerHandle>[];
  for (var i = 0; i < workerCount; i++) {
    final w = await _spawnWorker(cfg, advertised, i);
    workers.add(w);
  }

  final router = await HttpServer.bind(cfg.ip, cfg.routerPort);
  unawaited(_serve(router, advertised, workers, cfg));

  if (cfg.verbose) {
    final isWildcardBind =
        cfg.ip == '0.0.0.0' || cfg.ip == '::' || cfg.ip.isEmpty;
    final routerHost = isWildcardBind ? 'localhost' : cfg.ip;
    // ignore: avoid_print
    print('[router] listening on $routerHost:${router.port}'
        '${isWildcardBind ? ' (bind=${cfg.ip})' : ''} '
        '(advertise=$advertised, workers=$workerCount, '
        'ports=${workers.map((w) => w.port).toList()})');
  }

  return MultiRoomServerHandle._(router, workers);
}

/// Spawn a single worker isolate and wait for its [RoomWorkerReady]
/// handshake before returning.
Future<_WorkerHandle> _spawnWorker(
    MultiRoomServerConfig cfg, String advertised, int index) async {
  final receive = ReceivePort();
  final init = RoomWorkerInit(
    ip: cfg.ip,
    port: 0, // OS picks
    announceIp: advertised,
    authToken: cfg.authToken,
    maxRoomsPerWorker: cfg.maxRoomsPerWorker,
    maxParticipantsPerRoom: cfg.maxParticipantsPerRoom,
    maxInFlightBytesPerReceiver: cfg.maxInFlightBytesPerReceiver,
    maxAudioForwarded: cfg.maxAudioForwarded,
    maxVideoForwarded: cfg.maxVideoForwarded,
    nackEnabled: cfg.nackEnabled,
    handshake: receive.sendPort,
    label: 'worker-$index',
    verbose: cfg.verbose,
    roomIdleTimeout: cfg.roomIdleTimeout,
    roomIdleSweepInterval: cfg.roomIdleSweepInterval,
  );

  final isolate = await Isolate.spawn<RoomWorkerInit>(
    roomWorkerEntry,
    init,
    debugName: init.label,
    errorsAreFatal: false,
  );

  // Wire one persistent listener on the handshake port. The first
  // RoomWorkerReady completes the handshake; subsequent RoomWorkerLoad
  // messages keep the router's load snapshot fresh. (ReceivePort is a
  // single-subscription stream so we can't `firstWhere` then `listen` —
  // we use a Completer instead.)
  final ready = Completer<RoomWorkerReady>();
  late _WorkerHandle handle;
  receive.listen((msg) {
    if (msg is RoomWorkerReady) {
      if (!ready.isCompleted) {
        ready.complete(msg);
      } else {
        // Respawn handshake.
        handle.port = msg.port;
        handle.control = msg.control;
      }
    } else if (msg is RoomWorkerLoad) {
      handle.rooms = msg.rooms;
      handle.participants = msg.participants;
    }
  });

  final r = await ready.future;
  handle = _WorkerHandle(
    label: r.label,
    isolate: isolate,
    port: r.port,
    control: r.control,
  );
  return handle;
}

Future<void> _serve(HttpServer http, String advertised,
    List<_WorkerHandle> workers, MultiRoomServerConfig cfg) async {
  await for (final req in http) {
    try {
      await _route(req, advertised, workers, cfg);
    } catch (e, st) {
      // ignore: avoid_print
      if (cfg.verbose) print('[router] $e\n$st');
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }
}

Future<void> _route(HttpRequest req, String advertised,
    List<_WorkerHandle> workers, MultiRoomServerConfig cfg) async {
  final path = req.uri.path;

  if (req.method == 'GET' && path == '/health') {
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode({
      'status': 'ok',
      'workers': [
        for (final w in workers)
          {
            'label': w.label,
            'port': w.port,
            'rooms': w.rooms,
            'participants': w.participants,
          },
      ],
      'totals': {
        'rooms': workers.fold<int>(0, (a, w) => a + w.rooms),
        'participants': workers.fold<int>(0, (a, w) => a + w.participants),
      },
    }));
    await req.response.close();
    return;
  }

  if (req.method == 'GET' && path.startsWith('/room/')) {
    // /room/<id>/locate
    final tail = path.substring('/room/'.length);
    final slash = tail.indexOf('/');
    if (slash <= 0) {
      req.response.statusCode = HttpStatus.badRequest;
      await req.response.close();
      return;
    }
    final roomId = tail.substring(0, slash);
    final action = tail.substring(slash + 1);
    if (action != 'locate') {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final w = workers[_pickWorker(roomId, workers.length)];
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode({
      'roomId': roomId,
      'host': advertised,
      'port': w.port,
      'worker': w.label,
      'ws': 'ws://$advertised:${w.port}/ws/$roomId',
    }));
    await req.response.close();
    return;
  }

  if (req.method == 'GET' && (path == '/' || path == '/index.html')) {
    req.response.headers.contentType =
        ContentType('text', 'html', charset: 'utf-8');
    req.response.write(_demoHtml);
    await req.response.close();
    return;
  }

  req.response.statusCode = HttpStatus.notFound;
  await req.response.close();
}

/// Stable FNV-1a 32-bit hash. Used so the same roomId always lands on
/// the same worker, independently of `String.hashCode` (which is per-
/// isolate randomised in modern Dart).
int _fnv1a(String s) {
  var h = 0x811c9dc5;
  for (var i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i) & 0xff;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// Pick a worker for [roomId] given the current pool size. Public for
/// testing.
int pickWorkerForRoom(String roomId, int workerCount) =>
    _pickWorker(roomId, workerCount);

int _pickWorker(String roomId, int workerCount) {
  if (workerCount <= 1) return 0;
  return _fnv1a(roomId) % workerCount;
}

Future<String?> _firstNonLoopbackIPv4() async {
  try {
    final ifaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    for (final i in ifaces) {
      for (final a in i.addresses) {
        if (a.type == InternetAddressType.IPv4 && !a.isLoopback) {
          return a.address;
        }
      }
    }
  } catch (_) {}
  return null;
}

/// Tiny browser demo. Asks the router which worker owns the requested
/// roomId, then opens a WebSocket directly against that worker.
const String _demoHtml = r'''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>pure_dart_webrtc multi-room SFU demo</title>
    <style>
      body{font:14px sans-serif;margin:1em;background:#111;color:#eee}
      video{width:320px;background:#000;margin:.25em;border:1px solid #444}
      #log{font-family:monospace;white-space:pre-wrap;background:#000;padding:.5em;height:10em;overflow:auto}
      button,input{font:inherit;padding:.3em .6em}
    </style>
  </head>
  <body>
    <h2>pure_dart_webrtc multi-room SFU demo</h2>
    <p>
      room: <input id="room" value="lobby">
      id: <input id="id" value="alice">
      <button id="go">Join</button>
    </p>
    <div id="videos"></div>
    <pre id="stats" style="background:#000;padding:.5em;font-size:12px;max-height:14em;overflow:auto"></pre>
    <div id="log"></div>
    <script>
document.addEventListener('DOMContentLoaded', () => {
  console.log('document loaded ...');
  const log = (...a) => {
    document.getElementById('log').textContent += a.join(' ') + '\n';
    console.log(...a);
  };
  const videos = document.getElementById('videos');

  document.getElementById('go').onclick = async () => {
    const room = document.getElementById('room').value || 'lobby';
    const id = document.getElementById('id').value || 'alice';

    // Discovery hop: ask the router which worker owns this room.
    const r = await fetch('/room/' + encodeURIComponent(room) + '/locate');
    if (!r.ok) { log('locate failed:', r.status); return; }
    const { ws: wsUrl, worker } = await r.json();
    log('routed to', worker, '->', wsUrl);

    const ws = new WebSocket(wsUrl);
    await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });

    const local = await navigator.mediaDevices.getUserMedia({video:true, audio:true});
    const localV = document.createElement('video');
    localV.autoplay = true; localV.muted = true; localV.srcObject = local;
    videos.appendChild(localV);

    const pc = new RTCPeerConnection();
    const pendingCandidates = [];

    // Pre-allocate a fixed pool of recvonly transceiver pairs BEFORE
    // adding our local sender tracks. The SFU's augmentAnswerSdp only
    // injects each producer into one m= section, so without enough
    // recvonly slots we can never see more than two peers. Doing this
    // up-front (instead of growing the pool on peer-joined) avoids the
    // mid-call renegotiations that were tripping the browser into
    // sending a fatal DTLS InternalError.
    const RECV_SLOTS = 16;
    for (let i = 0; i < RECV_SLOTS; i++) {
      pc.addTransceiver('video', {direction:'recvonly'});
      pc.addTransceiver('audio', {direction:'recvonly'});
    }
    for (const t of local.getTracks()) pc.addTrack(t, local);

    pc.onicecandidate = (e) => {
      if (!e.candidate) return;
      log('ice candidate:', e.candidate.candidate);
      ws.send(JSON.stringify({
        type:'candidate',
        candidate: e.candidate.candidate,
        sdpMid: e.candidate.sdpMid,
        sdpMLineIndex: e.candidate.sdpMLineIndex,
      }));
    };
    pc.ontrack = (e) => {
      let v = document.getElementById('v_' + e.streams[0].id);
      if (!v) {
        v = document.createElement('video');
        v.id = 'v_' + e.streams[0].id;
        v.autoplay = true; v.playsInline = true;
        videos.appendChild(v);
      }
      v.srcObject = e.streams[0];
    };
    pc.oniceconnectionstatechange = () => log('ice:', pc.iceConnectionState);
    pc.onconnectionstatechange = () => log('conn:', pc.connectionState);

    ws.onmessage = async (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.type !== 'candidate') log('ws<=', msg.type);
      if (msg.type === 'joined') {
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        ws.send(JSON.stringify({type:'offer', sdp: offer.sdp}));
      } else if (msg.type === 'answer') {
        await pc.setRemoteDescription({type:'answer', sdp: msg.sdp});
        log('got answer');
        // Flush any candidates that arrived before the answer.
        while (pendingCandidates.length) {
          const c = pendingCandidates.shift();
          try { await pc.addIceCandidate(c); }
          catch (e) { log('addIceCandidate (flush) err:', e); }
        }
      } else if (msg.type === 'candidate' && msg.candidate) {
        const cand = {
          candidate: msg.candidate,
          sdpMid: msg.sdpMid,
          sdpMLineIndex: msg.sdpMLineIndex,
        };
        if (!pc.remoteDescription || !pc.remoteDescription.type) {
          pendingCandidates.push(cand);
        } else {
          try { await pc.addIceCandidate(cand); }
          catch (e) { log('addIceCandidate err:', e); }
        }
      } else if (msg.type === 'renegotiate') {
        log('renegotiate:', msg.reason || '(no reason)');
        try {
          const offer = await pc.createOffer();
          await pc.setLocalDescription(offer);
          ws.send(JSON.stringify({type:'offer', sdp: offer.sdp}));
        } catch (e) { log('renegotiate err:', e); }
      } else if (msg.type === 'peer-joined' || msg.type === 'peer-left') {
        log(msg.type, msg.id);
      } else if (msg.type === 'error') {
        log('server error:', msg.message);
      }
    };

    ws.send(JSON.stringify({type:'join', id, name:id}));
    log('joined room', room, 'as', id);

    // Stats poller — hits the worker's /stats, not the router.
    const wsUrlObj = new URL(wsUrl);
    const statsUrl = `${wsUrlObj.protocol === 'wss:' ? 'https:' : 'http:'}//${wsUrlObj.host}/stats`;
    const statsEl = document.getElementById('stats');
    setInterval(async () => {
      try {
        const r = await fetch(statsUrl);
        const j = await r.json();
        statsEl.textContent = JSON.stringify(j, null, 2);
      } catch (e) {}
    }, 2000);
  };
});
    </script>
  </body>
</html>
''';
