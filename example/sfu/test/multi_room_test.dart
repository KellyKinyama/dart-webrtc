// End-to-end test for the multi-room SFU stack: spawn the router with
// real worker isolates, hit the discovery endpoint, and connect a
// WebSocket directly to the worker that owns the room.

import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc_sfu_example/multi_room_server.dart';
import 'package:test/test.dart';

void main() {
  group('MultiRoomServer', () {
    late MultiRoomServerHandle handle;

    setUp(() async {
      handle = await runMultiRoomServer(const MultiRoomServerConfig(
        ip: '127.0.0.1',
        routerPort: 0, // OS pick
        workerCount: 2,
        announceIp: '127.0.0.1',
      ));
    });

    tearDown(() async {
      await handle.close();
    });

    test('boots two worker isolates with distinct OS-allocated ports',
        () async {
      expect(handle.workerPorts.length, 2);
      expect(handle.workerPorts[0], greaterThan(0));
      expect(handle.workerPorts[1], greaterThan(0));
      expect(handle.workerPorts[0], isNot(equals(handle.workerPorts[1])));
      expect(handle.workerPorts[0], isNot(equals(handle.port)));
    });

    test('/health aggregates worker reports', () async {
      final client = HttpClient();
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:${handle.port}/health'));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      client.close(force: true);
      expect(resp.statusCode, 200);
      final parsed = jsonDecode(body) as Map<String, dynamic>;
      expect(parsed['status'], 'ok');
      expect((parsed['workers'] as List).length, 2);
      expect((parsed['totals'] as Map<String, dynamic>)['rooms'], 0);
    });

    test('/room/<id>/locate returns a worker URL with ws:// scheme', () async {
      final client = HttpClient();
      final req = await client.getUrl(
          Uri.parse('http://127.0.0.1:${handle.port}/room/lobby/locate'));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      client.close(force: true);
      expect(resp.statusCode, 200);
      final parsed = jsonDecode(body) as Map<String, dynamic>;
      expect(parsed['roomId'], 'lobby');
      expect(parsed['port'], isIn(handle.workerPorts));
      expect((parsed['ws'] as String).startsWith('ws://'), isTrue);
      expect((parsed['ws'] as String).contains('/ws/lobby'), isTrue);
    });

    test('routing is deterministic per room id', () {
      // Same room → same worker. Don't rely on which worker, just that
      // the choice is stable.
      final a1 = pickWorkerForRoom('alpha', 4);
      final a2 = pickWorkerForRoom('alpha', 4);
      final b = pickWorkerForRoom('bravo', 4);
      expect(a1, a2);
      expect(a1, isNonNegative);
      expect(a1, lessThan(4));
      expect(b, isNonNegative);
      expect(b, lessThan(4));
    });

    test('worker port serves /health independently of router', () async {
      final client = HttpClient();
      final req = await client.getUrl(
          Uri.parse('http://127.0.0.1:${handle.workerPorts[0]}/health'));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      client.close(force: true);
      expect(resp.statusCode, 200);
      final parsed = jsonDecode(body) as Map<String, dynamic>;
      expect(parsed['label'], startsWith('worker-'));
      expect(parsed['rooms'], 0);
    });
  });

  group('MultiRoomServer routing', () {
    test('FNV-1a partitioning is uniform-ish across 1000 ids over 8 workers',
        () {
      final counts = List<int>.filled(8, 0);
      for (var i = 0; i < 1000; i++) {
        counts[pickWorkerForRoom('room-$i', 8)]++;
      }
      // Every bucket should get a non-trivial share (at least ~5%).
      for (final c in counts) {
        expect(c, greaterThan(50), reason: 'partition skew: $counts');
      }
    });
  });
}
