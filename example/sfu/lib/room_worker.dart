// Multi-room signaling stack that runs inside a single worker isolate.
//
// One [RoomWorker] owns a `Map<String, BasicSfu>` keyed by roomId. The
// isolate binds its own HTTP port; clients reach it directly via
// `ws://host:port/ws/<roomId>` after the main-isolate router tells
// them which port owns that roomId.
//
// All RTP and signaling traffic stays inside this isolate's event loop
// — the router only ever touches the control plane (health,
// shutdown).
//
// See [MULTI_ROOM_ARCHITECTURE.md](../MULTI_ROOM_ARCHITECTURE.md).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

import 'basic_sfu.dart';

/// Bootstrap parameters sent from the main isolate via [Isolate.spawn].
/// Must be a plain Dart object graph (no closures, no streams).
class RoomWorkerInit {
  /// Address every HTTP / UDP socket binds on in this worker.
  final String ip;

  /// Worker HTTP port. 0 lets the OS pick; the actual port is reported
  /// back via [readyPort].
  final int port;

  /// Address advertised in host ICE candidates. When [ip] is a wildcard
  /// the bound address is not routable and ICE pairing fails.
  final String? announceIp;

  /// Optional shared bearer for WS upgrades.
  final String? authToken;

  /// Hard cap on rooms hosted in this worker. 0 = unbounded.
  final int maxRoomsPerWorker;

  /// Per-room participant cap. 0 = unbounded. Forwarded to
  /// [BasicSfu.maxParticipants].
  final int maxParticipantsPerRoom;

  /// Per-receiver outbound queue cap. 0 = no limit. Forwarded to
  /// [BasicSfu.maxInFlightBytesPerReceiver].
  final int maxInFlightBytesPerReceiver;

  /// SFU policy knobs forwarded to every [BasicSfu] this worker creates.
  final int maxAudioForwarded;
  final int maxVideoForwarded;
  final bool nackEnabled;

  /// SendPort used by the worker to publish its bound HTTP port (and
  /// later, control-plane events) back to the main isolate.
  final SendPort handshake;

  /// Display name for log lines (typically the worker index).
  final String label;

  /// When true, the worker prints per-event log lines.
  final bool verbose;

  /// Idle-room reaper interval. Rooms with zero participants for longer
  /// than [roomIdleTimeout] are closed and forgotten so a worker that
  /// served a million ephemeral rooms doesn't leak memory.
  final Duration roomIdleTimeout;

  /// How often the idle reaper wakes up.
  final Duration roomIdleSweepInterval;

  const RoomWorkerInit({
    required this.ip,
    required this.port,
    required this.handshake,
    required this.label,
    this.announceIp,
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
  });
}

/// Control-plane messages the main isolate sends to the worker after
/// startup. Workers receive them on a [ReceivePort] established during
/// the [RoomWorkerHandshake] reply.
sealed class RoomWorkerCommand {
  const RoomWorkerCommand();
}

class RoomWorkerShutdown extends RoomWorkerCommand {
  const RoomWorkerShutdown();
}

/// Worker → main isolate replies.
sealed class RoomWorkerEvent {
  const RoomWorkerEvent();
}

/// First message every worker emits. Tells the main isolate which port
/// the worker actually bound to and gives it a control-plane port.
class RoomWorkerReady extends RoomWorkerEvent {
  final String label;
  final int port;

  /// SendPort the main isolate uses to deliver [RoomWorkerCommand]s.
  final SendPort control;

  const RoomWorkerReady({
    required this.label,
    required this.port,
    required this.control,
  });
}

/// Periodic load report. The router does not currently rebalance based
/// on this — it's published purely for the aggregated `/health`
/// endpoint.
class RoomWorkerLoad extends RoomWorkerEvent {
  final String label;
  final int rooms;
  final int participants;

  const RoomWorkerLoad({
    required this.label,
    required this.rooms,
    required this.participants,
  });
}

/// Pick the host string we should *show* in human-readable URLs.
/// Wildcard bind addresses (`0.0.0.0`, `::`, empty) aren't routable,
/// so prefer the announce IP when set, otherwise fall back to
/// `localhost`.
String _displayHost(String bindIp, String? announceIp) {
  final isWildcard = bindIp == '0.0.0.0' || bindIp == '::' || bindIp.isEmpty;
  if (announceIp != null && announceIp.isNotEmpty) return announceIp;
  if (isWildcard) return 'localhost';
  return bindIp;
}

/// Isolate entry point. Spawn with:
/// ```dart
/// Isolate.spawn<RoomWorkerInit>(roomWorkerEntry, init);
/// ```
Future<void> roomWorkerEntry(RoomWorkerInit init) async {
  final worker = _RoomWorker(init);
  await worker.run();
}

class _RoomWorker {
  final RoomWorkerInit init;
  final Map<String, _Room> _rooms = {};
  HttpServer? _http;
  Timer? _idleSweep;
  Timer? _loadReporter;
  final ReceivePort _controlPort = ReceivePort();

