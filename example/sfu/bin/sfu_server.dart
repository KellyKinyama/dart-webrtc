// Minimal SFU video-conferencing server CLI.
//
// Run with:
//   dart run bin\sfu_server.dart [--ip 0.0.0.0] [--ws-port 8080] [--rtp-base 50000]
//
// All real logic lives in `lib/sfu_server.dart` so it can be tested.

import 'dart:async';

import 'package:pure_dart_webrtc_sfu_example/sfu_server.dart';

Future<void> main(List<String> arguments) async {
  String ip = '0.0.0.0';
  int wsPort = 8080;
  int rtpBase = 50000;

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
    }
  }

  final handle = await runSfuServer(ip: ip, port: wsPort, rtpBase: rtpBase);
  print('SFU signaling listening on ws://$ip:${handle.port}/ws');
  print('Browser demo:               http://$ip:${handle.port}/');
  print('Health probe:               http://$ip:${handle.port}/health');
  print('Live stats:                 http://$ip:${handle.port}/stats');
  print('SFU media base port: $rtpBase (one port per participant)');
}
