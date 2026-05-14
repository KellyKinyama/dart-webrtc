import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

void _w32(Uint8List b, int o, int v) {
  b[o] = (v >> 24) & 0xff;
  b[o + 1] = (v >> 16) & 0xff;
  b[o + 2] = (v >> 8) & 0xff;
  b[o + 3] = v & 0xff;
}

int _r32(Uint8List b, int o) =>
    ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]) & 0xffffffff;

/// Build an SR (PT=200) with optional report blocks. Each block is a
/// (sourceSsrc, fractionLost, cumulativeLost) tuple; the rest of the
/// 24-byte block is zero-padded.
Uint8List buildSr({
  required int senderSsrc,
  required int ntpHi,
  required int ntpLo,
  required int rtpTs,
  required int pktCount,
  required int octetCount,
  List<int> reportBlockSsrcs = const [],
}) {
  final rc = reportBlockSsrcs.length;
  final lenBytes = 28 + rc * 24;
  final lengthWords = (lenBytes ~/ 4) - 1;
  final b = Uint8List(lenBytes);
  b[0] = 0x80 | (rc & 0x1F); // V=2, P=0, RC
  b[1] = 200;
  b[2] = (lengthWords >> 8) & 0xff;
  b[3] = lengthWords & 0xff;
  _w32(b, 4, senderSsrc);
  _w32(b, 8, ntpHi);
  _w32(b, 12, ntpLo);
  _w32(b, 16, rtpTs);
  _w32(b, 20, pktCount);
  _w32(b, 24, octetCount);
  for (var i = 0; i < rc; i++) {
    _w32(b, 28 + i * 24, reportBlockSsrcs[i]);
  }
  return b;
}

Uint8List buildRr({
  required int senderSsrc,
  List<int> reportBlockSsrcs = const [],
}) {
  final rc = reportBlockSsrcs.length;
  final lenBytes = 8 + rc * 24;
  final lengthWords = (lenBytes ~/ 4) - 1;
  final b = Uint8List(lenBytes);
  b[0] = 0x80 | (rc & 0x1F);
  b[1] = 201;
  b[2] = (lengthWords >> 8) & 0xff;
  b[3] = lengthWords & 0xff;
  _w32(b, 4, senderSsrc);
  for (var i = 0; i < rc; i++) {
    _w32(b, 8 + i * 24, reportBlockSsrcs[i]);
  }
  return b;
}

/// Build a minimal SDES (PT=202) with one CNAME chunk for [ssrc].
Uint8List buildSdes(int ssrc, String cname) {
  final cb = cname.codeUnits;
  // chunk: 4-byte SSRC + 1 type + 1 len + cname + 1 NUL terminator,
  // padded to 4-byte boundary.
  final raw = 4 + 2 + cb.length + 1;
  final padded = ((raw + 3) ~/ 4) * 4;
  final lenBytes = 4 + padded;
  final lengthWords = (lenBytes ~/ 4) - 1;
  final b = Uint8List(lenBytes);
  b[0] = 0x81; // V=2, SC=1
  b[1] = 202;
  b[2] = (lengthWords >> 8) & 0xff;
  b[3] = lengthWords & 0xff;
  _w32(b, 4, ssrc);
  b[8] = 1; // CNAME
  b[9] = cb.length;
  for (var i = 0; i < cb.length; i++) {
    b[10 + i] = cb[i];
  }
  return b;
}

