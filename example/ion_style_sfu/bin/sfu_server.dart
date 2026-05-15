// CLI entry point for the ion-style SFU example.

import 'dart:io';

import 'package:pure_dart_webrtc_ion_style_sfu/src/cluster/locator.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/src/sfu_server.dart';

Future<void> main(List<String> arguments) async {
  String ip = '0.0.0.0';
  int wsPort = 9090;
  int rtpBase = 51000;
  String? announceIp;
  String? authToken;
  int maxPeersPerRoom = 0;
  int maxRooms = 0;
  String? selfId;
  int? relayPort;
  String? relaySecret;
  final clusterPeers = <ClusterPeer>[];
  final iceServerUrls = <String>[];

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
      case '--auth-token':
        authToken = arguments[++i];
        break;
      case '--max-peers-per-room':
        maxPeersPerRoom = int.parse(arguments[++i]);
        break;
      case '--max-rooms':
        maxRooms = int.parse(arguments[++i]);
        break;
      case '--self-id':
        selfId = arguments[++i];
        break;
      case '--relay-port':
        relayPort = int.parse(arguments[++i]);
        break;
      case '--relay-secret':
        relaySecret = arguments[++i];
        break;
      case '--peers':
        for (final spec in arguments[++i].split(',')) {
          final s = spec.trim();
          if (s.isEmpty) continue;
          clusterPeers.add(ClusterPeer.parse(s));
        }
        break;
      case '--ice-server':
        // Repeatable; also accepts comma-separated URLs in a single value.
        for (final raw in arguments[++i].split(',')) {
          final url = raw.trim();
          if (url.isNotEmpty) iceServerUrls.add(url);
        }
        break;
      case '-h':
      case '--help':
        stdout.writeln(_help);
        return;
    }
  }

  if (clusterPeers.isNotEmpty) {
    selfId ??= clusterPeers.first.id;
    relayPort ??= wsPort + 1;
  }

  final handle = await runIonStyleSfuServer(
    ip: ip,
    port: wsPort,
    rtpBase: rtpBase,
    iceServerUrls: iceServerUrls,
    announceIp: announceIp,
    authToken: authToken,
    maxPeersPerRoom: maxPeersPerRoom,
    maxRooms: maxRooms,
    clusterPeers: clusterPeers,
    selfClusterId: selfId,
    relayPort: relayPort,
    relaySecret: relaySecret,
  );

  // Phase 10 — graceful shutdown on SIGINT/SIGTERM.
  Future<void> shutdown(ProcessSignal sig) async {
    stdout.writeln('shutting down ($sig)');
    await handle.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen(shutdown);
  }
}

const _help = '''
Usage: dart run bin/sfu_server.dart [options]

Transport:
  --ip <addr>             Bind address (default 0.0.0.0)
  --ws-port <port>        WebSocket / HTTP port (default 9090)
  --rtp-base <port>       First UDP port for media transports (default 51000)
  --announce-ip <addr>    Override the host candidate IP (NAT/wildcard binds)
  --ice-server <url>      STUN URL for srflx gathering on Pub/Sub PCs.
                          Repeatable; comma-separated values also accepted.
                          E.g. --ice-server stun:stun.l.google.com:19302

Production:
  --auth-token <token>    Require this bearer token on /ws/<sid>
  --max-peers-per-room N  Reject join past N peers in a single room
  --max-rooms N           Reject cold-create past N concurrent rooms

Cluster (cross-host scaling):
  --peers host:httpPort:relayPort,...  Cluster membership
  --self-id host:httpPort              This SFU's id (must match a --peers entry)
  --relay-port <port>                  UDP port for relay traffic (default ws-port+1)
  --relay-secret <secret>              HMAC-SHA256 shared secret for relay auth

Endpoints:
  /ws/<sessionId>     WebSocket signaling (one peer per connection)
  /stats              JSON snapshot
  /metrics            Prometheus text exposition v0.0.4
  /healthz            Liveness + cluster summary
  /locate?sid=<id>    Resolve a session's owner SFU
''';
