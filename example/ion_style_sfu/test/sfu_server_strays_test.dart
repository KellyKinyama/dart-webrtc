// sfu_server batch D — extra strays:
//   * Plain HTTP GET to /ws/<sid> (no Upgrade headers) -> the
//     WebSocketTransformer.upgrade future rejects -> onError branch
//     (lines 486-487) fires with quiet:false so log.warn runs.
//   * Plain HTTP GET to / (unknown path) -> 404 fallback (495-497).

import 'dart:io';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

void main() {
  test('plain GET /ws/<sid> drives the WS-upgrade onError branch', () async {
    final h = await runIonStyleSfuServer(
      ip: '127.0.0.1',
      port: 0,
      rtpBase: 57000,
      announceIp: '127.0.0.1',
      // quiet: false so the log.warn('ws upgrade error', ...) runs.
    );
    addTearDown(h.close);
    final c = HttpClient();
    final req = await c.getUrl(Uri.parse('http://127.0.0.1:${h.port}/ws/r1'));
    // Deliberately do NOT set Upgrade/Connection headers; the
    // upgrade future inside the server rejects, hitting onError.
    final resp = await req.close();
    await resp.drain<void>();
    c.close(force: true);
    // The server sends some non-101 response (500 in dart:io). We only
    // care that the onError branch ran without throwing.
    expect(resp.statusCode, isNot(HttpStatus.switchingProtocols));
  });

  test('GET on an unknown path returns 404', () async {
    final h = await runIonStyleSfuServer(
      ip: '127.0.0.1',
      port: 0,
      rtpBase: 57020,
      announceIp: '127.0.0.1',
      quiet: true,
    );
    addTearDown(h.close);
    final c = HttpClient();
    final req =
        await c.getUrl(Uri.parse('http://127.0.0.1:${h.port}/no/such/path'));
    final resp = await req.close();
    await resp.drain<void>();
    c.close(force: true);
    expect(resp.statusCode, HttpStatus.notFound);
  });
}
