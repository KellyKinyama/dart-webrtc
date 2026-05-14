// Phase 2 — per-subscriber jitter buffer.
//
// Stores the last [capacity] forwarded RTP packets in a ring keyed by
// 16-bit sequence number. Subscribers ask for replays via NACK; the
// SFU answers from this buffer rather than forwarding the loss
// upstream when possible.

import 'dart:typed_data';

class JitterBuffer {
  /// Max packets retained.
  final int capacity;

  // Ring of (seq, packet) entries. seq < 0 means "empty slot".
  final List<int> _seq;
  final List<Uint8List?> _pkt;
  int _writeIdx = 0;

  JitterBuffer({this.capacity = 512})
      : _seq = List<int>.filled(capacity, -1, growable: false),
        _pkt = List<Uint8List?>.filled(capacity, null, growable: false);

  /// Record [packet] under [seq]. Overwrites the oldest entry.
  void record(int seq, Uint8List packet) {
    _seq[_writeIdx] = seq & 0xFFFF;
    _pkt[_writeIdx] = packet;
    _writeIdx = (_writeIdx + 1) % capacity;
  }

  /// Lookup by 16-bit seq. Returns null if not retained.
  Uint8List? get(int seq) {
    final s = seq & 0xFFFF;
    for (var i = 0; i < capacity; i++) {
      if (_seq[i] == s) return _pkt[i];
    }
    return null;
  }
}
