// Tests for the upstream-PLI 500 ms throttle on DownTrack
// (mirrors ion-sfu pkg/sfu/receiver.go#L266). The throttle is the
// rate-limit gate that prevents a misbehaving subscriber from
// inducing a keyframe storm at the publisher (and across every
// downstream cascade hop).

import 'package:pure_dart_webrtc_ion_style_sfu/src/down_track.dart';
import 'package:test/test.dart';

void main() {
  group('upstream PLI throttle (pliThrottleAllowForTest)', () {
    final t0 = DateTime.utc(2026, 1, 1, 0, 0, 0);
    const gap = DownTrack.minUpstreamPliGap;

    test('first call is always allowed (no prior send)', () {
      expect(pliThrottleAllowForTest(null, t0, gap), isTrue);
    });

    test('second call within the gap is denied', () {
      final t1 = t0.add(const Duration(milliseconds: 100));
      expect(pliThrottleAllowForTest(t0, t1, gap), isFalse);
    });

    test('second call exactly at the gap boundary is allowed', () {
      final t1 = t0.add(gap);
      expect(pliThrottleAllowForTest(t0, t1, gap), isTrue);
    });

    test('second call past the gap is allowed', () {
      final t1 = t0.add(gap + const Duration(milliseconds: 1));
      expect(pliThrottleAllowForTest(t0, t1, gap), isTrue);
    });

    test('the configured gap matches ion-sfu (500 ms)', () {
      // Hard-pin the value: regressing this silently would change the
      // upstream PLI cadence and could induce keyframe storms.
      expect(DownTrack.minUpstreamPliGap, const Duration(milliseconds: 500));
    });

    test('a 100-call burst at 50 ms intervals lets through ~1 call per gap',
        () {
      // Simulate a misbehaving subscriber spamming PLI every 50 ms for
      // 5 seconds. With a 500 ms minimum gap, at most 11 of those 100
      // calls should be accepted (one at t=0, then one every 500 ms
      // from t=500 .. t=5000).
      DateTime? last;
      var allowed = 0;
      for (var i = 0; i < 100; i++) {
        final now = t0.add(Duration(milliseconds: 50 * i));
        if (pliThrottleAllowForTest(last, now, gap)) {
          allowed++;
          last = now;
        }
      }
      expect(allowed, inInclusiveRange(10, 11));
    });
  });
}
