// HTTP-edge coverage tests for [runIonStyleSfuServer]. Focuses on
// branches that the cluster_phase* tests don't exercise: standalone
// (non-cluster) /stats, /metrics, /cluster (404), /locate, OPTIONS
// preflight, unknown paths; /admin/drain authentication branches;
// /ws/<sid> validation branches (empty, invalid characters, missing
// auth, bad auth, query-token, bearer header); and the cluster
// argument-error guards in `runIonStyleSfuServer` itself.

import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc_ion_style_sfu/src/cluster/locator.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/src/sfu_server.dart';
import 'package:test/test.dart';

Future<HttpClientResponse> _get(
  HttpClient client,
  int port,
  String path, {
  Map<String, String> headers = const {},
}) async {
  final req =
      await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
  headers.forEach(req.headers.set);
  return req.close();
}

Future<HttpClientResponse> _post(
  HttpClient client,
  int port,
  String path, {
  Map<String, String> headers = const {},
}) async {
  final req =
      await client.postUrl(Uri.parse('http://127.0.0.1:$port$path'));
  headers.forEach(req.headers.set);
  return req.close();
}

Future<dynamic> _json(HttpClientResponse res) async {
  return jsonDecode(await res.transform(utf8.decoder).join());
}

Future<HttpClientResponse> _wsUpgrade(
  HttpClient client,
  int port,
  String path, {
  Map<String, String> headers = const {},
}) async {
  final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
  req.headers.set('Connection', 'Upgrade');
  req.headers.set('Upgrade', 'websocket');
  req.headers.set('Sec-WebSocket-Key', 'dGhlIHNhbXBsZSBub25jZQ==');
  req.headers.set('Sec-WebSocket-Version', '13');
  headers.forEach(req.headers.set);
  return req.close();
}

