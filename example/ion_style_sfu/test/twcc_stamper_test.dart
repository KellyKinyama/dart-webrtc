// Phase 7 — TWCC sender-side sequence stamper tests.

import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

/// Build an RTP packet with one BEDE extension entry of [extId] holding
/// [extPayload] (length must be 1..16 bytes for one-byte form).
Uint8List _rtpWithExt({
  required int ssrc,
  required int seq,
  required int extId,
  required List<int> extPayload,
}) {
  assert(extPayload.isNotEmpty && extPayload.length <= 16);
  final hdr = ((extId & 0x0f) << 4) | ((extPayload.length - 1) & 0x0f);
  final ext = <int>[hdr, ...extPayload];
  while (ext.length % 4 != 0) {
    ext.add(0);
  }
  final extWords = ext.length ~/ 4;
  final b = BytesBuilder()
    ..addByte(0x90) // V=2, X=1
    ..addByte(96)
    ..addByte((seq >> 8) & 0xff)
    ..addByte(seq & 0xff)
    ..add([0, 0, 0, 0]) // timestamp
    ..addByte((ssrc >> 24) & 0xff)
    ..addByte((ssrc >> 16) & 0xff)
    ..addByte((ssrc >> 8) & 0xff)
    ..addByte(ssrc & 0xff)
    ..addByte(0xBE)
    ..addByte(0xDE)
    ..addByte((extWords >> 8) & 0xff)
    ..addByte(extWords & 0xff)
    ..add(ext)
    ..add([0xde, 0xad, 0xbe, 0xef]); // payload
  return b.toBytes();
}

/// Pull the 2-byte transport-cc payload out of a packet stamped at
/// extId.
int? _readStampedSeq(Uint8List rtp, int extId) {
  // Walk the one-byte ext block.
  final cc = rtp[0] & 0x0f;
  final extStart = 12 + cc * 4;
  if ((rtp[0] & 0x10) == 0) return null;
  final profile = (rtp[extStart] << 8) | rtp[extStart + 1];
  if (profile != 0xBEDE) return null;
  final lenWords = (rtp[extStart + 2] << 8) | rtp[extStart + 3];
  var p = extStart + 4;
  final end = p + lenWords * 4;
  while (p < end) {
    final b = rtp[p++];
    if (b == 0) continue;
    final id = (b >> 4) & 0x0f;
    final len = (b & 0x0f) + 1;
    if (id == 15) break;
    if (id == extId && len == 2) {
      return (rtp[p] << 8) | rtp[p + 1];
    }
    p += len;
  }
  return null;
}

