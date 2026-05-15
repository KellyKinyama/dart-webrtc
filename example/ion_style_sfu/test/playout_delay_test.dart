// Phase B13 — round-trip + edge tests for the playout-delay RTP
// header extension codec
// (`http://www.webrtc.org/experiments/rtp-hdrext/playout-delay`).

import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/src/rtp_header.dart';
import 'package:test/test.dart';

void main() {
  group('PlayoutDelay codec', () {
    test('encodes a 3-byte payload', () {
      final out = encodePlayoutDelay(const PlayoutDelay(0, 0));
      expect(out, isA<Uint8List>());
      expect(out.length, 3);
      expect(out, equals(Uint8List.fromList([0, 0, 0])));
    });

    test('round-trips zero', () {
      final encoded = encodePlayoutDelay(const PlayoutDelay(0, 0));
      final decoded = decodePlayoutDelay(encoded);
      expect(decoded, equals(const PlayoutDelay(0, 0)));
    });

    test('round-trips a typical (10ms, 200ms) delay', () {
      const pd = PlayoutDelay(10, 200);
      expect(decodePlayoutDelay(encodePlayoutDelay(pd)), equals(pd));
    });

    test('round-trips the maximum representable value (40_950 ms)', () {
      const pd = PlayoutDelay(
        PlayoutDelay.maxRepresentableMs,
        PlayoutDelay.maxRepresentableMs,
      );
      final dec = decodePlayoutDelay(encodePlayoutDelay(pd));
      expect(dec, equals(pd));
      expect(dec!.maxMs, 40950);
    });

    test('clamps values above the cap to 40_950 ms', () {
      const pd = PlayoutDelay(99999, 99999);
      final dec = decodePlayoutDelay(encodePlayoutDelay(pd));
      expect(dec!.minMs, PlayoutDelay.maxRepresentableMs);
      expect(dec.maxMs, PlayoutDelay.maxRepresentableMs);
    });

    test('clamps negative values to 0', () {
      const pd = PlayoutDelay(-50, -1);
      final dec = decodePlayoutDelay(encodePlayoutDelay(pd));
      expect(dec, equals(const PlayoutDelay(0, 0)));
    });

    test('truncates non-multiple-of-10 ms inputs (integer-divide units)', () {
      // 17ms encodes as 1 unit (= 10ms after decode); 195ms encodes as
      // 19 units (= 190ms). This matches the on-wire 10ms granularity.
      const pd = PlayoutDelay(17, 195);
      final dec = decodePlayoutDelay(encodePlayoutDelay(pd));
      expect(dec, equals(const PlayoutDelay(10, 190)));
    });

    test('preserves min/max independently (asymmetric values)', () {
      const pd = PlayoutDelay(50, 1500);
      expect(decodePlayoutDelay(encodePlayoutDelay(pd)), equals(pd));
    });

    test('decode returns null on null input', () {
      expect(decodePlayoutDelay(null), isNull);
    });

    test('decode returns null on short input', () {
      expect(decodePlayoutDelay(Uint8List(0)), isNull);
      expect(decodePlayoutDelay(Uint8List(1)), isNull);
      expect(decodePlayoutDelay(Uint8List(2)), isNull);
    });

    test('decode tolerates oversized payload (reads first 3 bytes)', () {
      final buf = Uint8List.fromList([0x01, 0x42, 0x40, 0xff, 0xff]);
      // min = (0x01 << 4) | ((0x42 >> 4) & 0xf) = 0x14 = 20 → 200ms
      // max = ((0x42 & 0xf) << 8) | 0x40 = 0x240 = 576 → 5760ms
      final dec = decodePlayoutDelay(buf);
      expect(dec, equals(const PlayoutDelay(200, 5760)));
    });

    test('equality and hashCode work', () {
      const a = PlayoutDelay(10, 200);
      const b = PlayoutDelay(10, 200);
      const c = PlayoutDelay(10, 201);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.toString(), contains('10'));
      expect(a.toString(), contains('200'));
    });
  });
}
