// CLI entry point for the ion-style SFU example.

import 'dart:io';

import 'package:pure_dart_webrtc_ion_style_sfu/src/sfu_server.dart';

Future<void> main(List<String> arguments) async {
  String ip = '0.0.0.0';
  int wsPort = 9090;
  int rtpBase = 51000;
  String? announceIp;

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
      case '--announce-ip':
        announceIp = arguments[++i];
        break;
      case '-h':
      case '--help':
        stdout.writeln('Usage: dart run bin/sfu_server.dart '
            '[--ip 0.0.0.0] [--ws-port 9090] [--rtp-base 51000] '
            '[--announce-ip 1.2.3.4]');
        return;
    }
  }

  await runIonStyleSfuServer(
    ip: ip,
    port: wsPort,
    rtpBase: rtpBase,
    announceIp: announceIp,
  );
}
