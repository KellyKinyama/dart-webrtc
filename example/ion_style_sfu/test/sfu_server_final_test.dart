// sfu_server final-stragglers coverage:
//   * quiet:false + cluster mode -> 'cluster mode online' + 'sfu listening' info logs.
//   * Shard close -> router closeAll -> ws.close on every live socket.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

void main() {
  test('cluster mode + quiet:false drives both info-log branches', () async {
    final self = ClusterPeer.parse('127.0.0.1:19601:19602');
    final peer = ClusterPeer.parse('127.0.0.1:19603:19604');
    final h = await runIonStyleSfuServer(
      ip: '127.0.0.1',
      port: 0,
      rtpBase: 56900,
      announceIp: '127.0.0.1',
      // quiet: false intentionally so the 'cluster mode online' +
      // 'sfu listening' log.info branches execute (lines 260-273).
      clusterPeers: [self, peer],
      selfClusterId: self.id,
      relayPort: self.relayPort,
    );
    addTearDown(h.close);
    // Sanity: /healthz reports cluster mode.
    final c = HttpClient();
    final req =
        await c.getUrl(Uri.parse('http://127.0.0.1:${h.port}/healthz'));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    c.close(force: true);
    final j = jsonDecode(body) as Map<String, Object?>;
    expect(j['mode'], 'cluster');
    expect(j['self'], self.id);
  });

  test('ShardClosedEvent triggers router.closeAll -> ws.close', () async {
    final h = await runIonStyleSfuServer(
      ip: '127.0.0.1',
      port: 0,
      rtpBase: 56920,
      announceIp: '127.0.0.1',
      quiet: true,
    );
    addTearDown(h.close);

    final ws = await WebSocket.connect('ws://127.0.0.1:${h.port}/ws/r1');
    ws.add(jsonEncode({'type': 'join', 'uid': 'alice'}));
    // Drain until 'joined' arrives so we know the shard exists.
    final it = StreamIterator(ws);
    var joined = false;
    for (var i = 0; i < 32; i++) {
      final ok = await it
          .moveNext()
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      if (!ok) break;
      final raw = it.current;
      if (raw is String) {
        try {
          final m = jsonDecode(raw);
          if (m is Map && m['type'] == 'joined') {
            joined = true;
            break;
          }
        } catch (_) {}
      }
    }
    expect(joined, isTrue);
    expect(ws.readyState, WebSocket.open);

    // Close the shard -> ShardClosedEvent -> router.closeAll
    // -> ws.close on the still-open socket.
    await h.sharded.closeShard('r1');

    // Drain remaining frames; the close should land within ~1s.
    while (await it.moveNext().timeout(const Duration(seconds: 2),
        onTimeout: () => false)) {
      // discard
    }
    expect(ws.readyState, anyOf(WebSocket.closed, WebSocket.closing));
    await it.cancel();
  });
}