void main() {
  group('runIonStyleSfuServer — argument validation', () {
    test('cluster mode requires selfClusterId', () async {
      expect(
        () => runIonStyleSfuServer(
          ip: '127.0.0.1',
          port: 0,
          rtpBase: 19500,
          quiet: true,
          clusterPeers: [
            ClusterPeer(
                id: 'a', host: '127.0.0.1', httpPort: 1, relayPort: 2),
          ],
          relayPort: 19501,
        ),
        throwsArgumentError,
      );
    });

    test('cluster mode requires relayPort', () async {
      expect(
        () => runIonStyleSfuServer(
          ip: '127.0.0.1',
          port: 0,
          rtpBase: 19510,
          quiet: true,
          clusterPeers: [
            ClusterPeer(
                id: 'a', host: '127.0.0.1', httpPort: 1, relayPort: 2),
          ],
          selfClusterId: 'a',
        ),
        throwsArgumentError,
      );
    });

    test('selfClusterId must match a peer', () async {
      expect(
        () => runIonStyleSfuServer(
          ip: '127.0.0.1',
          port: 0,
          rtpBase: 19520,
          quiet: true,
          clusterPeers: [
            ClusterPeer(
                id: 'a', host: '127.0.0.1', httpPort: 1, relayPort: 2),
          ],
          selfClusterId: 'nope',
          relayPort: 19521,
        ),
        throwsArgumentError,
      );
    });
  });

  group('runIonStyleSfuServer — standalone HTTP edge', () {
    late IonSfuServerHandle handle;
    late HttpClient client;
    late int port;

    setUp(() async {
      handle = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: 0,
        rtpBase: 19600,
        quiet: true,
      );
      port = handle.port;
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await handle.close();
    });

    test('OPTIONS preflight returns 204 with CORS headers', () async {
      final req =
          await client.openUrl('OPTIONS', Uri.parse('http://127.0.0.1:$port/'));
      final res = await req.close();
      expect(res.statusCode, HttpStatus.noContent);
      expect(res.headers.value('access-control-allow-origin'), '*');
      await res.drain();
    });

    test('GET /stats returns JSON snapshot', () async {
      final res = await _get(client, port, '/stats');
      expect(res.statusCode, HttpStatus.ok);
      expect(res.headers.contentType?.mimeType, 'application/json');
      final body = await _json(res);
      expect(body, isA<Map>());
    });

    test('GET /metrics returns Prometheus text', () async {
      final res = await _get(client, port, '/metrics');
      expect(res.statusCode, HttpStatus.ok);
      expect(res.headers.contentType?.mimeType, 'text/plain');
      final body = await res.transform(utf8.decoder).join();
      expect(body, isNotEmpty);
    });

    test('GET /cluster is 404 in non-cluster mode', () async {
      final res = await _get(client, port, '/cluster');
      expect(res.statusCode, HttpStatus.notFound);
      final body = await _json(res);
      expect(body['error'], 'not in cluster mode');
    });

    test('GET /locate reports self-ownership when no locator', () async {
      final res = await _get(client, port, '/locate?sid=room1');
      expect(res.statusCode, HttpStatus.ok);
      final body = await _json(res) as Map;
      expect(body['sid'], 'room1');
      expect((body['owner'] as Map)['self'], isTrue);
    });

    test('unknown path returns 404', () async {
      final res = await _get(client, port, '/no-such-thing');
      expect(res.statusCode, HttpStatus.notFound);
      await res.drain();
    });

    test('GET /healthz reports ok and standalone mode', () async {
      final res = await _get(client, port, '/healthz');
      expect(res.statusCode, HttpStatus.ok);
      final body = await _json(res) as Map;
      expect(body['status'], 'ok');
      expect(body['mode'], 'sharded');
    });

    test('/ws/ with empty sid returns 400', () async {
      final res = await _wsUpgrade(client, port, '/ws/');
      expect(res.statusCode, HttpStatus.badRequest);
      final body = await _json(res) as Map;
      expect(body['error'], 'invalidSessionId');
    });

    test('/ws/ with disallowed characters returns 400', () async {
      // Slash inside the sid component is filtered earlier; pick an
      // illegal char (`!`) that still routes here.
      final res = await _wsUpgrade(client, port, '/ws/bad%21id');
      expect(res.statusCode, HttpStatus.badRequest);
      final body = await _json(res) as Map;
      expect(body['error'], 'invalidSessionId');
    });

    test('/ws/ with id over the length cap returns 400', () async {
      final longSid = 'a' * 200;
      final res = await _wsUpgrade(client, port, '/ws/$longSid');
      expect(res.statusCode, HttpStatus.badRequest);
    });
  });

  group('runIonStyleSfuServer — auth-token branches', () {
    late IonSfuServerHandle handle;
    late HttpClient client;
    late int port;
    const token = 'sekrit-token-123';

    setUp(() async {
      handle = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: 0,
        rtpBase: 19700,
        quiet: true,
        authToken: token,
      );
      port = handle.port;
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await handle.close();
    });

    test('POST /admin/drain without token → 401', () async {
      final res = await _post(client, port, '/admin/drain');
      expect(res.statusCode, HttpStatus.unauthorized);
      await res.drain();
      expect(handle.draining, isFalse);
    });

    test('POST /admin/drain with wrong token → 401', () async {
      final res = await _post(client, port, '/admin/drain?token=wrong');
      expect(res.statusCode, HttpStatus.unauthorized);
      await res.drain();
      expect(handle.draining, isFalse);
    });

    test('POST /admin/drain with right token via query → 200', () async {
      final res = await _post(client, port, '/admin/drain?token=$token');
      expect(res.statusCode, HttpStatus.ok);
      await res.drain();
      expect(handle.draining, isTrue);
    });

    test('POST /admin/drain with right token via Bearer header → 200',
        () async {
      final res = await _post(
        client,
        port,
        '/admin/drain',
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      );
      expect(res.statusCode, HttpStatus.ok);
      await res.drain();
      expect(handle.draining, isTrue);
    });
  });
}
