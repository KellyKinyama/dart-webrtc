// WebSocket signaling-edge coverage tests for [_IonPeerSession].
// Drives the full validation matrix without requiring real SDP /
// DTLS: oversized frames, binary frames, rate-limit, invalid JSON,
// invalid uid, duplicate uid, maxPeersPerRoom cap, type-gated
// pre-join messages, oversized SDPs, malformed trickle candidates,
// and the peer-joined / peer-left broadcast path.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/src/sfu_server.dart';
import 'package:test/test.dart';

Future<WebSocket> _connect(int port, String sid) =>
    WebSocket.connect('ws://127.0.0.1:$port/ws/$sid');

/// Tiny FIFO queue over a single-subscriber [Stream]. Buffers events
/// that arrive before [next] is called; `next` waits when empty.
class _Q {
  _Q(Stream<dynamic> s) {
    _sub = s.listen(
      (e) {
        if (_waiters.isNotEmpty) {
          _waiters.removeAt(0).complete(e);
        } else {
          _buf.add(e);
        }
      },
      onDone: () {
        _done = true;
        for (final w in _waiters) {
          w.completeError(StateError('stream closed'));
        }
        _waiters.clear();
      },
      onError: (Object e, StackTrace st) {
        for (final w in _waiters) {
          w.completeError(e, st);
        }
        _waiters.clear();
      },
    );
  }
  final List<Completer<dynamic>> _waiters = [];
  final List<dynamic> _buf = [];
  late final StreamSubscription<dynamic> _sub;
  bool _done = false;

  Future<dynamic> next() {
    if (_buf.isNotEmpty) return Future.value(_buf.removeAt(0));
    if (_done) return Future.error(StateError('stream closed'));
    final c = Completer<dynamic>();
    _waiters.add(c);
    return c.future;
  }

  Future<void> cancel() => _sub.cancel();
}

