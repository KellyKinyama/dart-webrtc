// Coverage / sanity tests for the Phase-1 sketch types that the rest
// of the SFU codebase depends on as stable shapes:
//
//   * `SimulcastConfig` / `SimulcastTrackHelpers` / `SimulcastLayer`
//   * `ProducerLayer`
//   * `TwccResponder`
//   * `RembEstimator`
//
// These are deliberately stubs (Phase 5+ wires them up), but their
// presence is load-bearing — a downstream change that breaks one of
// the constructors / default values would silently regress the wiring
// sites. Lock in the shape so a coverage signal of 0% on them is no
// longer ambiguous.

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

void main() {
  group('SimulcastLayer / SimulcastConfig / SimulcastTrackHelpers', () {
    test('layer enum is q/h/f in order', () {
      expect(SimulcastLayer.values,
          [SimulcastLayer.quarter, SimulcastLayer.half, SimulcastLayer.full]);
    });

    test('config defaults: bestQualityFirst=false, enableTemporalLayer=false',
        () {
      const c = SimulcastConfig();
      expect(c.bestQualityFirst, isFalse);
      expect(c.enableTemporalLayer, isFalse);
    });

    test('config respects overrides', () {
      const c = SimulcastConfig(
        bestQualityFirst: true,
        enableTemporalLayer: true,
      );
      expect(c.bestQualityFirst, isTrue);
      expect(c.enableTemporalLayer, isTrue);
    });

    test('helpers default to full layer with no scheduled switch', () {
      final h = SimulcastTrackHelpers();
      expect(h.current, SimulcastLayer.full);
      expect(h.target, SimulcastLayer.full);
      expect(h.switchAt, isNull);

      // Mutability sanity (the helper is just a struct).
      h.target = SimulcastLayer.quarter;
      h.switchAt = DateTime.utc(2020, 1, 1);
      expect(h.target, SimulcastLayer.quarter);
      expect(h.switchAt, DateTime.utc(2020, 1, 1));
    });
  });

  group('ProducerLayer', () {
    test('records rid, primary SSRC, and optional RTX SSRC', () {
      const a = ProducerLayer(rid: 'q', primarySsrc: 1, rtxSsrc: 2);
      expect(a.rid, 'q');
      expect(a.primarySsrc, 1);
      expect(a.rtxSsrc, 2);

      const b = ProducerLayer(rid: '', primarySsrc: 42, rtxSsrc: null);
      expect(b.rid, '');
      expect(b.rtxSsrc, isNull);
    });

    test('toString includes RTX only when present', () {
      const withRtx = ProducerLayer(rid: 'h', primarySsrc: 11, rtxSsrc: 22);
      const noRtx = ProducerLayer(rid: 'f', primarySsrc: 33, rtxSsrc: null);
      expect(withRtx.toString(), contains('rtx=22'));
      expect(noRtx.toString(), isNot(contains('rtx=')));
    });
  });

  group('TwccResponder (Phase-1 stub)', () {
    test('observePacket and buildFeedback are callable no-ops', () {
      final r = TwccResponder();
      expect(() => r.observePacket(0, DateTime.utc(2024)), returnsNormally);
      expect(() => r.observePacket(65535, DateTime.now()), returnsNormally);
      expect(r.buildFeedback, returnsNormally);
    });
  });

  group('RembEstimator (Phase-1 stub)', () {
    test('default estimate is 0bps', () {
      final r = RembEstimator();
      expect(r.currentBps, 0);
    });

    test('onArrival and buildRemb are callable no-ops', () {
      final r = RembEstimator();
      expect(() => r.onArrival(1200, DateTime.utc(2024)), returnsNormally);
      expect(r.buildRemb, returnsNormally);
      // Stub doesn't update the estimate.
      expect(r.currentBps, 0);
    });

    test('currentBps is mutable so wiring sites can plug in real values', () {
      final r = RembEstimator()..currentBps = 1_500_000;
      expect(r.currentBps, 1500000);
    });
  });
}
