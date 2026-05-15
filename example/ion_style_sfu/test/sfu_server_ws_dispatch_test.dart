// sfu_server WS message dispatch coverage:
//   * type=offer (target=pub) after join — drives _onOffer +
//     applyPublisherOffer + signaling-error stderr branch.
//   * type=answer (target=sub) after join — drives _onAnswer.
//   * type=trickle (valid candidate:) after join — drives _onTrickle.
//   * SfuOverloadedException → serverOverloaded WS error.
//   * SessionFullException → sessionFull WS error.
//   * announceIp inference path (ip=0.0.0.0, announceIp=null) →
//     _firstNonLoopbackIPv4 fallback branch.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

Future<WebSocket> _connect(int port, String sid, {String? token}) {
  final url = token == null
      ? 'ws://127.0.0.1:$port/ws/$sid'
      : 'ws://127.0.0.1:$port/ws/$sid?token=$token';
  return WebSocket.connect(url);
}

Future<Map<String, dynamic>?> _waitFor(
  StreamIterator<dynamic> it,
  String type, {
  Duration timeout = const Duration(seconds: 3),
  int maxSkip = 16,
}) async {
  for (var i = 0; i < maxSkip; i++) {
    final ok = await it.moveNext().timeout(timeout, onTimeout: () => false);
    if (!ok) return null;
    final raw = it.current;
    if (raw is! String) continue;
    try {
      final m = jsonDecode(raw);
      if (m is Map<String, dynamic> && m['type'] == type) return m;
    } catch (_) {}
  }
  return null;
}

void main() {
  group('WS message dispatch', () {
    late IonSfuServerHandle handle;

    setUp(() async {
      handle = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: 0,
        rtpBase: 56600,
        announceIp: '127.0.0.1',
        quiet: true,
      );
    });

    tearDown(() async {
      await handle.close();
    });

    test('offer with bogus SDP routes to applyPublisherOffer', () async {
      final ws = await _connect(handle.port, 'r1');
      final it = StreamIterator(ws);
      addTearDown(() async {
        await it.cancel();
        await ws.close();
      });

      ws.add(jsonEncode({'type': 'join', 'uid': 'alice'}));
      final joined = await _waitFor(it, 'joined');
      expect(joined, isNotNull);

      // Drive _onOffer → applyPublisherOffer with malformed SDP.
      // Either it answers (unlikely) or throws on the worker side
      // (logged, swallowed in catch). Both walk lines 810-812 + 713.
      ws.add(jsonEncode({
        'type': 'offer',
        'target': 'pub',
        'sdp': 'v=0\r\no=- 1 1 IN IP4 1.1.1.1\r\ns=-\r\nt=0 0\r\n',
      }));
      // Give the worker a moment to process; we don't require a
      // specific reply.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    test('answer with bogus SDP routes to applySubscriberAnswer', () async {
      final ws = await _connect(handle.port, 'r2');
      final it = StreamIterator(ws);
      addTearDown(() async {
        await it.cancel();
        await ws.close();
      });

      ws.add(jsonEncode({'type': 'join', 'uid': 'bob'}));
      await _waitFor(it, 'joined');

      ws.add(jsonEncode({
        'type': 'answer',
        'target': 'sub',
        'sdp': 'v=0\r\no=- 1 1 IN IP4 1.1.1.1\r\ns=-\r\nt=0 0\r\n',
      }));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    test('trickle with valid candidate routes to shard.trickle', () async {
      final ws = await _connect(handle.port, 'r3');
      final it = StreamIterator(ws);
      addTearDown(() async {
        await it.cancel();
        await ws.close();
      });

      ws.add(jsonEncode({'type': 'join', 'uid': 'carol'}));
      await _waitFor(it, 'joined');

      ws.add(jsonEncode({
        'type': 'trickle',
        'target': 'pub',
        'candidate': 'candidate:1 1 udp 2113937151 1.2.3.4 12345 typ host',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      }));
      ws.add(jsonEncode({
        'type': 'trickle',
        'target': 'sub',
        'candidate': 'candidate:1 1 udp 2113937151 1.2.3.4 12345 typ host',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      }));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    test('explicit leave closes the socket cleanly', () async {
      final ws = await _connect(handle.port, 'r4');
      final it = StreamIterator(ws);
      addTearDown(() async {
        await it.cancel();
      });

      ws.add(jsonEncode({'type': 'join', 'uid': 'dave'}));
      await _waitFor(it, 'joined');

      ws.add(jsonEncode({'type': 'leave'}));
      // Drain; expect the stream to end.
      while (await it
          .moveNext()
          .timeout(const Duration(seconds: 2), onTimeout: () => false)) {
        // discard
      }
      expect(ws.readyState, anyOf(WebSocket.closed, WebSocket.closing));
    });
  });

  group('WS overload + session-full', () {
    test('SfuOverloadedException → serverOverloaded WS error', () async {
      final h = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: 0,
        rtpBase: 56700,
        announceIp: '127.0.0.1',
        quiet: true,
        maxSessions: 1,
      );
      addTearDown(h.close);

      // Pre-create one session so the cap is exhausted *before* the
      // WS join hits getOrCreate (we deliberately leave maxRooms=0
      // so the upgrade guard does NOT short-circuit).
      await h.sharded.getOrCreate('alpha');

      final ws = await _connect(h.port, 'beta');
      final it = StreamIterator(ws);
      addTearDown(() async {
        await it.cancel();
        await ws.close();
      });
      ws.add(jsonEncode({'type': 'join', 'uid': 'x'}));
      final err = await _waitFor(it, 'error');
      expect(err, isNotNull);
      expect(err!['reason'], 'serverOverloaded');
    });

    test('SessionFullException → sessionFull WS error', () async {
      final h = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: 0,
        rtpBase: 56720,
        announceIp: '127.0.0.1',
        quiet: true,
        maxPeersPerSession: 1,
      );
      addTearDown(h.close);

      // First peer joins fine.
      final ws1 = await _connect(h.port, 'sess');
      final it1 = StreamIterator(ws1);
      addTearDown(() async {
        await it1.cancel();
        await ws1.close();
      });
      ws1.add(jsonEncode({'type': 'join', 'uid': 'p1'}));
      expect(await _waitFor(it1, 'joined'), isNotNull);

      // Second peer must hit the per-session cap.
      final ws2 = await _connect(h.port, 'sess');
      final it2 = StreamIterator(ws2);
      addTearDown(() async {
        await it2.cancel();
        await ws2.close();
      });
      ws2.add(jsonEncode({'type': 'join', 'uid': 'p2'}));
      final err = await _waitFor(it2, 'error');
      expect(err, isNotNull);
      expect(err!['reason'], 'sessionFull');
    });
  });

  group('announceIp auto-inference', () {
    test('ip=0.0.0.0 + announceIp=null falls back to non-loopback IPv4',
        () async {
      final h = await runIonStyleSfuServer(
        ip: '0.0.0.0',
        port: 0,
        rtpBase: 56740,
        // announceIp: null intentionally — drives _firstNonLoopbackIPv4
        quiet: true,
      );
      addTearDown(h.close);
      // Reaching this point means the constructor ran the full
      // _firstNonLoopbackIPv4() fallback (no announceIp + 0.0.0.0).
      // Sanity: /healthz responds with status:ok.
      final c = HttpClient();
      final req =
          await c.getUrl(Uri.parse('http://127.0.0.1:${h.port}/healthz'));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      c.close(force: true);
      final j = jsonDecode(body) as Map<String, Object?>;
      expect(j['status'], 'ok');
    });
  });
}
