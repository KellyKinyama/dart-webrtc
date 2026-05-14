// Phase 5 — BandwidthEstimator and LayerSelector unit tests.

import 'package:pure_dart_webrtc_ion_style_sfu/src/bwe.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/src/rtcp.dart';
import 'package:test/test.dart';

void main() {
  group('BandwidthEstimator', () {
    test('first REMB seeds the estimate exactly', () {
      final bwe = BandwidthEstimator();
      bwe.onRemb(const RembFeedback(
        senderSsrc: 0,
        mediaSsrc: 0,
        bps: 1_000_000,
        ssrcs: [],
      ));
      expect(bwe.currentBps, 1_000_000);
      expect(bwe.lastUpdate, isNotNull);
    });

    test('subsequent REMB updates via EMA', () {
      final bwe = BandwidthEstimator(smoothing: 0.5);
      bwe.onRemb(const RembFeedback(
        senderSsrc: 0, mediaSsrc: 0, bps: 1_000_000, ssrcs: [],
      ));
      bwe.onRemb(const RembFeedback(
        senderSsrc: 0, mediaSsrc: 0, bps: 2_000_000, ssrcs: [],
      ));
      // EMA: 1_000_000 + 0.5 * (2_000_000 - 1_000_000) = 1_500_000.
      expect(bwe.currentBps, 1_500_000);
    });

    test('setBps overrides directly', () {
      final bwe = BandwidthEstimator();
      bwe.setBps(750_000);
      expect(bwe.currentBps, 750_000);
    });
  });

  group('LayerSelector', () {
    test('picks the highest rid whose threshold the estimate meets',
        () {
      final bwe = BandwidthEstimator()..setBps(800_000);
      final sel = LayerSelector(estimator: bwe);
      final changes = <(String, String)>[];
      sel.onLayerChange = (id, rid) => changes.add((id, rid));
      sel.register('vid1', ['q', 'h', 'f'], initialRid: 'q');
      sel.tick();
      // 800 kbps is above hMin (500k) but below fMin (1500k) → 'h'.
      expect(sel.currentLayer('vid1'), 'h');
      expect(changes, [('vid1', 'h')]);
    });

    test('budget is split across active video downtracks', () {
      final bwe = BandwidthEstimator()..setBps(1_200_000);
      final sel = LayerSelector(estimator: bwe);
      sel.activeVideoDownTracks = 3; // 400 kbps per track
      sel.register('a', ['q', 'h', 'f'], initialRid: 'q');
      sel.tick();
      // 400k is between qMin (150k) and hMin (500k) → 'q'.
      expect(sel.currentLayer('a'), 'q');
    });

    test('upgrade then downgrade fires onLayerChange each time', () {
      final bwe = BandwidthEstimator()..setBps(600_000);
      final sel = LayerSelector(estimator: bwe);
      final changes = <String>[];
      sel.onLayerChange = (_, rid) => changes.add(rid);
      sel.register('x', ['q', 'h', 'f'], initialRid: 'q');
      sel.tick();
      expect(changes.last, 'h');
      bwe.setBps(2_000_000);
      sel.tick();
      expect(changes.last, 'f');
      bwe.setBps(200_000);
      sel.tick();
      expect(changes.last, 'q');
      expect(changes, ['h', 'f', 'q']);
    });

    test('single-layer receivers are ignored by the selector', () {
      final bwe = BandwidthEstimator()..setBps(2_000_000);
      final sel = LayerSelector(estimator: bwe);
      var changes = 0;
      sel.onLayerChange = (_, __) => changes++;
      sel.register('audio', [''], initialRid: '');
      sel.tick();
      expect(changes, 0);
    });

    test('unregister stops tracking the receiver', () {
      final bwe = BandwidthEstimator()..setBps(2_000_000);
      final sel = LayerSelector(estimator: bwe);
      var changes = 0;
      sel.onLayerChange = (_, __) => changes++;
      sel.register('x', ['q', 'h', 'f'], initialRid: 'q');
      sel.tick();
      expect(changes, 1);
      sel.unregister('x');
      bwe.setBps(100_000); // would downgrade
      sel.tick();
      expect(changes, 1); // no further events
      expect(sel.currentLayer('x'), isNull);
    });
  });

  group('LayerBitrateThresholds', () {
    test('default thresholds: q ≤ 150k → q', () {
      const t = LayerBitrateThresholds();
      expect(t.pickRid(0, ['q', 'h', 'f']), 'q');
      expect(t.pickRid(149_000, ['q', 'h', 'f']), 'q');
    });

    test('150k..500k → q (h not yet)', () {
      const t = LayerBitrateThresholds();
      expect(t.pickRid(300_000, ['q', 'h', 'f']), 'q');
    });

    test('500k..1500k → h', () {
      const t = LayerBitrateThresholds();
      expect(t.pickRid(500_000, ['q', 'h', 'f']), 'h');
      expect(t.pickRid(1_499_000, ['q', 'h', 'f']), 'h');
    });

    test('1500k+ → f', () {
      const t = LayerBitrateThresholds();
      expect(t.pickRid(1_500_000, ['q', 'h', 'f']), 'f');
      expect(t.pickRid(5_000_000, ['q', 'h', 'f']), 'f');
    });
  });
}
