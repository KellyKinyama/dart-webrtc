import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/src/byte_pool.dart';
import 'package:test/test.dart';

void main() {
  group('BytePool', () {
    test('acquired view has requested length and pool tracks misses', () {
      final p = BytePool();
      final hits0 = p.hits;
      final misses0 = p.misses;
      final b = p.acquire(100);
      expect(b.length, 100);
      expect(p.hits, hits0); // first request always a miss
      expect(p.misses, misses0 + 1);
    });

    test('release then acquire returns a buffer of the same size class', () {
      final p = BytePool();
      final a = p.acquire(200);
      final cap0 = a.buffer.lengthInBytes;
      p.release(a);
      final hits0 = p.hits;
      final b = p.acquire(200);
      expect(b.length, 200);
      expect(b.buffer.lengthInBytes, cap0,
          reason: 'reused buffer should have the same backing capacity');
      expect(p.hits, hits0 + 1, reason: 'second acquire should be a pool hit');
    });

    test(
        'size-class promotion: requesting smaller-than-bucket size '
        'still gets a fresh-class buffer', () {
      final p = BytePool();
      // 100 bytes → 128-byte class.
      final a = p.acquire(100);
      expect(a.buffer.lengthInBytes, 128);
      // 130 bytes → 256-byte class.
      final b = p.acquire(130);
      expect(b.buffer.lengthInBytes, 256);
    });

    test('oversized requests bypass the pool and are not retained', () {
      final p = BytePool();
      final huge = p.acquire(1 << 20);
      expect(huge.length, 1 << 20);
      expect(p.parkedCount, 0);
      // Releasing should be a no-op (oversized capacity).
      p.release(huge);
      expect(p.parkedCount, 0);
    });

    test('perBucketCap caps retention; surplus releases drop', () {
      final p = BytePool(perBucketCap: 2);
      final bs = [for (var i = 0; i < 5; i++) p.acquire(64)];
      for (final b in bs) {
        p.release(b);
      }
      expect(p.parkedCount, 2);
      expect(p.oversizedDrops, 3);
    });

    test('acquireFrom copies the source bytes', () {
      final p = BytePool();
      final src = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final dst = p.acquireFrom(src);
      expect(dst, equals(src));
      // Mutating the source must not affect the pooled copy.
      src[0] = 0xff;
      expect(dst[0], 1);
    });

    test('clear empties every bucket', () {
      final p = BytePool();
      p.release(p.acquire(64));
      p.release(p.acquire(128));
      expect(p.parkedCount, 2);
      p.clear();
      expect(p.parkedCount, 0);
    });
  });
}
