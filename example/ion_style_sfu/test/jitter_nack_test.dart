import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

void main() {
  group('JitterBuffer', () {
    test('record + get round-trip', () {
      final jb = JitterBuffer(capacity: 8);
      final p = Uint8List.fromList([1, 2, 3]);
      jb.record(42, p);
      expect(jb.get(42), same(p));
    });

    test('returns null for unknown seq', () {
      final jb = JitterBuffer(capacity: 8);
      expect(jb.get(99), isNull);
    });

    test('overwrites oldest when ring fills', () {
      final jb = JitterBuffer(capacity: 4);
      for (var i = 0; i < 4; i++) {
        jb.record(i, Uint8List.fromList([i]));
      }
      // Now overwrite slot 0.
      jb.record(99, Uint8List.fromList([99]));
      expect(jb.get(0), isNull);
      expect(jb.get(99), isNotNull);
      expect(jb.get(1), isNotNull);
    });

    test('treats seq as 16-bit', () {
      final jb = JitterBuffer(capacity: 4);
      final p = Uint8List.fromList([7]);
      jb.record(0x10042, p); // == 0x42 truncated
      expect(jb.get(0x42), same(p));
    });
  });

  group('NackResponder', () {
    test('cache hit replays without escalating', () {
      final jb = JitterBuffer(capacity: 16);
      jb.record(10, Uint8List.fromList([1]));
      jb.record(11, Uint8List.fromList([2]));
      final nr = NackResponder(buffer: jb);
      final r = nr.lookup([10, 11]);
      expect(r.hits, hasLength(2));
      expect(r.stillMissing, isEmpty);
      expect(nr.retransmits, 2);
      expect(nr.upstreamRequested, 0);
    });

    test('cache miss escalates upstream', () {
      final jb = JitterBuffer(capacity: 16);
      jb.record(10, Uint8List.fromList([1]));
      final nr = NackResponder(buffer: jb);
      final r = nr.lookup([10, 11, 12]);
      expect(r.hits, hasLength(1));
      expect(r.stillMissing, [11, 12]);
      expect(nr.retransmits, 1);
      expect(nr.upstreamRequested, 2);
    });
  });
}
