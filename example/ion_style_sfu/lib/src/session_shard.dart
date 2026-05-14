// Phase 8 (part 2) — per-session isolate scaffolding.
//
// `SessionShard` owns a worker isolate dedicated to a single session.
// The main isolate talks to it via a request/reply RPC over SendPorts,
// keyed by a monotonically increasing correlation id so multiple
// in-flight calls don't get mixed up.
//
// This is the *lightweight scaffolding* tier of Phase 8.2: the shard
// keeps a tiny in-isolate session model (peer ids + a few counters) so
// we can prove the isolate boundary works end-to-end (spawn, RPC,
// stats, close) without yet moving Peer/PeerConnection/Router into
// the isolate. Future phases can grow the worker's responsibilities.

import 'dart:async';
import 'dart:isolate';

/// Snapshot of a shard's session state, returned by [SessionShard.stats].
class ShardStats {
  final String sessionId;
  final int peerCount;
  final List<String> peerIds;
  final int rtpForwarded;
  final int rtcpForwarded;

  const ShardStats({
    required this.sessionId,
    required this.peerCount,
    required this.peerIds,
    required this.rtpForwarded,
    required this.rtcpForwarded,
  });

  Map<String, Object?> toJson() => {
        'sessionId': sessionId,
        'peerCount': peerCount,
        'peerIds': peerIds,
        'rtpForwarded': rtpForwarded,
        'rtcpForwarded': rtcpForwarded,
      };

  factory ShardStats._fromMap(Map<dynamic, dynamic> m) => ShardStats(
        sessionId: m['sessionId'] as String,
        peerCount: m['peerCount'] as int,
        peerIds: (m['peerIds'] as List).cast<String>(),
        rtpForwarded: m['rtpForwarded'] as int,
        rtcpForwarded: m['rtcpForwarded'] as int,
      );
}

/// Main-isolate handle to a per-session worker isolate.
///
/// Each call sends a tagged request to the worker and completes a
/// `Completer` when the matching reply arrives. The worker is
/// single-threaded so requests are processed in arrival order.
class SessionShard {
  final String sessionId;
  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextReqId = 1;
  bool _closed = false;

  SessionShard._(
      this.sessionId, this._isolate, this._toWorker, this._fromWorker) {
    _fromWorker.listen(_onReply);
  }

  /// Spawn a fresh worker isolate dedicated to [sessionId].
  static Future<SessionShard> spawn(String sessionId) async {
    final handshake = ReceivePort();
    final replies = ReceivePort();
    final iso = await Isolate.spawn<_BootMsg>(
      _workerMain,
      _BootMsg(sessionId, handshake.sendPort, replies.sendPort),
      debugName: 'session-shard:$sessionId',
    );
    final toWorker = await handshake.first as SendPort;
    handshake.close();
    return SessionShard._(sessionId, iso, toWorker, replies);
  }

  void _onReply(dynamic msg) {
    if (msg is! Map) return;
    final id = msg['id'];
    if (id is! int) return;
    final c = _pending.remove(id);
    if (c == null) return;
    final err = msg['error'];
    if (err != null) {
      c.completeError(StateError(err.toString()));
    } else {
      c.complete(msg['result']);
    }
  }

  Future<Object?> _call(String op, [Object? payload]) {
    if (_closed) {
      throw StateError('SessionShard($sessionId) is closed');
    }
    final id = _nextReqId++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _toWorker.send({'id': id, 'op': op, 'payload': payload});
    return c.future;
  }

  /// Register a peer with the shard. Idempotent.
  Future<void> addPeer(String peerId) async {
    await _call('addPeer', peerId);
  }

  /// Drop a peer from the shard. Idempotent.
  Future<void> removePeer(String peerId) async {
    await _call('removePeer', peerId);
  }

  /// Bump the shard's RTP-forwarded counter by [n] (used for stats).
  Future<void> recordRtpForwarded(int n) async {
    await _call('rtp', n);
  }

  /// Bump the shard's RTCP-forwarded counter by [n].
  Future<void> recordRtcpForwarded(int n) async {
    await _call('rtcp', n);
  }

  /// Snapshot the shard's session state.
  Future<ShardStats> stats() async {
    final r = await _call('stats') as Map;
    return ShardStats._fromMap(r);
  }

  /// Tear the shard's worker isolate down. Idempotent.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _call('close');
    } catch (_) {
      // Worker may already be gone.
    }
    _fromWorker.close();
    _isolate.kill(priority: Isolate.immediate);
    // Fail any straggling pendings.
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('SessionShard($sessionId) closed'));
      }
    }
    _pending.clear();
  }
}

class _BootMsg {
  final String sessionId;
  final SendPort handshake;
  final SendPort replies;
  const _BootMsg(this.sessionId, this.handshake, this.replies);
}

/// Worker entry point. Keep this top-level so `Isolate.spawn` can
/// reach it. Holds a tiny in-isolate session model.
void _workerMain(_BootMsg boot) {
  final inbox = ReceivePort();
  // Hand our SendPort back so the main proxy can call us.
  boot.handshake.send(inbox.sendPort);

  final peerIds = <String>{};
  var rtpForwarded = 0;
  var rtcpForwarded = 0;

  inbox.listen((msg) {
    if (msg is! Map) return;
    final id = msg['id'] as int?;
    final op = msg['op'] as String?;
    final payload = msg['payload'];
    if (id == null || op == null) return;

    Object? result;
    String? error;
    try {
      switch (op) {
        case 'addPeer':
          peerIds.add(payload as String);
          result = null;
        case 'removePeer':
          peerIds.remove(payload as String);
          result = null;
        case 'rtp':
          rtpForwarded += (payload as int);
          result = null;
        case 'rtcp':
          rtcpForwarded += (payload as int);
          result = null;
        case 'stats':
          result = {
            'sessionId': boot.sessionId,
            'peerCount': peerIds.length,
            'peerIds': peerIds.toList(),
            'rtpForwarded': rtpForwarded,
            'rtcpForwarded': rtcpForwarded,
          };
        case 'close':
          result = null;
          boot.replies.send({'id': id, 'result': result});
          inbox.close();
          return;
        default:
          error = 'unknown op: $op';
      }
    } catch (e) {
      error = e.toString();
    }
    boot.replies.send({'id': id, 'result': result, 'error': error});
  });
}
