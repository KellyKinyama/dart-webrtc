// Multi-room SFU CLI: spawns a worker isolate per CPU core (configurable)
// and routes WebSocket signaling to the worker that owns each room id.
//
// Run with:
//   dart run bin\multi_room_server.dart [--ip 0.0.0.0] [--port 8080]
//                                        [--workers N]
//                                        [--max-rooms-per-worker 0]
//                                        [--max-participants-per-room 0]
//                                        [--announce-ip 1.2.3.4]
//
// All real logic lives in `lib/multi_room_server.dart` so it can be tested.

import 'dart:async';
import 'dart:io';

import 'package:pure_dart_webrtc_sfu_example/multi_room_server.dart';

Future<void> main(List<String> arguments) async {
  String ip = '0.0.0.0';
  int port = 8080;
  int? workerCount;
  int maxRoomsPerWorker = 0;
  int maxParticipantsPerRoom = 0;
  int maxInFlightBytesPerReceiver = 0;
  int maxAudioForwarded = 3;
  int maxVideoForwarded = -1;
  bool nackEnabled = false;
  String? announceIp = Platform.environment['SFU_ANNOUNCE_IP'];
  String? authToken = Platform.environment['SFU_AUTH_TOKEN'];
  bool verbose = true;

  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--ip':
        ip = arguments[++i];
        break;
      case '--port':
        port = int.parse(arguments[++i]);
        break;
      case '--workers':
        workerCount = int.parse(arguments[++i]);
        break;
      case '--max-rooms-per-worker':
        maxRoomsPerWorker = int.parse(arguments[++i]);
        break;
      case '--max-participants-per-room':
        maxParticipantsPerRoom = int.parse(arguments[++i]);
        break;
      case '--max-inflight-bytes':
        maxInFlightBytesPerReceiver = int.parse(arguments[++i]);
        break;
      case '--max-audio-forwarded':
        maxAudioForwarded = int.parse(arguments[++i]);
        break;
      case '--max-video-forwarded':
        maxVideoForwarded = int.parse(arguments[++i]);
        break;
      case '--enable-server-nack':
        nackEnabled = true;
        break;
      case '--auth-token':
        authToken = arguments[++i];
        break;
      case '--announce-ip':
        announceIp = arguments[++i];
        break;
      case '--quiet':
        verbose = false;
        break;
      case '-h':
      case '--help':
        stdout.writeln('Multi-room SFU\n'
            '\n'
            'Usage:\n'
            '  dart run bin/multi_room_server.dart [options]\n'
            '\n'
            'Options:\n'
            '  --ip ADDR                       Bind address (default 0.0.0.0)\n'
            '  --port N                        Router HTTP port (default 8080)\n'
            '  --workers N                     Worker isolate count (default = CPU count)\n'
            '  --max-rooms-per-worker N        Hard cap, 0 = unbounded\n'
            '  --max-participants-per-room N   Hard cap, 0 = unbounded\n'
            '  --max-inflight-bytes N          Per-receiver egress queue cap (bytes)\n'
            '  --max-audio-forwarded N         Top-K active audio speakers (default 3)\n'
            '  --max-video-forwarded N         Top-K video forwarding (default -1 = all)\n'
            '  --enable-server-nack            Server-side gap detection + NACK\n'
            '  --auth-token TOKEN              Required WS subprotocol/?token=\n'
            '  --announce-ip ADDR              IP advertised in ICE candidates\n'
            '  --quiet                         Suppress per-event log lines\n');
        return;
    }
  }

  final cfg = MultiRoomServerConfig(
    ip: ip,
    routerPort: port,
    workerCount: workerCount ?? 0,
    announceIp: announceIp,
    authToken: authToken,
    maxRoomsPerWorker: maxRoomsPerWorker,
    maxParticipantsPerRoom: maxParticipantsPerRoom,
    maxInFlightBytesPerReceiver: maxInFlightBytesPerReceiver,
    maxAudioForwarded: maxAudioForwarded,
    maxVideoForwarded: maxVideoForwarded,
    nackEnabled: nackEnabled,
    verbose: verbose,
  );

  final handle = await runMultiRoomServer(cfg);

  final displayHost =
      (ip == '0.0.0.0' || ip == '::' || ip.isEmpty) ? 'localhost' : ip;
  print('Router       : http://$displayHost:${handle.port}/');
  print('Health       : http://$displayHost:${handle.port}/health');
  print('Locate (eg.) : http://$displayHost:${handle.port}/room/lobby/locate');
  print('Workers      : ${handle.workerPorts.length} '
      '(ports=${handle.workerPorts.join(", ")})');

  // Graceful shutdown.
  final shutdown = Completer<void>();
  void onSignal(ProcessSignal s) {
    if (shutdown.isCompleted) return;
    print('\n[router] received $s, shutting down...');
    shutdown.complete();
  }

  ProcessSignal.sigint.watch().listen(onSignal);
  await shutdown.future;
  await handle.close();
  print('[router] bye.');
}