  _RoomWorker(this.init);

  void _log(String msg) {
    if (init.verbose) {
      // ignore: avoid_print
      print('[${init.label}] $msg');
    }
  }

  Future<void> run() async {
    final http = await HttpServer.bind(init.ip, init.port);
    _http = http;
    final display = _displayHost(init.ip, init.announceIp);
    _log('listening on $display:${http.port}'
        '${display == init.ip ? '' : ' (bind=${init.ip})'}');

    // Tell the main isolate where we are and how to talk to us.
    init.handshake.send(RoomWorkerReady(
      label: init.label,
      port: http.port,
      control: _controlPort.sendPort,
    ));

    _controlPort.listen((msg) async {
      if (msg is RoomWorkerShutdown) {
        await _shutdown();
      }
    });

    _idleSweep =
        Timer.periodic(init.roomIdleSweepInterval, (_) => _reapIdleRooms());
    _loadReporter =
        Timer.periodic(const Duration(seconds: 5), (_) => _reportLoad());

    unawaited(_serve(http));
  }

  Future<void> _serve(HttpServer http) async {
    await for (final request in http) {
      try {
        await _route(request);
      } catch (e, st) {
        _log('request error: $e\n$st');
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {}
      }
    }
  }

  Future<void> _route(HttpRequest req) async {
    final path = req.uri.path;
    if (req.method == 'GET' && path == '/health') {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'label': init.label,
        'rooms': _rooms.length,
        'participants': _totalParticipants(),
      }));
      await req.response.close();
      return;
    }
    if (req.method == 'GET' && path == '/stats') {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'label': init.label,
        'rooms': {
          for (final entry in _rooms.entries)
            entry.key: {
              'participants': entry.value.sfu.participants.length,
              'forwarding': {
                'rtpForwarded': entry.value.sfu.stats.rtpForwarded,
                'rtcpForwarded': entry.value.sfu.stats.rtcpForwarded,
                'rtpDropped': entry.value.sfu.stats.rtpDropped,
              },
            },
        },
      }));
      await req.response.close();
      return;
    }
    if (path.startsWith('/ws/')) {
      final roomId = path.substring('/ws/'.length);
      if (roomId.isEmpty) {
        req.response.statusCode = HttpStatus.badRequest;
        await req.response.close();
        return;
      }
      await _handleWsUpgrade(req, roomId);
      return;
    }
    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }

  Future<void> _handleWsUpgrade(HttpRequest req, String roomId) async {
    if (init.authToken != null) {
      final supplied = req.uri.queryParameters['token'] ??
          req.headers.value('sec-websocket-protocol');
      if (supplied != init.authToken) {
        req.response.statusCode = HttpStatus.unauthorized;
        await req.response.close();
        return;
      }
    }

    // Capacity check happens before the upgrade so the client gets a
    // real HTTP error code instead of a silent 1006.
    if (init.maxRoomsPerWorker > 0 &&
        !_rooms.containsKey(roomId) &&
        _rooms.length >= init.maxRoomsPerWorker) {
      req.response.statusCode = HttpStatus.serviceUnavailable;
      req.response.write('worker room cap reached\n');
      await req.response.close();
      return;
    }

    final WebSocket ws;
    try {
      ws = await WebSocketTransformer.upgrade(
        req,
        protocolSelector: init.authToken == null
            ? null
            : (protocols) => protocols.firstWhere(
                  (p) => p == init.authToken,
                  orElse: () => '',
                ),
      );
    } catch (e) {
      _log('upgrade failed: $e');
      return;
    }
    ws.pingInterval = const Duration(seconds: 20);

    final room = _rooms.putIfAbsent(roomId, () => _createRoom(roomId));
    room.attach(ws);
  }

  _Room _createRoom(String roomId) {
    _log('creating room "$roomId"');
    final advertised = init.announceIp ?? init.ip;
    final sfu = BasicSfu(
      address: InternetAddress(init.ip),
      announceAddress: InternetAddress(advertised),
      // Multi-room mode: every transport binds to OS-picked ports so
      // rooms cannot collide.
      basePort: 0,
      maxParticipants: init.maxParticipantsPerRoom,
      maxInFlightBytesPerReceiver: init.maxInFlightBytesPerReceiver,
      maxAudioForwarded: init.maxAudioForwarded,
      maxVideoForwarded: init.maxVideoForwarded,
      nackEnabled: init.nackEnabled,
    );
    return _Room(roomId, sfu, _log);
  }

  void _reapIdleRooms() {
    if (_rooms.isEmpty) return;
    final now = DateTime.now();
    final dead = <String>[];
    for (final entry in _rooms.entries) {
      final room = entry.value;
      if (room.sfu.participants.isNotEmpty) {
        room.lastActiveAt = now;
        continue;
      }
      if (now.difference(room.lastActiveAt) > init.roomIdleTimeout) {
        dead.add(entry.key);
      }
    }
    for (final id in dead) {
      _log('reaping idle room "$id"');
      _rooms.remove(id)?.close();
    }
  }

  void _reportLoad() {
    init.handshake.send(RoomWorkerLoad(
      label: init.label,
      rooms: _rooms.length,
      participants: _totalParticipants(),
    ));
  }

  int _totalParticipants() {
    var total = 0;
    for (final r in _rooms.values) {
      total += r.sfu.participants.length;
    }
    return total;
  }

  Future<void> _shutdown() async {
    _log('shutting down');
    _idleSweep?.cancel();
    _loadReporter?.cancel();
    _controlPort.close();
    for (final r in _rooms.values.toList()) {
      await r.close();
    }
    _rooms.clear();
    await _http?.close(force: true);
    _http = null;
  }
}

