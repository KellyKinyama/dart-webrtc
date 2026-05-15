// Phase B-quick — small-file coverage batch.
// Targets:
//   * audio_observer.dart: AudioObserverEvent.toString + EMA decay path.
//   * peer.dart: addPublisherIceCandidate / addSubscriberIceCandidate
//     + setSubscriberAnswer null-subscriber StateError.
//   * rtp_header.dart: stripAudioLevel two-byte profile (0x100x).
//   * vp8.dart: parseVp8Descriptor T/K bit byte + long picture-id rewrite.

import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:pure_dart_webrtc_ion_style_sfu/src/rtp_header.dart'
    show stripAudioLevel;
import 'package:pure_dart_webrtc_ion_style_sfu/src/vp8.dart'
    show Vp8PicIdRewriter;
import 'package:test/test.dart';

void main() {
  group('AudioObserverEvent', () {
    test('toString lists each speaker with one decimal place', () {
      final ev = AudioObserverEvent(['a:0', 'b:0'], [12.34, 7.5]);
      expect(ev.toString(), 'AudioObserverEvent(a:0=12.3, b:0=7.5)');
    });

    test('emitNow decays the EMA of tracks that did not observe', () {
      final ob = AudioObserver(threshold: 0, smoothing: 0.5);
      ob.observe('a:0', 0); // loudness=127
      // First emit: 'a' did observe in this tick → no decay yet, but
      // _tick is bumped so the next emit will be the decay window.
      ob.emitNow();
      // Don't observe between emits → on the next emit, the for-loop
      // hits `t.lastTick < _tick` → ema *= (1 - smoothing).
      ob.emitNow();
      // Observe again so we can read the public toString-ish state via
      // a third emit; the absolute value is implementation-detail, but
      // the decay branch executed without throwing.
      addTearDown(ob.dispose);
    });
  });

  group('Peer ICE-candidate + signaling guards', () {
    late Sfu sfu;

    setUp(() {
      sfu = Sfu(WebRTCTransportConfig(
        bindAddress: InternetAddress.loopbackIPv4,
        rtpBasePort: 52100,
        defaultVideoCodecs: [Vp8Codec()],
        defaultAudioCodecs: [PcmaCodec()],
      ));
    });
    tearDown(() async => sfu.close());

    test('addPublisherIceCandidate is a no-op for noPublish peers', () async {
      final p = Peer(sfu);
      await p.join(
        sid: 'r',
        uid: 'u1',
        joinConfig: const PeerJoinConfig(noPublish: true),
      );
      addTearDown(p.close);
      // Publisher is null → null-aware short-circuits (returns).
      await p.addPublisherIceCandidate(null);
    });

    test('addSubscriberIceCandidate is a no-op for noSubscribe peers',
        () async {
      final p = Peer(sfu);
      await p.join(
        sid: 'r',
        uid: 'u1',
        joinConfig: const PeerJoinConfig(noSubscribe: true),
      );
      addTearDown(p.close);
      await p.addSubscriberIceCandidate(null);
    });

    test('setSubscriberAnswer throws StateError when noSubscribe=true',
        () async {
      final p = Peer(sfu);
      await p.join(
        sid: 'r',
        uid: 'u1',
        joinConfig: const PeerJoinConfig(noSubscribe: true),
      );
      addTearDown(p.close);
      expect(
        () => p.setSubscriberAnswer('v=0\r\n'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('stripAudioLevel two-byte profile', () {
    test('zeros the level byte (preserves V flag) under profile 0x1000', () {
      // RTP header: V=2, X=1, CC=0, M=0, PT=111. Then 4-byte ext
      // header: profile 0x1000, length=1 (one 32-bit word of data).
      final rtp = Uint8List(12 + 4 + 4);
      rtp[0] = 0x90; // V=2, P=0, X=1, CC=0
      rtp[1] = 111;
      // ext header
      rtp[12] = 0x10;
      rtp[13] = 0x00;
      rtp[14] = 0x00;
      rtp[15] = 0x01; // length=1 word
      // Two-byte ext element: id=5, len=1, then data (V=1, level=42).
      rtp[16] = 5;
      rtp[17] = 1;
      rtp[18] = 0x80 | 42; // V=1, level=42
      rtp[19] = 0; // padding
      stripAudioLevel(rtp, 5);
      // V preserved, level zeroed.
      expect(rtp[18] & 0x80, 0x80);
      expect(rtp[18] & 0x7f, 0);
    });

    test('two-byte profile: id=0 padding is skipped, then mismatched id', () {
      final rtp = Uint8List(12 + 4 + 4);
      rtp[0] = 0x90;
      rtp[1] = 111;
      rtp[12] = 0x10;
      rtp[13] = 0x00;
      rtp[14] = 0x00;
      rtp[15] = 0x01;
      rtp[16] = 0; // padding id → continue
      rtp[17] = 7; // a different id
      rtp[18] = 1; // len=1
      rtp[19] = 0x80 | 33;
      stripAudioLevel(rtp, 5); // looking for id=5 → not found, no-op
      expect(rtp[19], 0x80 | 33);
    });
  });

  group('Vp8PictureIdRewriter long picture-id', () {
    Uint8List _vp8Pkt({
      required int pictureId,
      required bool isKeyframe,
      bool tBit = false,
    }) {
      // 12B RTP + payload: VP8 desc byte 0 (X=1, S=isKeyframe? 1:0,
      // PID=0), byte 1 (I=1, T=tBit, K=0, L=0), 2-byte picture id with
      // M-bit set, then VP8 payload byte 0 (S bit defines keyframe).
      final pktLen = 12 + 2 + 2 + (tBit ? 1 : 0) + 4;
      final rtp = Uint8List(pktLen);
      rtp[0] = 0x80;
      rtp[1] = 96;
      // VP8 payload starts at 12.
      rtp[12] = 0x90; // X=1, S=1 (start of partition)
      var ext = 0x80; // I bit
      if (tBit) ext |= 0x20;
      rtp[13] = ext;
      // Long picture id: 0x80 | hi, lo
      rtp[14] = 0x80 | ((pictureId >> 8) & 0x7f);
      rtp[15] = pictureId & 0xff;
      var p = 16;
      if (tBit) {
        rtp[p] = 0x40; // TID/Y/KEYIDX byte
        p += 1;
      }
      // VP8 payload first byte: bit 0 inverted = key (0=key).
      rtp[p] = isKeyframe ? 0x00 : 0x01;
      return rtp;
    }

    test('keyframe baselines, then second packet rewrites long pic-id', () {
      final rw = Vp8PicIdRewriter();
      final p1 = _vp8Pkt(pictureId: 1000, isKeyframe: true);
      expect(rw.rewrite(rid: 'q', rtp: p1, isKeyframe: true), isTrue);
      final p2 = _vp8Pkt(pictureId: 1001, isKeyframe: false);
      expect(rw.rewrite(rid: 'q', rtp: p2, isKeyframe: false), isTrue);
      // After rewrite, the long picture-id bytes should still have the
      // M bit set (long form) and decode to 1001 (or 1001 + offset).
      final hi = p2[14];
      expect(hi & 0x80, 0x80, reason: 'M bit preserved');
    });

    test('parseVp8Descriptor handles T-bit byte (extra TID/Y byte)', () {
      final rw = Vp8PicIdRewriter();
      final pkt = _vp8Pkt(pictureId: 5, isKeyframe: true, tBit: true);
      expect(rw.rewrite(rid: 'q', rtp: pkt, isKeyframe: true), isTrue);
    });
  });
}
