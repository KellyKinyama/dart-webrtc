// Phase 26 — graceful drain.
//
// Verifies:
//  * /healthz returns 200/"ok" before drain, 503/"draining" after.
//  * POST /admin/drain flips the flag.
//  * /ws/<sid> upgrade is rejected with 503 once draining.
//  * Existing sockets are unaffected (we don't open any here; that
//    behaviour is exercised implicitly by [IonSfuServerHandle.drain]
//    leaving `sharded` and `cluster` running).

import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc_ion_style_sfu/src/sfu_server.dart';
import 'package:test/test.dart';

void main() {
  group('Phase 26 — graceful drain', () {
    late IonSfuServerHandle handle;

    setUp(() async {
      handle = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: 0,
        rtpBase: 19401,
        quiet: true,
      );
    });

    tearDown(() async {
      await handle.close();
    });

    test('/healthz reports ok then draining; /ws rejected with 503', () async {
      final base = 'http://127.0.0.1:${handle.port}';
      final client = HttpClient();
      addTearDown(client.close);

      // Pre-drain: 200 ok.
      var req = await client.getUrl(Uri.parse('$base/healthz'));
      var res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      var body = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
      expect(body['status'], 'ok');

      // Trigger drain via the admin endpoint.
      req = await client.postUrl(Uri.parse('$base/admin/drain'));
      res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      await res.drain();
      expect(handle.draining, isTrue);

      // Post-drain: /healthz reports 503/"draining".
      req = await client.getUrl(Uri.parse('$base/healthz'));
      res = await req.close();
      expect(res.statusCode, HttpStatus.serviceUnavailable);
      body = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
      expect(body['status'], 'draining');

      // Post-drain: /ws/<sid> upgrade refused with 503.
      req = await client.getUrl(Uri.parse('$base/ws/room-1'));
      req.headers.set('Connection', 'Upgrade');
      req.headers.set('Upgrade', 'websocket');
      req.headers.set('Sec-WebSocket-Key', 'dGhlIHNhbXBsZSBub25jZQ==');
      req.headers.set('Sec-WebSocket-Version', '13');
      res = await req.close();
      expect(res.statusCode, HttpStatus.serviceUnavailable);
      await res.drain();
    });

    test('handle.drain() is idempotent', () async {
      expect(handle.draining, isFalse);
      handle.drain();
      handle.drain();
      expect(handle.draining, isTrue);
    });
  });
}
