// CLI entry point for the SFU load-test harness ("test drive").
//
// Drives the in-isolate fan-out hot path under a configurable load
// profile and prints the throughput / latency / pool / drop report.
//
// Examples:
//
//   dart run bin/load_test.dart --rooms 1 --pubs 4 --subs 3 \
//                                --pps 30 --duration 10s
//
//   dart run bin/load_test.dart --rooms 5 --pubs 5 --subs 5 --json
//
//   dart run bin/load_test.dart --no-pool   # baseline without buffer pooling

import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc_ion_style_sfu/src/load_test.dart';

Future<void> main(List<String> arguments) async {
  var rooms = 1;
  var pubs = 4;
  var subs = 3;
  var pps = 30;
  var payload = 1100;
  var duration = const Duration(seconds: 5);
  var warmup = const Duration(milliseconds: 500);
  var jitter = 512;
  var usePool = true;
  var json = false;

  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--rooms':
        rooms = int.parse(arguments[++i]);
        break;
      case '--pubs':
        pubs = int.parse(arguments[++i]);
        break;
      case '--subs':
        subs = int.parse(arguments[++i]);
        break;
      case '--pps':
        pps = int.parse(arguments[++i]);
        break;
      case '--payload':
        payload = int.parse(arguments[++i]);
        break;
      case '--duration':
        duration = _parseDuration(arguments[++i]);
        break;
      case '--warmup':
        warmup = _parseDuration(arguments[++i]);
        break;
      case '--jitter':
        jitter = int.parse(arguments[++i]);
        break;
      case '--no-pool':
        usePool = false;
        break;
      case '--json':
        json = true;
        break;
      case '-h':
      case '--help':
        stdout.writeln(_help);
        return;
    }
  }

  final cfg = LoadTestConfig(
    rooms: rooms,
    publishersPerRoom: pubs,
    subscribersPerPublisher: subs,
    packetsPerSecondPerPublisher: pps,
    payloadBytes: payload,
    duration: duration,
    warmup: warmup,
    jitterCapacity: jitter,
    usePool: usePool,
  );

  if (!json) {
    stdout.writeln('warming up for ${warmup.inMilliseconds} ms...');
  }
  final harness = LoadTestHarness(cfg);
  final report = await harness.run();

  if (json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
  } else {
    stdout.writeln(report.renderHuman());
  }
}

Duration _parseDuration(String s) {
  if (s.endsWith('ms')) {
    return Duration(milliseconds: int.parse(s.substring(0, s.length - 2)));
  }
  if (s.endsWith('s')) {
    return Duration(seconds: int.parse(s.substring(0, s.length - 1)));
  }
  if (s.endsWith('m')) {
    return Duration(minutes: int.parse(s.substring(0, s.length - 1)));
  }
  return Duration(seconds: int.parse(s));
}

const _help = '''
Usage: dart run bin/load_test.dart [options]

Workload:
  --rooms N            Number of independent rooms (default 1)
  --pubs N             Publishers per room (default 4)
  --subs N             Subscribers per publisher (default 3)
  --pps N              Packets/sec per publisher (default 30)
  --payload N          RTP payload bytes per packet (default 1100)
  --duration <T>       Steady-state measurement window, e.g. 10s, 500ms (default 5s)
  --warmup <T>         Warm-up before measurement starts (default 500ms)
  --jitter N           Jitter buffer capacity per fan-out edge (default 512)

Variants:
  --no-pool            Disable the BytePool — measures the no-pool baseline
  --json               Emit JSON instead of the human-readable report

Total fan-out edges = rooms * pubs * subs.
Aggregate target packets/sec = rooms * pubs * subs * pps.
''';
