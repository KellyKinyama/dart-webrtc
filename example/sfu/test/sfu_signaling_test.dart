// Integration tests for the HTTP + WebSocket signaling layer.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc_sfu_example/sfu_server.dart';
import 'package:test/test.dart';

/// Buffered reader for a JSON-message WebSocket. Captures every frame
/// the moment it arrives so later `nextWhere` calls don't miss messages.
class WsReader {
  final List<Map<String, dynamic>> _buffer = [];
  final List<Completer<void>> _waiters = [];
  late final StreamSubscription _sub;

  WsReader(WebSocket ws) {
    _sub = ws.listen((data) {
      _buffer.add(jsonDecode(data as String) as Map<String, dynamic>);
      for (final w in _waiters) {
        if (!w.isCompleted) w.complete();
      }
      _waiters.clear();
    });
  }

  Future<Map<String, dynamic>> nextWhere(
    bool Function(Map<String, dynamic>) match, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final idx = _buffer.indexWhere(match);
      if (idx >= 0) return _buffer.removeAt(idx);
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) {
        throw TimeoutException(
            'no matching WS message within $timeout (buffer=$_buffer)');
      }
      final c = Completer<void>();
      _waiters.add(c);
      await c.future.timeout(remaining, onTimeout: () {});
    }
  }

  Future<void> close() => _sub.cancel();
}

void main() {
  late SfuServerHandle handle;

  setUp(() async {
    handle = await runSfuServer(
      ip: '127.0.0.1',
      port: 0,
      rtpBase: 0,
      quiet: true,
    );
  });

  tearDown(() async {
    await handle.close();
  });

  Uri httpUri(String path) =>
      Uri.parse('http://127.0.0.1:${handle.port}$path');

  Future<Map<String, dynamic>> getJson(String path) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(httpUri(path));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  test('GET /health returns ok with zero participants', () async {
    final j = await getJson('/health');
    expect(j['status'], 'ok');
    expect(j['participants'], 0);
  });

  test('GET /stats returns the empty snapshot shape', () async {
    final j = await getJson('/stats');
    expect(j['participants'], isEmpty);
    final fwd = j['forwarding'] as Map<String, dynamic>;
    expect(fwd, containsPair('rtpForwarded', 0));
    expect(fwd, containsPair('pliSent', 0));
    expect(fwd, containsPair('rtxForwarded', 0));
  });

  test('GET / returns the demo HTML', () async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(httpUri('/'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      expect(res.statusCode, 200);
      expect(body, contains('pure_dart_webrtc SFU demo'));
      expect(body, contains('RTCPeerConnection'));
    } finally {
      client.close();
    }
  });

  test('GET /missing returns 404', () async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(httpUri('/does-not-exist'));
      final res = await req.close();
      await res.drain<void>();
      expect(res.statusCode, 404);
    } finally {
      client.close();
    }
  });

  test(
      'WebSocket join flow: server replies with joined and broadcasts '
      'peer-joined to other clients', () async {
    final aliceWs =
        await WebSocket.connect('ws://127.0.0.1:${handle.port}/ws');
    addTearDown(() => aliceWs.close());
    final aliceR = WsReader(aliceWs);
    addTearDown(aliceR.close);

    aliceWs.add(jsonEncode({'type': 'join', 'id': 'alice', 'name': 'Alice'}));
    final aliceJoined = await aliceR.nextWhere((m) => m['type'] == 'joined');
    expect(aliceJoined['id'], 'alice');

    final s1 = await getJson('/stats');
    final ids =
        (s1['participants'] as List).map((p) => (p as Map)['id']).toList();
    expect(ids, contains('alice'));

    final bobWs = await WebSocket.connect('ws://127.0.0.1:${handle.port}/ws');
    addTearDown(() => bobWs.close());
    final bobR = WsReader(bobWs);
    addTearDown(bobR.close);
    bobWs.add(jsonEncode({'type': 'join', 'id': 'bob', 'name': 'Bob'}));

    final bobJoined = await bobR.nextWhere((m) => m['type'] == 'joined');
    expect(bobJoined['id'], 'bob');

    final peerJoined = await aliceR
        .nextWhere((m) => m['type'] == 'peer-joined' && m['id'] == 'bob');
    expect(peerJoined['name'], 'Bob');

    final h = await getJson('/health');
    expect(h['participants'], 2);
  });

  test('WebSocket close removes the participant and broadcasts peer-left',
      () async {
    final aliceWs =
        await WebSocket.connect('ws://127.0.0.1:${handle.port}/ws');
    final aliceR = WsReader(aliceWs);

    final bobWs = await WebSocket.connect('ws://127.0.0.1:${handle.port}/ws');
    addTearDown(() => bobWs.close());
    final bobR = WsReader(bobWs);
    addTearDown(bobR.close);

    aliceWs.add(jsonEncode({'type': 'join', 'id': 'alice'}));
    await aliceR.nextWhere((m) => m['type'] == 'joined');

    bobWs.add(jsonEncode({'type': 'join', 'id': 'bob'}));
    await bobR.nextWhere((m) => m['type'] == 'joined');
    await aliceR
        .nextWhere((m) => m['type'] == 'peer-joined' && m['id'] == 'bob');

    await aliceWs.close();
    final peerLeft = await bobR
        .nextWhere((m) => m['type'] == 'peer-left' && m['id'] == 'alice');
    expect(peerLeft['id'], 'alice');

    final h = await getJson('/health');
    expect(h['participants'], 1);

    await aliceR.close();
  });
}
