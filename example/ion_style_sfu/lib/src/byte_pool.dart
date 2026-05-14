// Per-isolate Uint8List pool for the RTP forwarding hot path.
//
// One inbound RTP packet on a hot room can spawn N rewritten copies
// (one per attached DownTrack). Without pooling, each copy is a fresh
// `Uint8List` that becomes garbage milliseconds later. The Dart GC
// cost of that allocation churn is the dominant in-isolate scaling
// bottleneck identified during Phase 10 load testing.
//
// [BytePool] is a tiny size-class allocator. Buffers are bucketed into
// power-of-two size classes (capacity, not length). `acquire(n)`
// returns a `Uint8List` whose `.length == n`, backed by a `ByteBuffer`
// whose capacity is the next power of two ≥ n. `release(buf)` returns
// the underlying buffer to its bucket.
//
// The pool is deliberately *not* thread-safe — every isolate keeps its
// own [BytePool.instance]. The single producer/consumer model on the
// SFU's hot path means no locking is needed.

import 'dart:typed_data';

/// Default maximum buffers retained per size class. Beyond this,
/// [release] simply drops the buffer for the GC to reclaim — keeps the
/// pool bounded in low-traffic / burst-then-quiet workloads.
const int _defaultPerBucketCap = 64;

/// Smallest size class (bytes). Below this, allocations are small
/// enough that pooling saves nothing.
const int _minSizeClassPow2 = 6; // 64 B

/// Largest size class (bytes). Above this we fall back to plain
/// allocation — typical RTP payloads are well below 2 KB; relay or
/// FEC bursts can cross 4 KB but caching MTU-sized buffers is cheap.
const int _maxSizeClassPow2 = 13; // 8 KB

class BytePool {
  /// Per-isolate singleton. Tests may construct private pools.
  static final BytePool instance = BytePool();

  /// Per size-class bucket cap (defaults to 64). Tunable for tests.
  final int perBucketCap;

  /// `_buckets[i]` is the free list for capacity `1 << (i + _minSizeClassPow2)`.
  final List<List<ByteBuffer>> _buckets;

  // Diagnostics. Not synchronised — read from the same isolate that
  // mutates them.
  int hits = 0;
  int misses = 0;
  int releases = 0;
  int oversizedDrops = 0;

  BytePool({this.perBucketCap = _defaultPerBucketCap})
      : _buckets = List.generate(
          _maxSizeClassPow2 - _minSizeClassPow2 + 1,
          (_) => <ByteBuffer>[],
          growable: false,
        );

  /// Acquire a `Uint8List` whose `.length == size`. The returned view
  /// may be backed by a larger buffer; callers should [release] it
  /// when done so the underlying capacity goes back into the pool.
  ///
  /// For sizes outside the size-class range the call falls back to a
  /// plain allocation; [release] on those buffers is a no-op (they
  /// were never pooled).
  Uint8List acquire(int size) {
    if (size <= 0) return Uint8List(0);
    final cls = _classFor(size);
    if (cls < 0) {
      misses++;
      return Uint8List(size);
    }
    final bucket = _buckets[cls];
    if (bucket.isEmpty) {
      misses++;
      return Uint8List(1 << (cls + _minSizeClassPow2))
          .buffer
          .asUint8List(0, size);
    }
    hits++;
    final buf = bucket.removeLast();
    return buf.asUint8List(0, size);
  }

  /// Acquire a buffer and copy [src] into it. Equivalent to
  /// `acquire(src.length)..setRange(0, src.length, src)`.
  Uint8List acquireFrom(Uint8List src) {
    final out = acquire(src.length);
    out.setRange(0, src.length, src);
    return out;
  }

  /// Return [view] to the pool. Safe on buffers acquired outside the
  /// pool (those simply get dropped).
  void release(Uint8List view) {
    final cap = view.buffer.lengthInBytes;
    final cls = _classForCapacity(cap);
    if (cls < 0) {
      oversizedDrops++;
      return;
    }
    final bucket = _buckets[cls];
    if (bucket.length >= perBucketCap) {
      oversizedDrops++;
      return;
    }
    releases++;
    bucket.add(view.buffer);
  }

  /// Empty every bucket.
  void clear() {
    for (final b in _buckets) {
      b.clear();
    }
  }

  /// Number of buffers currently parked in the pool (across all
  /// size classes).
  int get parkedCount {
    var n = 0;
    for (final b in _buckets) {
      n += b.length;
    }
    return n;
  }

  /// Size-class index for a request of [size] bytes. Returns -1 when
  /// outside the supported range.
  int _classFor(int size) {
    if (size < (1 << _minSizeClassPow2)) {
      return 0;
    }
    final maxCap = 1 << _maxSizeClassPow2;
    if (size > maxCap) return -1;
    var pow = _minSizeClassPow2;
    var cap = 1 << pow;
    while (cap < size) {
      pow++;
      cap <<= 1;
    }
    return pow - _minSizeClassPow2;
  }

  /// Size-class index for an *exact* power-of-two capacity. -1 when
  /// the capacity isn't one of our buckets.
  int _classForCapacity(int cap) {
    if (cap < (1 << _minSizeClassPow2)) return -1;
    if (cap > (1 << _maxSizeClassPow2)) return -1;
    // Detect non-power-of-two — those are external Uint8Lists we can't
    // safely return to a power-of-two bucket.
    if ((cap & (cap - 1)) != 0) return -1;
    var pow = _minSizeClassPow2;
    var c = 1 << pow;
    while (c < cap) {
      pow++;
      c <<= 1;
    }
    return pow - _minSizeClassPow2;
  }
}
