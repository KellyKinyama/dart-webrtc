// Verifies that STUN URLs configured via [ShardConfigTemplate.iceServerUrls]
// are propagated end-to-end:
//
//   ShardedSfu(template) -> getOrCreate -> ShardConfig (per session)
//   -> SessionShard worker -> Sfu.config.iceServerUrls
//   -> Publisher/Subscriber RTCPeerConnection.RTCConfiguration.iceServers
//
// The propagation through ShardedSfu is observed via the public
// `configure` callback. The downstream effect (gathered srflx candidates
// trickled to clients) is covered by the lower-level
// `test/ice_gathering_test.dart` in the parent package.

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

void main() {
  group('SFU ICE server propagation', () {
    test('ShardConfigTemplate.iceServerUrls flow into per-session ShardConfig',
        () async {
      const urls = [
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
      ];
      final sharded = ShardedSfu(const ShardConfigTemplate(
        bindAddress: '127.0.0.1',
        rtpBasePort: 0,
        announceAddress: '127.0.0.1',
        portsPerShard: 4,
        quiet: true,
        iceServerUrls: urls,
      ));
      addTearDown(sharded.close);

      ShardConfig? observed;
      sharded.configure = (base) {
        observed = base;
        // Don't actually spawn the worker; throwing here aborts the
        // getOrCreate future, which is exactly what we want for a pure
        // propagation test (avoids opening UDP sockets).
        throw _StopHere();
      };

      await expectLater(
        () => sharded.getOrCreate('room-ice'),
        throwsA(isA<_StopHere>()),
      );

      expect(observed, isNotNull);
      expect(observed!.iceServerUrls, urls);
      expect(observed!.sessionId, 'room-ice');
    });

    test('default iceServerUrls is empty (no srflx gathering)', () {
      const tmpl = ShardConfigTemplate(
        bindAddress: '127.0.0.1',
        rtpBasePort: 0,
      );
      expect(tmpl.iceServerUrls, isEmpty);
    });

    test('ShardConfig accepts and stores iceServerUrls', () {
      const cfg = ShardConfig(
        sessionId: 's',
        bindAddress: '127.0.0.1',
        rtpBasePort: 0,
        iceServerUrls: ['stun:example.com:3478'],
      );
      expect(cfg.iceServerUrls, ['stun:example.com:3478']);
    });
  });
}

/// Sentinel error used to short-circuit shard spawn in the propagation
/// test without opening UDP sockets.
class _StopHere implements Exception {}