void main() {
  group('rewriteRtcpForSubscriber - SR', () {
    test('translates header SSRC and shifts RTP ts', () {
      final sr = buildSr(
        senderSsrc: 0x11111111,
        ntpHi: 0xCAFEBABE,
        ntpLo: 0xDEADBEEF,
        rtpTs: 1000,
        pktCount: 50,
        octetCount: 7000,
      );
      final map = RtcpSsrcMap();
      map.primary[0x11111111] = 0x99999999;
      final out = rewriteRtcpForSubscriber(sr, map,
          tsOffsetFor: (s) => s == 0x11111111 ? 500 : null);
      expect(_r32(out, 4), 0x99999999);
      expect(_r32(out, 8), 0xCAFEBABE); // NTP hi untouched
      expect(_r32(out, 12), 0xDEADBEEF); // NTP lo untouched
      expect(_r32(out, 16), 1500);
      expect(_r32(out, 20), 50); // pkt count untouched
      expect(_r32(out, 24), 7000);
    });

    test('leaves SSRC untouched when not in map', () {
      final sr = buildSr(
        senderSsrc: 0x22222222,
        ntpHi: 0,
        ntpLo: 0,
        rtpTs: 1000,
        pktCount: 0,
        octetCount: 0,
      );
      final map = RtcpSsrcMap()..primary[0x11111111] = 0x99999999;
      final out = rewriteRtcpForSubscriber(sr, map, tsOffsetFor: (_) => 500);
      expect(_r32(out, 4), 0x22222222);
      expect(_r32(out, 16), 1000); // ts not shifted either
    });

    test('does not shift ts when callback returns null', () {
      final sr = buildSr(
        senderSsrc: 0x11111111,
        ntpHi: 0,
        ntpLo: 0,
        rtpTs: 1000,
        pktCount: 0,
        octetCount: 0,
      );
      final map = RtcpSsrcMap()..primary[0x11111111] = 0x99999999;
      final out = rewriteRtcpForSubscriber(sr, map, tsOffsetFor: (_) => null);
      expect(_r32(out, 4), 0x99999999);
      expect(_r32(out, 16), 1000);
    });

    test('does not shift ts when callback omitted', () {
      final sr = buildSr(
        senderSsrc: 0x11111111,
        ntpHi: 0,
        ntpLo: 0,
        rtpTs: 1000,
        pktCount: 0,
        octetCount: 0,
      );
      final map = RtcpSsrcMap()..primary[0x11111111] = 0x99999999;
      final out = rewriteRtcpForSubscriber(sr, map);
      expect(_r32(out, 16), 1000);
    });

    test('translates report-block source SSRCs', () {
      final sr = buildSr(
        senderSsrc: 0x11111111,
        ntpHi: 0,
        ntpLo: 0,
        rtpTs: 0,
        pktCount: 0,
        octetCount: 0,
        reportBlockSsrcs: [0x11111111, 0x22222222],
      );
      final map = RtcpSsrcMap()
        ..primary[0x11111111] = 0x99999999
        ..primary[0x22222222] = 0x88888888;
      final out = rewriteRtcpForSubscriber(sr, map);
      expect(_r32(out, 28), 0x99999999);
      expect(_r32(out, 28 + 24), 0x88888888);
    });

    test('ts wraps modulo 2^32', () {
      final sr = buildSr(
        senderSsrc: 0x11111111,
        ntpHi: 0,
        ntpLo: 0,
        rtpTs: 0xFFFFFF00,
        pktCount: 0,
        octetCount: 0,
      );
      final map = RtcpSsrcMap()..primary[0x11111111] = 0x99999999;
      final out = rewriteRtcpForSubscriber(sr, map, tsOffsetFor: (_) => 0x200);
      // 0xFFFFFF00 + 0x200 = 0x100000100 → wrap → 0x100
      expect(_r32(out, 16), 0x100);
    });

    test('translates RTX SSRC via rtx map', () {
      final sr = buildSr(
        senderSsrc: 0xAAAA0001,
        ntpHi: 0,
        ntpLo: 0,
        rtpTs: 0,
        pktCount: 0,
        octetCount: 0,
      );
      final map = RtcpSsrcMap()..rtx[0xAAAA0001] = 0xBBBB0001;
      final out = rewriteRtcpForSubscriber(sr, map);
      expect(_r32(out, 4), 0xBBBB0001);
    });
  });

  group('rewriteRtcpForSubscriber - RR', () {
    test('leaves sender SSRC alone, translates report blocks', () {
      final rr = buildRr(
        senderSsrc: 0xCCCCCCCC,
        reportBlockSsrcs: [0x11111111, 0x33333333],
      );
      final map = RtcpSsrcMap()
        ..primary[0x11111111] = 0x99999999
        ..primary[0x33333333] = 0x77777777;
      final out = rewriteRtcpForSubscriber(rr, map);
      expect(_r32(out, 4), 0xCCCCCCCC); // sender (the receiver) untouched
      expect(_r32(out, 8), 0x99999999);
      expect(_r32(out, 8 + 24), 0x77777777);
    });

    test('unknown report-block SSRCs pass through', () {
      final rr = buildRr(
        senderSsrc: 0xCCCCCCCC,
        reportBlockSsrcs: [0xDEADBEEF],
      );
      final map = RtcpSsrcMap()..primary[0x11111111] = 0x99999999;
      final out = rewriteRtcpForSubscriber(rr, map);
      expect(_r32(out, 8), 0xDEADBEEF);
    });
  });

  group('rewriteRtcpForSubscriber - compound & passthrough', () {
    test('SR + SDES — SR rewritten, SDES untouched', () {
      final sr = buildSr(
        senderSsrc: 0x11111111,
        ntpHi: 0,
        ntpLo: 0,
        rtpTs: 100,
        pktCount: 0,
        octetCount: 0,
      );
      final sdes = buildSdes(0x11111111, 'pub');
      final compound = Uint8List(sr.length + sdes.length)
        ..setRange(0, sr.length, sr)
        ..setRange(sr.length, sr.length + sdes.length, sdes);
      final map = RtcpSsrcMap()..primary[0x11111111] = 0x99999999;
      final out =
          rewriteRtcpForSubscriber(compound, map, tsOffsetFor: (_) => 50);
      expect(_r32(out, 4), 0x99999999);
      expect(_r32(out, 16), 150);
      // SDES preserved verbatim.
      final sdesOut = out.sublist(sr.length);
      expect(sdesOut, equals(sdes));
    });

    test('NACK (PT=205) passes through unchanged', () {
      final nack = buildNack(0x11111111, 0x11111111, [42]);
      final map = RtcpSsrcMap()..primary[0x11111111] = 0x99999999;
      final out = rewriteRtcpForSubscriber(nack, map);
      expect(out, equals(nack));
    });

    test('REMB (PT=206 PSFB) passes through unchanged', () {
      final remb = buildRemb(0x11111111, 500000, [0x11111111]);
      final map = RtcpSsrcMap()..primary[0x11111111] = 0x99999999;
      final out = rewriteRtcpForSubscriber(remb, map);
      expect(out, equals(remb));
    });

    test('empty buffer returns empty', () {
      final out = rewriteRtcpForSubscriber(Uint8List(0), RtcpSsrcMap());
      expect(out, isEmpty);
    });

    test('truncated header is tolerated (returns copy)', () {
      final buf = Uint8List.fromList([0x80, 200, 0]); // 3 bytes
      final out = rewriteRtcpForSubscriber(buf, RtcpSsrcMap()..primary[1] = 2);
      expect(out, equals(buf));
    });

    test('declared length exceeds buffer — stops cleanly', () {
      final sr = buildSr(
        senderSsrc: 0x11111111,
        ntpHi: 0,
        ntpLo: 0,
        rtpTs: 0,
        pktCount: 0,
        octetCount: 0,
      );
      // Patch length to claim 100 words while buffer is 28 bytes.
      sr[2] = 0;
      sr[3] = 100;
      final map = RtcpSsrcMap()..primary[0x11111111] = 0x99999999;
      final out = rewriteRtcpForSubscriber(sr, map);
      // Should not crash; SR isn't rewritten because its declared
      // length runs past the buffer end.
      expect(_r32(out, 4), 0x11111111);
    });
  });
}
