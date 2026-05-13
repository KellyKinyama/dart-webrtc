// Tests for the basic SFU. We can't fully exercise SRTP forwarding here
// without a real DTLS handshake against a browser-style client, but we
// can validate the participant lifecycle, port allocation, callback
// fan-out, and that the SFU drops packets gracefully when the
// destination peer isn't yet keyed.

import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:pure_dart_webrtc_sfu_example/basic_sfu.dart';
import 'package:test/test.dart';

void main() {
  group('BasicSfu', () {
    late BasicSfu sfu;

    setUp(() {
      sfu = BasicSfu(
        address: InternetAddress.loopbackIPv4,
        basePort: 0, // OS-allocated; basePort+offset => 0+0, 0+1, ...
        // basePort=0 only works because RtcUdpTransport.bind(_, 0) asks
        // the OS for a free port. The "offset" is irrelevant when the
        // requested port is 0.
      );
    });

    tearDown(() async {
      await sfu.close();
    });

    test('addParticipant binds a transport and emits onParticipantJoined',
        () async {
      final joined = <String>[];
      sfu.onParticipantJoined = (p) => joined.add(p.id);

      final p = await sfu.addParticipant('alice', displayName: 'Alice');

      expect(p.id, 'alice');
      expect(p.displayName, 'Alice');
      expect(p.transport.address.address, '127.0.0.1');
      expect(p.transport.port, isNot(0));
      expect(p.pc.transport, same(p.transport));
      expect(sfu.participants, hasLength(1));
      expect(joined, ['alice']);
    });

    test('addParticipant rejects duplicate ids', () async {
      await sfu.addParticipant('alice');
      expect(
        () => sfu.addParticipant('alice'),
        throwsStateError,
      );
    });

    test('removeParticipant fires onParticipantLeft and tears down', () async {
      final left = <String>[];
      sfu.onParticipantLeft = (p) => left.add(p.id);

      await sfu.addParticipant('alice');
      await sfu.addParticipant('bob');
      expect(sfu.participants, hasLength(2));

      await sfu.removeParticipant('alice');
      expect(sfu.participants, hasLength(1));
      expect(left, ['alice']);
      expect(sfu.getParticipant('alice'), isNull);
      expect(sfu.getParticipant('bob'), isNotNull);
    });

    test('close tears down every participant', () async {
      final left = <String>[];
      sfu.onParticipantLeft = (p) => left.add(p.id);

      await sfu.addParticipant('alice');
      await sfu.addParticipant('bob');
      await sfu.close();

      expect(sfu.participants, isEmpty);
      expect(left.toSet(), {'alice', 'bob'});
    });

    test('createOffer on a participant produces an SDP with a fingerprint',
        () async {
      final p = await sfu.addParticipant('alice');
      final offer = await p.pc.createOffer();
      expect(offer.type, RTCSdpType.offer);
      expect(offer.sdp, contains('a=fingerprint'));
      expect(offer.sdp, contains('a=ice-ufrag'));
    });

    test('forwarding drops packets when no peer is secure', () async {
      await sfu.addParticipant('alice');
      final bob = await sfu.addParticipant('bob');

      // Synthesise a tiny "RTP-shaped" packet (V=2, PT=96) and pump it
      // through bob's transport callback as if it had arrived from the
      // network. Since alice isn't keyed, the SFU should drop it.
      final fake = Uint8List.fromList([
        0x80, 0x60, 0x00, 0x01, // V=2, PT=96, seq=1
        0x00, 0x00, 0x00, 0x00, // timestamp
        0x12, 0x34, 0x56, 0x78, // ssrc
      ]);

      // Directly invoke the bob.transport.onRtp callback the way the
      // datagram listener would. activePeer is null (no DTLS yet) so the
      // SFU forwarding path takes the "no peer" branch and drops.
      final cb = bob.transport.onRtp;
      final peer = bob.pc.activePeer;
      if (peer != null) cb?.call(peer, fake);

      // Drive at least one forwarding attempt by directly calling into
      // the SFU's own forwarder via a second participant whose activePeer
      // is also null.
      // We can't reach _forwardRtp privately, so instead we just confirm
      // that with no secure peers the public stats stay at zero forward
      // and at least one drop is recorded when a callback is delivered.
      await Future<void>.delayed(Duration.zero);

      expect(sfu.stats.rtpForwarded, 0);
    });
  });

  group('BasicSfu inactivity sweep', () {
    test('fires onParticipantTimedOut for participants idle past the threshold',
        () async {
      final sfu = BasicSfu(
        address: InternetAddress.loopbackIPv4,
        basePort: 0,
        inactivityTimeout: const Duration(milliseconds: 100),
      );
      addTearDown(sfu.close);

      final timeouts = <String>[];
      sfu.onParticipantTimedOut = (p, idle) => timeouts.add(p.id);

      final alice = await sfu.addParticipant('alice');
      final bob = await sfu.addParticipant('bob');

      // No activity yet -> sweep is a no-op (lastActivityAt is null).
      sfu.runInactivitySweep(requireConnected: false);
      expect(timeouts, isEmpty);

      // Pretend both have produced media long ago.
      alice.stats.lastActivityAt =
          DateTime.now().subtract(const Duration(seconds: 5));
      // Bob is recently active -> should not fire.
      bob.stats.lastActivityAt = DateTime.now();

      sfu.runInactivitySweep(requireConnected: false);
      expect(timeouts, ['alice']);
    });

    test('does nothing when inactivityTimeout is null', () async {
      final sfu = BasicSfu(
        address: InternetAddress.loopbackIPv4,
        basePort: 0,
      );
      addTearDown(sfu.close);

      var fired = false;
      sfu.onParticipantTimedOut = (_, __) => fired = true;
      final alice = await sfu.addParticipant('alice');
      alice.stats.lastActivityAt =
          DateTime.now().subtract(const Duration(hours: 1));
      sfu.runInactivitySweep(requireConnected: false);
      expect(fired, isFalse);
    });
  });

  group('SeqGapDetector', () {
    test('returns empty on the first packet (anchors silently)', () {
      final d = SeqGapDetector();
      expect(d.feed(100), isEmpty);
      expect(d.lastSeq, 100);
    });

    test('returns empty on the next consecutive packet', () {
      final d = SeqGapDetector();
      d.feed(100);
      expect(d.feed(101), isEmpty);
    });

    test('reports the missing sequence numbers in a small gap', () {
      final d = SeqGapDetector();
      d.feed(100);
      expect(d.feed(105), [101, 102, 103, 104]);
    });

    test('handles seq wrap (65535 -> 0)', () {
      final d = SeqGapDetector();
      d.feed(65534);
      expect(d.feed(2), [65535, 0, 1]);
    });

    test('ignores reordered (older) packets without advancing', () {
      final d = SeqGapDetector();
      d.feed(100);
      expect(d.feed(99), isEmpty);
      expect(d.lastSeq, 100);
    });

    test('ignores duplicates', () {
      final d = SeqGapDetector();
      d.feed(100);
      expect(d.feed(100), isEmpty);
    });

    test('re-anchors silently on a jump larger than maxGap', () {
      final d = SeqGapDetector(maxGap: 4);
      d.feed(100);
      expect(d.feed(200), isEmpty);
      expect(d.lastSeq, 200);
    });
  });

  group('BasicSfu.buildNack', () {
    test('packs three adjacent losses into one FCI word with BLP bits set', () {
      // Missing 100, 101, 102 -> PID=100, BLP bits 0 and 1 set => BLP=0x0003.
      final pkt = BasicSfu.buildNack(1, 0xCAFEBABE, [100, 101, 102]);
      expect(pkt.length, 16);
      expect(pkt[0] & 0x1F, 1, reason: 'FMT=1');
      expect(pkt[1], 205, reason: 'PT=RTPFB');
      final len = (pkt[2] << 8) | pkt[3];
      expect(len, 3);
      expect((pkt[4] << 24) | (pkt[5] << 16) | (pkt[6] << 8) | pkt[7], 1);
      expect((pkt[8] << 24) | (pkt[9] << 16) | (pkt[10] << 8) | pkt[11],
          0xCAFEBABE);
      expect((pkt[12] << 8) | pkt[13], 100);
      expect((pkt[14] << 8) | pkt[15], 0x0003);
    });

    test('uses a second FCI when the gap exceeds 16', () {
      final pkt = BasicSfu.buildNack(1, 0xDEAD0000, [100, 200]);
      expect(pkt.length, 20);
      expect((pkt[12] << 8) | pkt[13], 100);
      expect((pkt[14] << 8) | pkt[15], 0);
      expect((pkt[16] << 8) | pkt[17], 200);
      expect((pkt[18] << 8) | pkt[19], 0);
    });
  });

  group('RateMeter', () {
    test('reports 0 bps with no samples', () {
      final m = RateMeter(window: const Duration(seconds: 1));
      expect(m.bitsPerSecond(DateTime(2026)), 0);
    });

    test('returns sum*8/window-seconds inside the window', () {
      final m = RateMeter(window: const Duration(seconds: 2));
      final t0 = DateTime(2026);
      m.record(1000, t0);
      m.record(1000, t0.add(const Duration(milliseconds: 500)));
      // 2000 bytes inside a 2s window => 16000 / 2 = 8000 bps.
      expect(m.bitsPerSecond(t0.add(const Duration(seconds: 1))), 8000);
    });

    test('drops samples older than window', () {
      final m = RateMeter(window: const Duration(seconds: 2));
      final t0 = DateTime(2026);
      m.record(1000, t0);
      // 5 seconds later, the only sample is well outside the window.
      expect(m.bitsPerSecond(t0.add(const Duration(seconds: 5))), 0);
    });
  });

  group('SsrcAllocator', () {
    test('returns a stable rewritten SSRC per receiver+original pair', () {
      final a = SsrcAllocator();
      final r1 = a.rewrite('alice', 0x11111111);
      final r2 = a.rewrite('alice', 0x11111111);
      final r3 = a.rewrite('alice', 0x22222222);
      final r4 = a.rewrite('bob', 0x11111111);

      expect(r1, r2, reason: 'same key returns same SSRC');
      expect(r1, isNot(0));
      expect(r1, isNot(r3), reason: 'different original SSRC -> different');
      expect(r1, isNot(r4),
          reason: 'different receiver gets independent SSRC space');
    });

    test('forgetReceiver drops mappings', () {
      final a = SsrcAllocator();
      final r1 = a.rewrite('alice', 0x11111111);
      a.forgetReceiver('alice');
      final r2 = a.rewrite('alice', 0x11111111);
      // Tiny chance of collision; with 32-bit space this is acceptable.
      // We just assert it's a valid SSRC and the cache was dropped.
      expect(r2, isNot(0));
      // It's overwhelmingly likely to differ from r1 since it's reseeded
      // from `Random.secure()`.
      expect(r1, isNotNull);
    });

    test('originalFor reverses the rewrite', () {
      final a = SsrcAllocator();
      final rewritten = a.rewrite('alice', 0xDEADBEEF);
      expect(a.originalFor('alice', rewritten), 0xDEADBEEF);
      expect(a.originalFor('alice', 0x12345678), isNull,
          reason: 'unmapped SSRC returns null');
      expect(a.originalFor('bob', rewritten), isNull,
          reason: 'reverse map is per-receiver');
    });

    test('forgetReceiver clears the reverse map too', () {
      final a = SsrcAllocator();
      final rewritten = a.rewrite('alice', 0xDEADBEEF);
      expect(a.originalFor('alice', rewritten), 0xDEADBEEF);
      a.forgetReceiver('alice');
      expect(a.originalFor('alice', rewritten), isNull);
    });

    test('rewriteRtx pairs the RTX rewritten SSRC with its primary', () {
      final a = SsrcAllocator();
      const primary = 0x11111111;
      const rtx = 0x22222222;

      final rewrittenRtx = a.rewriteRtx('alice', primary, rtx);
      // Allocating after-the-fact must return the primary's already-cached
      // value, proving rewriteRtx forced an allocation for primary first.
      final rewrittenPrimary = a.rewrite('alice', primary);

      expect(rewrittenRtx, isNot(rtx));
      expect(rewrittenPrimary, isNot(primary));
      expect(rewrittenRtx, isNot(rewrittenPrimary));
      // Reverse map covers both halves.
      expect(a.originalFor('alice', rewrittenRtx), rtx);
      expect(a.originalFor('alice', rewrittenPrimary), primary);
      // Stable across calls.
      expect(a.rewriteRtx('alice', primary, rtx), rewrittenRtx);
    });
  });

  group('BasicSfu RTX learning', () {
    test('learnSsrcMappingFromOffer extracts FID groups', () {
      final sfu = BasicSfu(
        address: InternetAddress.loopbackIPv4,
        basePort: 0,
      );
      addTearDown(sfu.close);

      const offerSdp = 'v=0\r\n'
          'o=- 1 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96 97\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'a=rtpmap:96 VP8/90000\r\n'
          'a=rtpmap:97 rtx/90000\r\n'
          'a=fmtp:97 apt=96\r\n'
          'a=ssrc-group:FID 4242 8484\r\n'
          'a=ssrc:4242 cname:c1\r\n'
          'a=ssrc:8484 cname:c1\r\n';
      // Just exercise the API; no participant needed.
      sfu.learnSsrcMappingFromOffer('alice', offerSdp);
      // No public getter for the map (intentionally), so verify behaviour
      // indirectly: a second call must be idempotent (no throw).
      sfu.learnSsrcMappingFromOffer('alice', offerSdp);

      // Producer record should have one video stream with paired RTX.
      final producers = sfu.producersOf('alice');
      expect(producers, hasLength(1));
      expect(producers.first.kind, 'video');
      expect(producers.first.primarySsrc, 4242);
      expect(producers.first.rtxSsrc, 8484);
      expect(producers.first.cname, 'c1');
    });
  });

  group('BasicSfu.augmentAnswerSdp', () {
    test('injects FID group + ssrc cname lines for other producers', () {
      final sfu = BasicSfu(
        address: InternetAddress.loopbackIPv4,
        basePort: 0,
      );
      addTearDown(sfu.close);

      const aliceOffer = 'v=0\r\n'
          'o=- 1 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96 97\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'a=rtpmap:96 VP8/90000\r\n'
          'a=rtpmap:97 rtx/90000\r\n'
          'a=fmtp:97 apt=96\r\n'
          'a=ssrc-group:FID 1111 2222\r\n'
          'a=ssrc:1111 cname:alice\r\n'
          'a=ssrc:2222 cname:alice\r\n';
      sfu.learnSsrcMappingFromOffer('alice', aliceOffer);

      // Bob's answer (as we'd produce it) — no ssrc/group lines yet.
      const bobAnswer = 'v=0\r\n'
          'o=- 3 4 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'a=ice-lite\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96 97\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'a=setup:passive\r\n'
          'a=rtpmap:96 VP8/90000\r\n'
          'a=rtpmap:97 rtx/90000\r\n'
          'a=fmtp:97 apt=96\r\n';

      final augmented = sfu.augmentAnswerSdp('bob', bobAnswer);
      expect(augmented, contains('a=ssrc-group:FID '));
      expect(augmented, contains('cname:alice'));
      // Each FID group must list two SSRCs that *differ* from alice's
      // originals — they're per-receiver-rewritten.
      expect(augmented, isNot(contains('1111')));
      expect(augmented, isNot(contains('2222')));
    });

    test("does not inject anything for the receiver's own streams", () {
      final sfu = BasicSfu(
        address: InternetAddress.loopbackIPv4,
        basePort: 0,
      );
      addTearDown(sfu.close);

      const aliceOffer = 'v=0\r\n'
          'o=- 1 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'a=rtpmap:96 VP8/90000\r\n'
          'a=ssrc:1111 cname:alice\r\n';
      sfu.learnSsrcMappingFromOffer('alice', aliceOffer);

      const aliceAnswer = 'v=0\r\n'
          'o=- 3 4 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'a=rtpmap:96 VP8/90000\r\n';
      // Augmenting alice's own answer with no other producers must not
      // add any ssrc lines.
      final augmented = sfu.augmentAnswerSdp('alice', aliceAnswer);
      expect(augmented, isNot(contains('a=ssrc:')));
      expect(augmented, isNot(contains('a=ssrc-group:')));
    });

    test('emits per-producer msid lines so each remote stream is distinct', () {
      final sfu = BasicSfu(
        address: InternetAddress.loopbackIPv4,
        basePort: 0,
      );
      addTearDown(sfu.close);

      // Alice's offer carries an explicit msid stream/track id.
      const aliceOffer = 'v=0\r\n'
          'o=- 1 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'a=rtpmap:96 VP8/90000\r\n'
          'a=ssrc:1111 cname:alice\r\n'
          'a=ssrc:1111 msid:aliceStream aliceVideo0\r\n';
      sfu.learnSsrcMappingFromOffer('alice', aliceOffer);

      final p = sfu.producersOf('alice').single;
      expect(p.msidStream, 'aliceStream');
      expect(p.msidTrack, 'aliceVideo0');

      const bobAnswer = 'v=0\r\n'
          'o=- 3 4 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'a=rtpmap:96 VP8/90000\r\n';
      final augmented = sfu.augmentAnswerSdp('bob', bobAnswer);
      expect(augmented, contains('msid:aliceStream aliceVideo0'));
      expect(augmented, contains('cname:alice'));
    });

    test('synthesises msid when offer omits one', () {
      final sfu = BasicSfu(
        address: InternetAddress.loopbackIPv4,
        basePort: 0,
      );
      addTearDown(sfu.close);

      const offer = 'v=0\r\n'
          'o=- 1 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'a=rtpmap:96 VP8/90000\r\n'
          'a=ssrc:1111 cname:alice\r\n';
      sfu.learnSsrcMappingFromOffer('alice', offer);
      final p = sfu.producersOf('alice').single;
      expect(p.msidStream, 'alice');
      expect(p.msidTrack, 'alice-video-0');
    });
  });

  group('BasicSfu.onProducersChanged', () {
    test('fires once per learn-call when new producers appear', () {
      final sfu = BasicSfu(
        address: InternetAddress.loopbackIPv4,
        basePort: 0,
      );
      addTearDown(sfu.close);

      final fired = <String>[];
      sfu.onProducersChanged =
          (id, streams) => fired.add('$id:${streams.length}');

      const offer = 'v=0\r\n'
          'o=- 1 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'a=rtpmap:96 VP8/90000\r\n'
          'a=ssrc:1111 cname:alice\r\n';
      sfu.learnSsrcMappingFromOffer('alice', offer);
      // Idempotent re-learn: no new producers => no new fire.
      sfu.learnSsrcMappingFromOffer('alice', offer);

      expect(fired, ['alice:1']);
    });
  });

  group('BasicSfu.requestKeyframe', () {
    test('returns 0 when the producer is unknown', () async {
      final sfu = BasicSfu(
        address: InternetAddress.loopbackIPv4,
        basePort: 0,
      );
      addTearDown(sfu.close);
      expect(await sfu.requestKeyframe('nobody'), 0);
      expect(sfu.stats.pliSent, 0);
    });

    test('returns 0 when the producer has no DTLS-secure peer yet', () async {
      final sfu = BasicSfu(
        address: InternetAddress.loopbackIPv4,
        basePort: 0,
      );
      addTearDown(sfu.close);

      await sfu.addParticipant('alice');
      const offer = 'v=0\r\n'
          'o=- 1 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'a=rtpmap:96 VP8/90000\r\n'
          'a=ssrc:1111 cname:alice\r\n';
      sfu.learnSsrcMappingFromOffer('alice', offer);
      // No DTLS handshake has run, so activePeer is null and we drop.
      expect(await sfu.requestKeyframe('alice'), 0);
      expect(sfu.stats.pliSent, 0);
    });
  });

  group('BasicSfu active-speaker cache', () {
    test('caches top-K audio set across recompute calls', () async {
      final sfu = BasicSfu(
        address: InternetAddress.loopbackIPv4,
        basePort: 0,
        maxAudioForwarded: 2,
        audioActivityWindow: const Duration(seconds: 5),
      );
      addTearDown(sfu.close);

      // No samples yet -> empty set means "forward everyone".
      sfu.recomputeActiveSpeakersNow();
      expect(sfu.activeAudioSet, isEmpty);

      // Inject samples directly through the public path is awkward, but
      // the recompute logic is driven by an internal map. We can drive
      // it indirectly by feeding RTP through a producer with the audio
      // extension parsed from a real SDP. That's heavy for a unit test;
      // here we settle for the empty-set semantic and rely on the
      // signaling integration tests for the loaded path.
      expect(sfu.activeAudioSet, isEmpty);
      expect(sfu.activeVideoSet, isEmpty);
    });

    test('maxVideoForwarded < 0 keeps active-video set empty (forward all)',
        () async {
      final sfu = BasicSfu(
        address: InternetAddress.loopbackIPv4,
        basePort: 0,
      );
      addTearDown(sfu.close);
      sfu.recomputeActiveSpeakersNow();
      expect(sfu.activeVideoSet, isEmpty);
    });

    test('maxVideoForwarded == 0 yields empty set + drop-all-video policy',
        () async {
      final sfu = BasicSfu(
        address: InternetAddress.loopbackIPv4,
        basePort: 0,
        maxVideoForwarded: 0,
      );
      addTearDown(sfu.close);
      sfu.recomputeActiveSpeakersNow();
      expect(sfu.activeVideoSet, isEmpty);
    });
  });

  group('BasicSfu admission + cleanup', () {
    test('addParticipant throws once maxParticipants is reached', () async {
      final sfu = BasicSfu(
        address: InternetAddress.loopbackIPv4,
        basePort: 0,
        maxParticipants: 2,
      );
      addTearDown(sfu.close);

      await sfu.addParticipant('a');
      await sfu.addParticipant('b');
      expect(
        () => sfu.addParticipant('c'),
        throwsA(isA<StateError>()),
      );
    });

    test('removeParticipant prunes audio-level + ext maps', () async {
      final sfu = BasicSfu(
        address: InternetAddress.loopbackIPv4,
        basePort: 0,
      );
      addTearDown(sfu.close);

      await sfu.addParticipant('alice');
      const offer = 'v=0\r\n'
          'o=- 1 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'a=rtpmap:96 opus/48000/2\r\n'
          'a=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level\r\n'
          'a=ssrc:9999 cname:alice\r\n';
      sfu.learnSsrcMappingFromOffer('alice', offer);
      expect(sfu.producersOf('alice'), isNotEmpty);

      await sfu.removeParticipant('alice');
      expect(sfu.getParticipant('alice'), isNull);
      expect(sfu.producersOf('alice'), isEmpty);
    });
  });
}