/// Wait for the next decoded JSON map, or null on timeout / non-string.
Future<Map<String, dynamic>?> _nextJson(
  _Q q, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  try {
    final raw = await q.next().timeout(timeout);
    if (raw is! String) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on TimeoutException {
    return null;
  } on StateError {
    return null;
  }
}

/// Wait for the next JSON map whose `type` matches [type], skipping
/// async noise like `trickle` events that the server emits eagerly
/// during peer setup.
Future<Map<String, dynamic>?> _nextOfType(
  _Q q,
  String type, {
  Duration timeout = const Duration(seconds: 3),
  int maxSkip = 32,
}) async {
  final deadline = DateTime.now().add(timeout);
  for (var i = 0; i < maxSkip; i++) {
    final remain = deadline.difference(DateTime.now());
    if (remain.isNegative) return null;
    final m = await _nextJson(q, timeout: remain);
    if (m == null) return null;
    if (m['type'] == type) return m;
  }
  return null;
}

void main() {
  group('WS signaling — validation matrix', () {
    late IonSfuServerHandle handle;
    late int port;

    setUp(() async {
      handle = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: 0,
        rtpBase: 19800,
        quiet: true,
        maxPeersPerRoom: 2,
      );
      port = handle.port;
    });

    tearDown(() async {
      await handle.close();
    });

    test('join with valid uid → "joined" response', () async {
      final ws = await _connect(port, 'room1');
      addTearDown(() async => ws.close());
      final q = _Q(ws);
      ws.add(jsonEncode({'type': 'join', 'uid': 'alice'}));
      final reply = await _nextOfType(q, 'joined');
      expect(reply, isNotNull);
      expect(reply!['uid'], 'alice');
      expect(reply['sid'], 'room1');
    });

    test('join with no uid auto-generates one', () async {
      final ws = await _connect(port, 'room1');
      addTearDown(() async => ws.close());
      final q = _Q(ws);
      ws.add(jsonEncode({'type': 'join'}));
      final reply = await _nextOfType(q, 'joined');
      expect(reply, isNotNull);
      expect((reply!['uid'] as String).startsWith('peer-'), isTrue);
    });

    test('join with invalid uid → error invalidUid + close', () async {
      final ws = await _connect(port, 'room1');
      final q = _Q(ws);
      ws.add(jsonEncode({'type': 'join', 'uid': 'bad uid!'}));
      final reply = await _nextOfType(q, 'error');
      expect(reply, isNotNull);
      expect(reply!['reason'], 'invalidUid');
    });

    test('duplicate uid in same room → uidInUse error', () async {
      final ws1 = await _connect(port, 'roomDup');
      addTearDown(() async => ws1.close());
      final q1 = _Q(ws1);
      ws1.add(jsonEncode({'type': 'join', 'uid': 'alice'}));
      expect(await _nextOfType(q1, 'joined'), isNotNull);

      final ws2 = await _connect(port, 'roomDup');
      final q2 = _Q(ws2);
      ws2.add(jsonEncode({'type': 'join', 'uid': 'alice'}));
      final reply = await _nextOfType(q2, 'error');
      expect(reply, isNotNull);
      expect(reply!['reason'], 'uidInUse');
    });

    test('maxPeersPerRoom cap → maxPeersReached', () async {
      final ws1 = await _connect(port, 'roomCap');
      addTearDown(() async => ws1.close());
      final q1 = _Q(ws1);
      ws1.add(jsonEncode({'type': 'join', 'uid': 'a'}));
      expect(await _nextOfType(q1, 'joined'), isNotNull);

      final ws2 = await _connect(port, 'roomCap');
      addTearDown(() async => ws2.close());
      final q2 = _Q(ws2);
      ws2.add(jsonEncode({'type': 'join', 'uid': 'b'}));
      expect(await _nextOfType(q2, 'joined'), isNotNull);

      final ws3 = await _connect(port, 'roomCap');
      final q3 = _Q(ws3);
      ws3.add(jsonEncode({'type': 'join', 'uid': 'c'}));
      final reply = await _nextOfType(q3, 'error');
      expect(reply, isNotNull);
      expect(reply!['reason'], 'maxPeersReached');
      expect(reply['limit'], 2);
    });

    test('peer-joined broadcast fires for already-joined peers', () async {
      final ws1 = await _connect(port, 'roomBroadcast');
      addTearDown(() async => ws1.close());
      final q1 = _Q(ws1);
      ws1.add(jsonEncode({'type': 'join', 'uid': 'alice'}));
      expect(await _nextOfType(q1, 'joined'), isNotNull);

      final ws2 = await _connect(port, 'roomBroadcast');
      addTearDown(() async => ws2.close());
      final q2 = _Q(ws2);
      ws2.add(jsonEncode({'type': 'join', 'uid': 'bob'}));
      expect(await _nextOfType(q2, 'joined'), isNotNull);

      // Alice should observe a peer-joined event for Bob (skipping
      // any trickle frames emitted during her own setup).
      final evt = await _nextOfType(q1, 'peer-joined',
          timeout: const Duration(seconds: 4), maxSkip: 64);
      expect(evt, isNotNull, reason: 'expected peer-joined for bob');
      expect(evt!['uid'], 'bob');
    });

    test('binary frame → socket closed with unsupportedData', () async {
      final ws = await _connect(port, 'roomBin');
      final q = _Q(ws);
      addTearDown(q.cancel);
      ws.add(Uint8List.fromList([0, 1, 2, 3]));
      // Wait for close.
      await ws.done.timeout(const Duration(seconds: 2));
      expect(ws.closeCode, WebSocketStatus.unsupportedData);
    });

    test('oversized text frame → socket closed with messageTooBig', () async {
      final ws = await _connect(port, 'roomBig');
      final q = _Q(ws);
      addTearDown(q.cancel);
      // 300 KB of plain text, well over the 256 KB cap.
      final huge = 'x' * (300 * 1024);
      ws.add(huge);
      await ws.done.timeout(const Duration(seconds: 2));
      expect(ws.closeCode, WebSocketStatus.messageTooBig);
    });

    test('rate-limit burst → socket closed with policyViolation', () async {
      final ws = await _connect(port, 'roomRate');
      final q = _Q(ws);
      addTearDown(q.cancel);
      // 70 frames of unknown type — well past the 64-msg window.
      for (var i = 0; i < 80; i++) {
        ws.add(jsonEncode({'type': 'noop', 'i': i}));
      }
      await ws.done.timeout(const Duration(seconds: 3));
      expect(ws.closeCode, WebSocketStatus.policyViolation);
    });

    test('invalid JSON is silently dropped (no close)', () async {
      final ws = await _connect(port, 'roomBadJson');
      addTearDown(() async => ws.close());
      ws.add('this is not json');
      ws.add('{also not valid');
      // Send a real join afterwards — server should still respond.
      ws.add(jsonEncode({'type': 'join', 'uid': 'survivor'}));
      final q = _Q(ws);
      final reply = await _nextOfType(q, 'joined');
      expect(reply, isNotNull);
      expect(reply!['uid'], 'survivor');
    });

    test('non-map JSON payload is silently dropped', () async {
      final ws = await _connect(port, 'roomNonMap');
      addTearDown(() async => ws.close());
      ws.add(jsonEncode([1, 2, 3])); // list, not map
      ws.add(jsonEncode('hello')); // string
      ws.add(jsonEncode(42)); // number
      ws.add(jsonEncode({'type': 'join', 'uid': 'survivor'}));
      final q = _Q(ws);
      expect(await _nextOfType(q, 'joined'), isNotNull);
    });

    test('unknown message type is silently dropped', () async {
      final ws = await _connect(port, 'roomUnknown');
      addTearDown(() async => ws.close());
      final q = _Q(ws);
      ws.add(jsonEncode({'type': 'completelyUnknown'}));
      ws.add(jsonEncode({'type': 'join', 'uid': 'survivor'}));
      expect(await _nextOfType(q, 'joined'), isNotNull);
    });

    test('offer/answer/trickle before join are silently dropped', () async {
      final ws = await _connect(port, 'roomEarly');
      addTearDown(() async => ws.close());
      final q = _Q(ws);
      ws.add(jsonEncode({'type': 'offer', 'target': 'pub', 'sdp': 'v=0'}));
      ws.add(jsonEncode({'type': 'answer', 'target': 'sub', 'sdp': 'v=0'}));
      ws.add(jsonEncode(
          {'type': 'trickle', 'target': 'pub', 'candidate': 'candidate:1'}));
      ws.add(jsonEncode({'type': 'join', 'uid': 'survivor'}));
      expect(await _nextOfType(q, 'joined'), isNotNull);
    });

    test('oversized SDP in offer/answer is silently dropped', () async {
      final ws = await _connect(port, 'roomBigSdp');
      addTearDown(() async => ws.close());
      final q = _Q(ws);
      ws.add(jsonEncode({'type': 'join', 'uid': 'me'}));
      expect(await _nextOfType(q, 'joined'), isNotNull);

      // 80 KB SDP — past _maxSdpBytes (64 KB) but well under
      // _maxSignalingFrameBytes (256 KB).
      final bigSdp = 'v=0\r\n${'x' * (80 * 1024)}';
      ws.add(jsonEncode({'type': 'offer', 'target': 'pub', 'sdp': bigSdp}));
      ws.add(jsonEncode({'type': 'answer', 'target': 'sub', 'sdp': bigSdp}));
      // Socket should still be alive; assert no error frame appears.
      final maybeErr = await _nextOfType(q, 'error',
          timeout: const Duration(milliseconds: 400));
      expect(maybeErr, isNull);
      expect(ws.readyState, WebSocket.open);
    });

    test('malformed trickle candidate is silently dropped', () async {
      final ws = await _connect(port, 'roomBadCand');
      addTearDown(() async => ws.close());
      final q = _Q(ws);
      ws.add(jsonEncode({'type': 'join', 'uid': 'me'}));
      expect(await _nextOfType(q, 'joined'), isNotNull);

      // Wrong target.
      ws.add(jsonEncode({
        'type': 'trickle',
        'target': 'bogus',
        'candidate': 'candidate:1 1 udp 1 1.2.3.4 1 typ host',
      }));
      // Wrong prefix.
      ws.add(jsonEncode({
        'type': 'trickle',
        'target': 'pub',
        'candidate': 'totally not an ice candidate',
      }));
      // Oversized candidate (>1024 bytes).
      ws.add(jsonEncode({
        'type': 'trickle',
        'target': 'pub',
        'candidate': 'x' * 2000,
      }));
      // Confirm socket is still healthy: no error frame surfaces.
      final maybeErr = await _nextOfType(q, 'error',
          timeout: const Duration(milliseconds: 400));
      expect(maybeErr, isNull);
      expect(ws.readyState, WebSocket.open);
    });

    test('explicit leave message closes the socket', () async {
      final ws = await _connect(port, 'roomLeave');
      final q = _Q(ws);
      ws.add(jsonEncode({'type': 'join', 'uid': 'leaver'}));
      expect(await _nextOfType(q, 'joined'), isNotNull);
      ws.add(jsonEncode({'type': 'leave'}));
      await ws.done.timeout(const Duration(seconds: 2));
    });
  });
}
