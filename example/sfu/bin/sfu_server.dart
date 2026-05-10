// Minimal SFU video-conferencing server CLI.
//
// Run with:
//   dart run bin\sfu_server.dart [--ip 0.0.0.0] [--ws-port 8080]
//                                [--rtp-base 50000] [--pli-min-interval-ms 500]
//
// All real logic lives in `lib/sfu_server.dart` so it can be tested.

import 'dart:async';
import 'dart:io';

import 'package:pure_dart_webrtc_sfu_example/sfu_server.dart';

Future<void> main(List<String> arguments) async {
  String ip = '0.0.0.0';
  int wsPort = 8080;
  int rtpBase = 50000;
  int pliMinIntervalMs = 500;
  int inactivityTimeoutS = 30;
  String? authToken = Platform.environment['SFU_AUTH_TOKEN'];
  bool nackEnabled = false;
  String? announceIp = Platform.environment['SFU_ANNOUNCE_IP'];

  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--ip':
        ip = arguments[++i];
        break;
      case '--ws-port':
        wsPort = int.parse(arguments[++i]);
        break;
      case '--rtp-base':
        rtpBase = int.parse(arguments[++i]);
        break;
      case '--pli-min-interval-ms':
        pliMinIntervalMs = int.parse(arguments[++i]);
        break;
      case '--inactivity-timeout-s':
        inactivityTimeoutS = int.parse(arguments[++i]);
        break;
      case '--auth-token':
        authToken = arguments[++i];
        break;
      case '--enable-server-nack':
        nackEnabled = true;
        break;
      case '--announce-ip':
        announceIp = arguments[++i];
        break;
      case '-h':
      case '--help':
        stdout.writeln(
            'Usage: dart run bin/sfu_server.dart [--ip 0.0.0.0] [--ws-port 8080] '
            '[--rtp-base 50000] [--pli-min-interval-ms 500] '
            '[--inactivity-timeout-s 30] [--auth-token TOKEN] '
            '[--enable-server-nack] [--announce-ip 1.2.3.4]\n'
            '\n'
            'The auth token may also be supplied via the SFU_AUTH_TOKEN '
            'environment variable. If unset, /ws is unauthenticated.\n'
            '\n'
            'When --ip is a wildcard (0.0.0.0 / ::) the SFU advertises '
            '127.0.0.1 in host ICE candidates by default; override with '
            '--announce-ip or SFU_ANNOUNCE_IP for cross-machine testing.');
        return;
    }
  }

  final handle = await runSfuServer(
    ip: ip,
    port: wsPort,
    rtpBase: rtpBase,
    pliMinInterval: Duration(milliseconds: pliMinIntervalMs),
    inactivityTimeout:
        inactivityTimeoutS <= 0 ? null : Duration(seconds: inactivityTimeoutS),
    authToken: authToken,
    nackEnabled: nackEnabled,
    announceIp: announceIp,
  );
  // When binding to a wildcard address (0.0.0.0 / ::), display a more
  // useful host so the printed URLs are clickable in a terminal.
  final displayHost = (ip == '0.0.0.0' || ip == '::' || ip == '0' || ip.isEmpty)
      ? 'localhost'
      : (ip.contains(':') ? '[$ip]' : ip);
  if (ip != displayHost) {
    print('SFU bound to $ip (all interfaces); URLs below use $displayHost.');
  }
  print('SFU signaling listening on ws://$displayHost:${handle.port}/ws');
  print('Browser demo:               http://$displayHost:${handle.port}/');
  print(
      'Health probe:               http://$displayHost:${handle.port}/health');
  print('Live stats:                 http://$displayHost:${handle.port}/stats');
  print('SFU media base port: $rtpBase (one port per participant)');
  print('PLI min interval:    ${pliMinIntervalMs}ms');
  print('Inactivity timeout:  '
      '${inactivityTimeoutS <= 0 ? 'disabled' : '${inactivityTimeoutS}s'}');
  print('WS auth:             '
      '${authToken == null ? 'disabled (open)' : 'enabled (token required)'}');
  print('Server-NACK:         ${nackEnabled ? 'enabled' : 'disabled'}');
  final isWildcard = ip == '0.0.0.0' || ip == '::' || ip.isEmpty;
  final advertised = announceIp ?? (isWildcard ? '127.0.0.1' : ip);
  print('Announce IP (host candidate): $advertised'
      '${announceIp == null && isWildcard ? '  [auto: --announce-ip to override]' : ''}');

  // Graceful shutdown — close every UDP transport, the SFU, and the
  // HTTP listener before exiting.
  final shutdown = Completer<void>();
  void onSignal(ProcessSignal sig) {
    if (shutdown.isCompleted) return;
    print('\n[sfu] received $sig, shutting down...');
    shutdown.complete();
  }

  ProcessSignal.sigint.watch().listen(onSignal);
  // SIGTERM isn't supported on Windows; guard the subscription.
  // if (!Platform.isWindows) {
  //   ProcessSignal.sigterm.watch().listen(onSignal);
  // }

  await shutdown.future;
  await handle.close();
  print('[sfu] bye.');
  exit;
}
