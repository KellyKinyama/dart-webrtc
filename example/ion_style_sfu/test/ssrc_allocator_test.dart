import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

void main() {
  group('SsrcAllocator', () {
    test('rewrite is idempotent per (subscriber, ssrc)', () {
      final a = SsrcAllocator();
      final s1 = a.rewrite('subA', 1111);
      final s2 = a.rewrite('subA', 1111);
      expect(s2, equals(s1));
    });

    test('different originals get distinct rewrites', () {
      final a = SsrcAllocator();
      final s1 = a.rewrite('subA', 1111);
      final s2 = a.rewrite('subA', 2222);
      expect(s1, isNot(equals(s2)));
    });

    test('different subscribers get independent maps', () {
      final a = SsrcAllocator();
      final sA = a.rewrite('subA', 1111);
      final sB = a.rewrite('subB', 1111);
      // Reverse must respect subscriber scope.
      expect(a.originalFor('subA', sA), 1111);
      expect(a.originalFor('subB', sB), 1111);
      expect(a.originalFor('subA', sB), isNull);
    });

    test('rewriteRtx forces primary alloc and pairs', () {
      final a = SsrcAllocator();
      final rtx = a.rewriteRtx('subA', 1111, 9999);
      expect(a.originalFor('subA', rtx), 9999);
      // Primary must now be reachable by the same subscriber id.
      final primary = a.rewrite('subA', 1111);
      expect(a.originalFor('subA', primary), 1111);
      expect(primary, isNot(equals(rtx)));
    });

    test('forget clears all mappings for a subscriber', () {
      final a = SsrcAllocator();
      final s = a.rewrite('subA', 1111);
      a.forget('subA');
      expect(a.originalFor('subA', s), isNull);
      // A new alloc starts from scratch.
      final s2 = a.rewrite('subA', 1111);
      expect(a.originalFor('subA', s2), 1111);
    });

    test('never allocates SSRC zero', () {
      final a = SsrcAllocator();
      for (var i = 0; i < 200; i++) {
        final s = a.rewrite('subA', 1000 + i);
        expect(s, isNot(0));
      }
    });
  });
}
