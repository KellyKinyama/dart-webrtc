// sfu_server.dart — auth + maxRooms WS guard coverage.

import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

Future<HttpClientResponse> _httpGet(int port, String path,
    {Map<String, String>? headers}) async {
  final c = HttpClient();
  final req = await c.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
  headers?.forEach(req.headers.set);
  // Inhibit websocket upgrade — we just want the HTTP status.
  final resp = await req.close();
  // Consume body so the socket can close.
  await resp.drain<void>();
  c.close(force: true);
  return resp;
}

Future<HttpClientResponse> _wsUpgradeAttempt(int port, String path,
    {String? bearerToken}) async {
  final c = HttpClient();
  final req = await c.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
  req.headers
    ..set(HttpHeaders.connectionHeader, 'Upgrade')
    ..set(HttpHeaders.upgradeHeader, 'websocket')
    ..set('Sec-WebSocket-Version', '13')
    ..set('Sec-WebSocket-Key', 'dGhlIHNhbXBsZSBub25jZQ==');
  if (bearerToken != null) {
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  }
  final resp = await req.close();
  await resp.drain<void>();
  c.close(force: true);
  return resp;
}

void main() {
  group('sfu_server WS auth + maxRooms guards', () {
    test('rejects WS upgrade with 401 when authToken is missing', () async {
      final h = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: 0,
        rtpBase: 55400,
        announceIp: '127.0.0.1',
        quiet: true,
        authToken: 'sekret',
      );
      addTearDown(h.close);
      final resp = await _wsUpgradeAttempt(h.port, '/ws/room1');
      expect(resp.statusCode, HttpStatus.unauthorized);
    });

    test('rejects WS upgrade with 401 when token is wrong', () async {
      final h = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: 0,
        rtpBase: 55410,
        announceIp: '127.0.0.1',
        quiet: true,
        authToken: 'sekret',
      );
      addTearDown(h.close);
      final resp =
          await _wsUpgradeAttempt(h.port, '/ws/room1', bearerToken: 'wrong');
      expect(resp.statusCode, HttpStatus.unauthorized);
    });

    test('accepts WS upgrade via ?token= query param', () async {
      final h = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: 0,
        rtpBase: 55420,
        announceIp: '127.0.0.1',
        quiet: true,
        authToken: 'sekret',
      );
      addTearDown(h.close);
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${h.port}/ws/room1?token=sekret',
      );
      addTearDown(() async {
        await ws.close();
      });
      expect(ws.readyState, WebSocket.open);
    });

    test('rejects new room with 503 when maxRooms cap is hit', () async {
      final h = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: 0,
        rtpBase: 55430,
        announceIp: '127.0.0.1',
        quiet: true,
        maxRooms: 1,
      );
      addTearDown(h.close);

      // Pre-create the shard directly so shardCount == maxRooms before
      // the WS upgrade attempt for a different sid hits the guard.
      await h.sharded.getOrCreate('alpha');
      expect(h.sharded.shardCount, 1);

      // Second room should be rejected with 503 + JSON body.
      final c = HttpClient();
      final req =
          await c.getUrl(Uri.parse('http://127.0.0.1:${h.port}/ws/beta'));
      req.headers
        ..set(HttpHeaders.connectionHeader, 'Upgrade')
        ..set(HttpHeaders.upgradeHeader, 'websocket')
        ..set('Sec-WebSocket-Version', '13')
        ..set('Sec-WebSocket-Key', 'dGhlIHNhbXBsZSBub25jZQ==');
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.serviceUnavailable);
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, Object?>;
      expect(json['error'], 'maxRoomsReached');
      expect(json['limit'], 1);
      c.close(force: true);
    });

    test('existing room stays reachable when maxRooms cap is hit', () async {
      final h = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: 0,
        rtpBase: 55440,
        announceIp: '127.0.0.1',
        quiet: true,
        maxRooms: 1,
      );
      addTearDown(h.close);

      await h.sharded.getOrCreate('alpha');
      expect(h.sharded.shardCount, 1);

      // WS upgrade for the SAME session must succeed (cap is per new room).
      final ws = await WebSocket.connect('ws://127.0.0.1:${h.port}/ws/alpha');
      addTearDown(() async {
        await ws.close();
      });
      expect(ws.readyState, WebSocket.open);
    });

    test('/admin/drain rejects without bearer when authToken set', () async {
      final h = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: 0,
        rtpBase: 55450,
        announceIp: '127.0.0.1',
        quiet: true,
        authToken: 'sekret',
      );
      addTearDown(h.close);
      final c = HttpClient();
      final req =
          await c.postUrl(Uri.parse('http://127.0.0.1:${h.port}/admin/drain'));
      final resp = await req.close();
      await resp.drain<void>();
      expect(resp.statusCode, HttpStatus.unauthorized);
      c.close(force: true);
      expect(h.draining, isFalse);
    });
  });
}
