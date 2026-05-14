// Phase 8 (part 2) — sharded session registry.
//
// `ShardedSfu` is a thin orchestrator that hands out one [SessionShard]
// per session id, spawning a worker isolate on first request and
// reusing it thereafter. It runs alongside the main-isolate [Sfu]; the
// two will converge as more functionality migrates into the shards in
// later phases.

import 'dart:async';

import 'session_shard.dart';

/// Per-session-isolate registry. Spawns shards lazily and keeps them
/// warm until [closeShard] or [close] is called.
class ShardedSfu {
  final Map<String, SessionShard> _shards = {};
  final Map<String, Future<SessionShard>> _spawning = {};
  bool _closed = false;

  /// Live shards (snapshot).
  Iterable<SessionShard> get shards => _shards.values;

  /// Number of live shards.
  int get shardCount => _shards.length;

  /// Get-or-create a shard for [sessionId]. Concurrent calls for the
  /// same id share a single spawn future so we never create duplicate
  /// isolates.
  Future<SessionShard> getOrCreate(String sessionId) {
    if (_closed) {
      throw StateError('ShardedSfu is closed');
    }
    final existing = _shards[sessionId];
    if (existing != null) return Future.value(existing);
    final pending = _spawning[sessionId];
    if (pending != null) return pending;
    final f = SessionShard.spawn(sessionId).then((shard) {
      _shards[sessionId] = shard;
      _spawning.remove(sessionId);
      return shard;
    }, onError: (e, st) {
      _spawning.remove(sessionId);
      throw e;
    });
    _spawning[sessionId] = f;
    return f;
  }

  /// Look up an existing shard without spawning one.
  SessionShard? get(String sessionId) => _shards[sessionId];

  /// Close and forget the shard for [sessionId]. No-op when absent.
  Future<void> closeShard(String sessionId) async {
    final s = _shards.remove(sessionId);
    if (s != null) await s.close();
  }

  /// Close every shard.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final all = _shards.values.toList();
    _shards.clear();
    await Future.wait(all.map((s) => s.close()));
  }
}