/// One room hosted by a worker isolate. Wraps a [BasicSfu] plus the
/// per-room signaling state (connected websockets, last-seen SDP).
class _Room {
  final String id;
  final BasicSfu sfu;
  final void Function(String) log;
  final Map<String, WebSocket> clients = {};
  DateTime lastActiveAt = DateTime.now();

  _Room(this.id, this.sfu, this.log) {
    sfu
      ..onParticipantJoined = (p) {
        log('[$id] joined ${p.id}');
        _broadcast({'type': 'peer-joined', 'id': p.id, 'name': p.displayName},
            except: p.id);
      }
      ..onParticipantLeft = (p) {
        log('[$id] left ${p.id}');
        _broadcast({'type': 'peer-left', 'id': p.id});
      }
      ..onProducersChanged = (producerId, _) {
        for (final cid in clients.keys) {
          if (cid == producerId) continue;
          final ws = clients[cid];
          try {
            ws?.add(jsonEncode({
              'type': 'renegotiate',
              'reason': 'new-producer:$producerId',
            }));
          } catch (_) {}
        }
      };
  }

  void attach(WebSocket ws) {
    lastActiveAt = DateTime.now();
    String? participantId;

    ws.listen((raw) async {
      lastActiveAt = DateTime.now();
      try {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        switch (msg['type']) {
          case 'join':
            participantId = msg['id'] as String;
            final name = msg['name'] as String?;
            final existingPeers = [
              for (final p in sfu.participants)
                {'id': p.id, 'name': p.displayName},
            ];
            clients[participantId!] = ws;
            final p = await sfu
                .addParticipant(participantId!, displayName: name)
                .catchError((Object e) {
              ws.add(jsonEncode({'type': 'error', 'message': e.toString()}));
              throw e;
            });
            p.pc.onIceCandidate = (cand) {
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
            ws.add(jsonEncode({
              'type': 'joined',
              'id': participantId,
              'room': id,
              'peers': existingPeers,
            }));
            break;
          case 'offer':
            final p = sfu.getParticipant(participantId ?? '');
            if (p == null) break;
            final sdpText = msg['sdp'] as String;
            sfu.learnSsrcMappingFromOffer(participantId!, sdpText);
            await p.pc.setRemoteDescription(
              RTCSessionDescription(RTCSdpType.offer, sdpText),
            );
            final answer = await p.pc.createAnswer();
            await p.pc.setLocalDescription(answer);
            final augmented = sfu.augmentAnswerSdp(participantId!, answer.sdp);
            ws.add(jsonEncode({'type': 'answer', 'sdp': augmented}));
            break;
          case 'answer':
            final p = sfu.getParticipant(participantId ?? '');
            if (p == null) break;
            await p.pc.setRemoteDescription(
              RTCSessionDescription(RTCSdpType.answer, msg['sdp'] as String),
            );
            break;
          case 'candidate':
            final p = sfu.getParticipant(participantId ?? '');
            if (p == null) break;
            final candStr = msg['candidate'] as String?;
            if (candStr == null) break;
            await p.pc.addIceCandidate(RTCIceCandidate(
              candidate: candStr,
              sdpMid: msg['sdpMid'] as String?,
              sdpMLineIndex: msg['sdpMLineIndex'] as int?,
            ));
            break;
          case 'leave':
            if (participantId != null) {
              await sfu.removeParticipant(participantId!);
              clients.remove(participantId);
            }
            await ws.close();
            break;
        }
      } catch (e, st) {
        log('[$id] ws error: $e\n$st');
      }
    }, onDone: () async {
      if (participantId != null) {
        await sfu.removeParticipant(participantId!);
        clients.remove(participantId);
      }
    }, cancelOnError: true);
  }

  void _broadcast(Map<String, Object?> msg, {String? except}) {
    final encoded = jsonEncode(msg);
    for (final entry in clients.entries) {
      if (entry.key == except) continue;
      try {
        entry.value.add(encoded);
      } catch (_) {}
    }
  }

  Future<void> close() async {
    await sfu.close();
    for (final ws in clients.values.toList()) {
      try {
        await ws.close();
      } catch (_) {}
    }
    clients.clear();
  }
}
