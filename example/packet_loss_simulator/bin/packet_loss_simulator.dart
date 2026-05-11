// packet_loss_simulator — bidirectional UDP middlebox.
//
// Sits between two UDP peers and randomly drops, reorders, delays, or
// duplicates packets in each direction. Indispensable when debugging
// WebRTC jitter buffers, NACK / PLI logic, FEC, congestion control,
// audio glitch repair, etc.
//
//                  client side                       server side
//   peer A ───▶ [listen-port] ─── lossy A→B ───▶ [target host:port]
//   peer A ◀─── [listen-port] ◀── lossy B→A ─── [target host:port]
//
// Usage:
//   dart run bin/packet_loss_simulator.dart \
//       --listen 0.0.0.0:7000 \
//       --target 192.168.1.50:5000 \
//       --drop 5 --reorder 1 --delay 30 --jitter 20
//
// Point peer A at port 7000 instead of the real server. The simulator
// learns peer A's address from the first packet it receives and uses
// that for the return path.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:args/args.dart';

class _Profile {
  _Profile({
    required this.dropPct,
    required this.reorderPct,
    required this.duplicatePct,
    required this.delayMs,
    required this.jitterMs,
  });
  final double dropPct;
  final double reorderPct;
  final double duplicatePct;
  final int delayMs;
  final int jitterMs;

  Duration sampleDelay(Random rng) {
    if (delayMs == 0 && jitterMs == 0) return Duration.zero;
    final j = jitterMs == 0 ? 0 : rng.nextInt(jitterMs * 2) - jitterMs;
    final ms = (delayMs + j).clamp(0, 60000);
    return Duration(milliseconds: ms);
  }
}

class _Stats {
  int rx = 0;
  int dropped = 0;
  int reordered = 0;
  int duplicated = 0;
  int delivered = 0;
}

Future<int> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('listen', defaultsTo: '0.0.0.0:7000')
    ..addOption('target', mandatory: true, help: 'host:port to forward to')
    // Symmetric defaults; override per direction with the long flags.
    ..addOption('drop', defaultsTo: '0', help: 'drop %, both directions')
    ..addOption('reorder', defaultsTo: '0', help: 'reorder %, both')
    ..addOption('duplicate', defaultsTo: '0', help: 'duplicate %, both')
    ..addOption('delay', defaultsTo: '0', help: 'base delay ms, both')
    ..addOption('jitter', defaultsTo: '0', help: '+/- jitter ms, both')
    ..addOption('drop-a2b', help: 'override drop % A→B')
    ..addOption('drop-b2a', help: 'override drop % B→A')
    ..addOption('delay-a2b', help: 'override delay ms A→B')
    ..addOption('delay-b2a', help: 'override delay ms B→A')
    ..addOption('seed', help: 'RNG seed (deterministic mode)');

  late final ArgResults o;
  try {
    o = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n${parser.usage}');
    return 64;
  }

  final listenParts = (o['listen'] as String).split(':');
  final targetParts = (o['target'] as String).split(':');
  if (listenParts.length != 2 || targetParts.length != 2) {
    stderr.writeln('--listen and --target must be host:port');
    return 64;
  }
  final listenAddr = InternetAddress(listenParts[0]);
  final listenPort = int.parse(listenParts[1]);
  final targetAddr = (await InternetAddress.lookup(targetParts[0])).first;
  final targetPort = int.parse(targetParts[1]);

  double pct(String? v, String fallback) => double.parse(v ?? fallback) / 100.0;
  int ms(String? v, String fallback) => int.parse(v ?? fallback);

  final pA2B = _Profile(
    dropPct: pct(o['drop-a2b'] as String?, o['drop'] as String),
    reorderPct: pct(null, o['reorder'] as String),
    duplicatePct: pct(null, o['duplicate'] as String),
    delayMs: ms(o['delay-a2b'] as String?, o['delay'] as String),
    jitterMs: ms(null, o['jitter'] as String),
  );
  final pB2A = _Profile(
    dropPct: pct(o['drop-b2a'] as String?, o['drop'] as String),
    reorderPct: pct(null, o['reorder'] as String),
    duplicatePct: pct(null, o['duplicate'] as String),
    delayMs: ms(o['delay-b2a'] as String?, o['delay'] as String),
    jitterMs: ms(null, o['jitter'] as String),
  );

  final seed = o['seed'] != null ? int.parse(o['seed'] as String) : null;
  final rng = seed != null ? Random(seed) : Random.secure();

  // Two sockets: one bound on the public side (peer A talks to it),
  // and one ephemeral for sending to/receiving from the real target.
  final listen = await RawDatagramSocket.bind(listenAddr, listenPort);
  final upstream = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  stdout.writeln('[plsim] listen ${listenAddr.address}:$listenPort '
      '→ ${targetAddr.address}:$targetPort');
  stdout.writeln('[plsim] A→B drop=${(pA2B.dropPct * 100).toStringAsFixed(1)}% '
      'delay=${pA2B.delayMs}±${pA2B.jitterMs}ms');
  stdout.writeln('[plsim] B→A drop=${(pB2A.dropPct * 100).toStringAsFixed(1)}% '
      'delay=${pB2A.delayMs}±${pB2A.jitterMs}ms');

  InternetAddress? peerA;
  int peerAPort = 0;
  final s = _Stats();

  void schedule(_Profile p, Uint8List bytes, void Function(Uint8List) deliver) {
    s.rx++;
    if (rng.nextDouble() < p.dropPct) {
      s.dropped++;
      return;
    }
    final dups = rng.nextDouble() < p.duplicatePct ? 2 : 1;
    if (dups > 1) s.duplicated++;
    for (var i = 0; i < dups; i++) {
      // Reorder = add an extra random delay on this packet so it
      // arrives after a normally-delayed neighbour.
      final extra = rng.nextDouble() < p.reorderPct
          ? Duration(milliseconds: rng.nextInt(100) + 20)
          : Duration.zero;
      final d = p.sampleDelay(rng) + extra;
      if (d == Duration.zero) {
        deliver(bytes);
        s.delivered++;
      } else {
        Timer(d, () {
          deliver(bytes);
          s.delivered++;
        });
        if (extra > Duration.zero) s.reordered++;
      }
    }
  }

  listen.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = listen.receive();
    if (dg == null) return;
    peerA = dg.address;
    peerAPort = dg.port;
    schedule(pA2B, dg.data, (b) {
      upstream.send(b, targetAddr, targetPort);
    });
  });

  upstream.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = upstream.receive();
    if (dg == null) return;
    final pa = peerA;
    if (pa == null) return; // No peer A known yet, drop.
    schedule(pB2A, dg.data, (b) {
      listen.send(b, pa, peerAPort);
    });
  });

  Timer.periodic(const Duration(seconds: 5), (_) {
    stdout.writeln('[plsim] rx=${s.rx} delivered=${s.delivered} '
        'dropped=${s.dropped} reordered=${s.reordered} '
        'duplicated=${s.duplicated}');
  });

  await Completer<void>().future;
  return 0;
}
