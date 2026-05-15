// Phase B14 — Room Service REST API tests. Exercises:
//   * GET    /api/rooms                              (empty + populated)
//   * POST   /api/rooms                              (create + duplicate + bad input)
//   * GET    /api/rooms/<sid>
//   * DELETE /api/rooms/<sid>                        (close)
//   * GET    /api/rooms/<sid>/participants
//   * DELETE /api/rooms/<sid>/participants/<uid>     (kick)
//   * Auth gate (401 without token, 200 with bearer + with ?token=)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

Future<HttpClientResponse> _req(
  HttpClient c,
  String method,
  Uri uri, {
  Object? jsonBody,
  String? bearer,
}) async {
  final r = await c.openUrl(method, uri);
  if (bearer != null) {
    r.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
  }
  if (jsonBody != null) {
    r.headers.contentType = ContentType.json;
    r.add(utf8.encode(jsonEncode(jsonBody)));
  }
  return r.close();
}

Future<Object?> _json(HttpClientResponse r) async {
  final text = await utf8.decoder.bind(r).join();
  if (text.isEmpty) return null;
  return jsonDecode(text);
}

void main() {
  late IonSfuServerHandle handle;
  late HttpClient client;
  late Uri base;

  Future<void> spawn({String? token}) async {
    handle = await runIonStyleSfuServer(
      ip: '127.0.0.1',
      port: 0,
      rtpBase: 58000,
      announceIp: '127.0.0.1',
      quiet: true,
      authToken: token,
    );
    client = HttpClient();
    base = Uri.parse('http://127.0.0.1:${handle.port}');
  }

  tearDown(() async {
    client.close(force: true);
    await handle.close();
  });

  group('Room Service REST (Phase B14)', () {
    test('GET /api/rooms returns empty list on a fresh server', () async {
      await spawn();
      final r = await _req(client, 'GET', base.resolve('/api/rooms'));
      expect(r.statusCode, 200);
      final body = await _json(r) as Map<String, Object?>;
      expect(body['rooms'], isEmpty);
    });

    test(
        'POST /api/rooms creates a room (201) and idempotent retry returns 200',
        () async {
      await spawn();
      final r1 = await _req(
        client,
        'POST',
        base.resolve('/api/rooms'),
        jsonBody: {'sid': 'room-a'},
      );
      expect(r1.statusCode, 201);
      final b1 = await _json(r1) as Map<String, Object?>;
      expect(b1, {'sid': 'room-a', 'created': true});

      final r2 = await _req(
        client,
        'POST',
        base.resolve('/api/rooms'),
        jsonBody: {'sid': 'room-a'},
      );
      expect(r2.statusCode, 200);
      final b2 = await _json(r2) as Map<String, Object?>;
      expect(b2['created'], false);

      // Now appears in the list.
      final r3 = await _req(client, 'GET', base.resolve('/api/rooms'));
      final b3 = await _json(r3) as Map<String, Object?>;
      final rooms = (b3['rooms'] as List).cast<Map<String, Object?>>();
      expect(rooms, hasLength(1));
      expect(rooms.first['sid'], 'room-a');
      expect(rooms.first['numParticipants'], 0);
    });

    test('POST /api/rooms rejects empty/unsafe sid and bad JSON', () async {
      await spawn();
      final r1 = await _req(client, 'POST', base.resolve('/api/rooms'),
          jsonBody: {'sid': ''});
      expect(r1.statusCode, 400);
      final r2 = await _req(client, 'POST', base.resolve('/api/rooms'),
          jsonBody: {'sid': 'bad name'});
      expect(r2.statusCode, 400);
      // Bad JSON.
      final raw = await client.openUrl('POST', base.resolve('/api/rooms'));
      raw.headers.contentType = ContentType.json;
      raw.add(utf8.encode('not-json'));
      final r3 = await raw.close();
      expect(r3.statusCode, 400);
      await _json(r3);
    });

    test('GET /api/rooms/<sid> 404 on missing room', () async {
      await spawn();
      final r = await _req(client, 'GET', base.resolve('/api/rooms/nope'));
      expect(r.statusCode, 404);
      await _json(r);
    });

    test('DELETE /api/rooms/<sid> closes the room', () async {
      await spawn();
      await _req(client, 'POST', base.resolve('/api/rooms'),
          jsonBody: {'sid': 'r-del'});
      final r = await _req(client, 'DELETE', base.resolve('/api/rooms/r-del'));
      expect(r.statusCode, 200);
      final body = await _json(r) as Map<String, Object?>;
      expect(body['closed'], true);
      // Subsequent GET is a 404.
      final r2 = await _req(client, 'GET', base.resolve('/api/rooms/r-del'));
      expect(r2.statusCode, 404);
      await _json(r2);
    });

    test('GET /api/rooms/<sid>/participants reflects WS joins', () async {
      await spawn();
      await _req(client, 'POST', base.resolve('/api/rooms'),
          jsonBody: {'sid': 'r-ws'});
      // Open a WS, send join, wait for the joined response.
      final ws =
          await WebSocket.connect('ws://127.0.0.1:${handle.port}/ws/r-ws');
      addTearDown(() async {
        if (ws.readyState == WebSocket.open) await ws.close();
      });
      final joined = Completer<void>();
      ws.listen((data) {
        final msg = jsonDecode(data as String) as Map<String, Object?>;
        if (msg['type'] == 'joined' && !joined.isCompleted) {
          joined.complete();
        }
      });
      ws.add(jsonEncode({'type': 'join', 'uid': 'alice'}));
      await joined.future.timeout(const Duration(seconds: 5));

      final r = await _req(
          client, 'GET', base.resolve('/api/rooms/r-ws/participants'));
      expect(r.statusCode, 200);
      final body = await _json(r) as Map<String, Object?>;
      final ps = (body['participants'] as List).cast<Map<String, Object?>>();
      expect(ps.map((e) => e['uid']), contains('alice'));
    });

    test('DELETE /api/rooms/<sid>/participants/<uid> kicks the WS', () async {
      await spawn();
      await _req(client, 'POST', base.resolve('/api/rooms'),
          jsonBody: {'sid': 'r-kick'});
      final ws =
          await WebSocket.connect('ws://127.0.0.1:${handle.port}/ws/r-kick');
      final joined = Completer<void>();
      final closed = Completer<void>();
      ws.listen(
        (data) {
          final msg = jsonDecode(data as String) as Map<String, Object?>;
          if (msg['type'] == 'joined' && !joined.isCompleted) {
            joined.complete();
          }
        },
        onDone: () {
          if (!closed.isCompleted) closed.complete();
        },
      );
      ws.add(jsonEncode({'type': 'join', 'uid': 'bob'}));
      await joined.future.timeout(const Duration(seconds: 5));

      final r = await _req(
          client, 'DELETE', base.resolve('/api/rooms/r-kick/participants/bob'));
      expect(r.statusCode, 200);
      final body = await _json(r) as Map<String, Object?>;
      expect(body, {'sid': 'r-kick', 'uid': 'bob', 'kicked': true});

      // The server-initiated close should reach the client quickly.
      await closed.future.timeout(const Duration(seconds: 5));

      // 404 on a second kick attempt.
      final r2 = await _req(
          client, 'DELETE', base.resolve('/api/rooms/r-kick/participants/bob'));
      expect(r2.statusCode, 404);
      await _json(r2);
    });

    test('auth gate: 401 without token, 200 with bearer + ?token=', () async {
      await spawn(token: 's3cret');

      final r1 = await _req(client, 'GET', base.resolve('/api/rooms'));
      expect(r1.statusCode, 401);
      await _json(r1);

      final r2 = await _req(
        client,
        'GET',
        base.resolve('/api/rooms'),
        bearer: 's3cret',
      );
      expect(r2.statusCode, 200);
      await _json(r2);

      final r3 = await _req(
        client,
        'GET',
        base.resolve('/api/rooms?token=s3cret'),
      );
      expect(r3.statusCode, 200);
      await _json(r3);

      final r4 = await _req(
        client,
        'GET',
        base.resolve('/api/rooms'),
        bearer: 'wrong',
      );
      expect(r4.statusCode, 401);
      await _json(r4);
    });

    test('GET on /api/rooms with PUT method returns 405', () async {
      await spawn();
      final r = await _req(client, 'PUT', base.resolve('/api/rooms'));
      expect(r.statusCode, 405);
      await _json(r);
    });
  });
}