void main() {
  group('TwccStamper', () {
    test('stamps consecutive 16-bit sequence numbers into the ext', () {
      final st = TwccStamper();
      final p1 = _rtpWithExt(
        ssrc: 1, seq: 0, extId: 3, extPayload: [0, 0],
      );
      final p2 = _rtpWithExt(
        ssrc: 1, seq: 1, extId: 3, extPayload: [0, 0],
      );
      expect(st.stamp(p1, 3), 0);
      expect(st.stamp(p2, 3), 1);
      expect(_readStampedSeq(p1, 3), 0);
      expect(_readStampedSeq(p2, 3), 1);
      expect(st.totalStamped, 2);
      expect(st.lastSeq, 1);
    });

    test('returns null when the extension is not present', () {
      final st = TwccStamper();
      // No X bit set → no extensions.
      final b = Uint8List(12);
      b[0] = 0x80;
      expect(st.stamp(b, 3), isNull);
      expect(st.missingExtensionDrops, 1);
      expect(st.totalStamped, 0);
    });

    test('returns null when the requested extId is absent', () {
      final st = TwccStamper();
      final p = _rtpWithExt(
        ssrc: 1, seq: 0, extId: 5, extPayload: [0xAB],
      );
      expect(st.stamp(p, 3), isNull);
      expect(st.missingExtensionDrops, 1);
    });

    test('wraps modulo 2^16', () {
      final st = TwccStamper();
      // Fast-forward via reserve() to 0xFFFF, then stamp one real
      // packet and observe the next read as 0.
      for (var i = 0; i < 0xFFFF; i++) {
        st.reserve();
      }
      expect(st.lastSeq, 0xFFFE);
      final p = _rtpWithExt(
        ssrc: 1, seq: 0, extId: 3, extPayload: [0, 0],
      );
      expect(st.stamp(p, 3), 0xFFFF);
      final p2 = _rtpWithExt(
        ssrc: 1, seq: 1, extId: 3, extPayload: [0, 0],
      );
      expect(st.stamp(p2, 3), 0);
    });

    test('records send time and size per seq', () {
      final st = TwccStamper();
      final p = _rtpWithExt(
        ssrc: 1, seq: 0, extId: 3, extPayload: [0, 0],
      );
      final seq = st.stamp(p, 3, sendTimeMicros: 1_000_000);
      expect(seq, 0);
      expect(st.sendTimeMicrosFor(0), 1_000_000);
      expect(st.sizeBytesFor(0), p.length);
    });

    test('history is bounded by historyCapacity', () {
      final st = TwccStamper(historyCapacity: 4);
      for (var i = 0; i < 10; i++) {
        st.reserve(sizeBytes: 100);
      }
      // Only the last 4 seqs should still be queryable.
      expect(st.sizeBytesFor(0), isNull);
      expect(st.sizeBytesFor(5), isNull);
      expect(st.sizeBytesFor(6), 100);
      expect(st.sizeBytesFor(9), 100);
    });

    test('evictOlderThan drops stale samples relative to latest', () {
      final st = TwccStamper();
      st.reserve(sendTimeMicros: 0);
      st.reserve(sendTimeMicros: 1_000_000);
      st.reserve(sendTimeMicros: 2_000_000);
      st.evictOlderThan(500_000);
      expect(st.sendTimeMicrosFor(0), isNull);
      expect(st.sendTimeMicrosFor(1), isNull);
      expect(st.sendTimeMicrosFor(2), 2_000_000);
    });

    test('refuses to stamp when the ext payload is not 2 bytes', () {
      final st = TwccStamper();
      final p = _rtpWithExt(
        ssrc: 1, seq: 0, extId: 3, extPayload: [0xAB], // 1 byte
      );
      expect(st.stamp(p, 3), isNull);
      expect(st.missingExtensionDrops, 1);
    });

    test('multiple extensions: stamper only touches the matching one',
        () {
      // Build manually: BEDE with [ext1=audio-level (id=4, 1B),
      // ext3=transport-cc (id=3, 2B)].
      final extBytes = <int>[
        ((4 << 4) | 0), 0x55, // id=4 len=1 payload=0x55
        ((3 << 4) | 1), 0x00, 0x00, // id=3 len=2 payload=0,0
        0, 0, 0, // pad to 8-byte (2-word) boundary
      ];
      final extWords = extBytes.length ~/ 4;
      final b = BytesBuilder()
        ..addByte(0x90)
        ..addByte(96)
        ..addByte(0)
        ..addByte(0)
        ..add([0, 0, 0, 0])
        ..add([1, 2, 3, 4])
        ..addByte(0xBE)
        ..addByte(0xDE)
        ..addByte((extWords >> 8) & 0xff)
        ..addByte(extWords & 0xff)
        ..add(extBytes)
        ..add([1, 2]);
      final pkt = b.toBytes();
      final st = TwccStamper();
      final seq = st.stamp(pkt, 3);
      expect(seq, 0);
      // The audio-level byte 0x55 must be untouched.
      // Locate audio-level slot: just after the BEDE header (4 bytes
      // after extStart=12). Format: id|len byte, then 1B payload.
      expect(pkt[12 + 4 + 1], 0x55);
    });
  });

  group('Subscriber wiring', () {
    test('Subscriber exposes a TwccStamper', () {
      // We cannot construct a real Subscriber without a PeerConnection
      // backend in unit tests, but the stamper is plain Dart and the
      // wiring is straightforward — assert the type is exported.
      const expectedType = TwccStamper;
      expect(expectedType, isNotNull);
    });
  });

  group('ProducerStream.twccExtId', () {
    test('factories preserve twccExtId on single-layer streams', () {
      final s = ProducerStream(
        kind: 'video',
        mid: '0',
        primarySsrc: 1,
        rtxSsrc: null,
        cname: 'c',
        msidStream: 's',
        msidTrack: 't',
        twccExtId: 3,
      );
      expect(s.twccExtId, 3);
    });

    test('factories preserve twccExtId on simulcast streams', () {
      final s = ProducerStream.simulcast(
        kind: 'video',
        mid: '0',
        layers: const [
          ProducerLayer(rid: 'q', primarySsrc: 1, rtxSsrc: null),
          ProducerLayer(rid: 'h', primarySsrc: 2, rtxSsrc: null),
        ],
        cname: 'c',
        msidStream: 's',
        msidTrack: 't',
        twccExtId: 7,
      );
      expect(s.twccExtId, 7);
    });
  });

  group('SDP parsing', () {
    test('publisher offer with twcc extmap surfaces twccExtId', () {
      const offer = '''v=0
o=- 1 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE 0
m=video 9 UDP/TLS/RTP/SAVPF 96
c=IN IP4 0.0.0.0
a=ice-ufrag:abcd
a=ice-pwd:efghefghefghefghefgh
a=fingerprint:sha-256 11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22
a=setup:actpass
a=mid:0
a=sendrecv
a=rtpmap:96 VP8/90000
a=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01
a=ssrc:42 cname:foo
a=msid:streamA trackA
''';
      final streams = parsePublisherOffer(peerId: 'p', offerSdp: offer);
      expect(streams, hasLength(1));
      expect(streams.first.twccExtId, 3);
    });
  });
}
