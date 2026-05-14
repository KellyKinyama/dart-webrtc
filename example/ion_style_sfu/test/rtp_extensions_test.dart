// Phase 3c — RTP header-extension parser tests.

import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/src/rtp_header.dart';
import 'package:test/test.dart';

/// Build an RTP packet with an extension block. [profile] is the 16-bit
/// extension profile (0xBEDE for one-byte form). [extData] is the raw
/// extension payload that follows the 4-byte extension header; its
/// length must be a multiple of 4.
Uint8List _rtpWithExt({
  required int profile,
  required List<int> extData,
  List<int> payload = const [0xff],
}) {
  assert(extData.length % 4 == 0);
  final out = Uint8List(12 + 4 + extData.length + payload.length);
  out[0] = 0x90; // V=2, X=1
  out[1] = 96;
  out[2] = 0x00;
  out[3] = 0x01; // seq=1
  // ts/ssrc zero
  // extension header
  out[12] = (profile >> 8) & 0xff;
  out[13] = profile & 0xff;
  final lenWords = extData.length ~/ 4;
  out[14] = (lenWords >> 8) & 0xff;
  out[15] = lenWords & 0xff;
  out.setAll(16, extData);
  out.setAll(16 + extData.length, payload);
  return out;
}

void main() {
  group('readRtpExtensions (one-byte form, 0xBEDE)', () {
    test('returns empty when X bit is unset', () {
      final p = Uint8List(12);
      p[0] = 0x80;
      expect(readRtpExtensions(p), isEmpty);
    });

    test('parses a single 1-byte-payload extension', () {
      // id=4, len-1=0 → byte = (4 << 4) | 0 = 0x40, then 1 payload byte,
      // then 3 padding bytes to reach 4-byte multiple.
      final p = _rtpWithExt(
        profile: 0xBEDE,
        extData: [0x40, 0x71 /* 'q' */, 0x00, 0x00],
      );
      final exts = readRtpExtensions(p);
      expect(exts, hasLength(1));
      expect(exts[4], isNotNull);
      expect(exts[4]!.length, 1);
      expect(exts[4]![0], 0x71);
      expect(decodeRidString(exts[4]), 'q');
    });

    test('parses two extensions and skips padding bytes', () {
      // id=2 len=2 ('h' + 0x00), id=5 len=1 ('f'), pad pad pad pad
      final p = _rtpWithExt(
        profile: 0xBEDE,
        extData: [
          0x21, 0x68 /* 'h' */, 0x00, // id=2 len=2 → 1 hdr + 2 data = 3 bytes
          0x50, 0x66 /* 'f' */, // id=5 len=1 → 1 hdr + 1 data = 2 bytes
          0x00, 0x00, 0x00, // padding to 8 bytes total
        ],
      );
      final exts = readRtpExtensions(p);
      expect(exts.keys, containsAll([2, 5]));
      expect(decodeRidString(exts[5]), 'f');
      expect(exts[2]!.length, 2);
      expect(exts[2]![0], 0x68);
    });

    test('id=15 terminates parsing', () {
      // id=4 len=1 'q', then 0xF0 terminator, padding.
      final p = _rtpWithExt(
        profile: 0xBEDE,
        extData: [0x40, 0x71, 0xF0, 0x00],
      );
      final exts = readRtpExtensions(p);
      expect(exts.keys, [4]);
    });
  });

  group('readRtpExtensions (two-byte form, 0x100x)', () {
    test('parses one extension', () {
      // id=10, len=1, data='q', pad pad pad to 4-byte multiple.
      final p = _rtpWithExt(
        profile: 0x1000,
        extData: [10, 1, 0x71 /* 'q' */, 0x00],
      );
      final exts = readRtpExtensions(p);
      expect(exts[10], isNotNull);
      expect(decodeRidString(exts[10]), 'q');
    });

    test('id=0 is one-byte padding', () {
      // pad, id=10 len=1 'h', pad pad
      final p = _rtpWithExt(
        profile: 0x1000,
        extData: [0x00, 10, 1, 0x68],
      );
      final exts = readRtpExtensions(p);
      expect(exts[10], isNotNull);
      expect(decodeRidString(exts[10]), 'h');
    });
  });

  group('decodeRidString', () {
    test('null and empty → null', () {
      expect(decodeRidString(null), isNull);
      expect(decodeRidString(Uint8List(0)), isNull);
    });

    test('multi-byte rid', () {
      expect(decodeRidString(Uint8List.fromList([0x71, 0x31])), 'q1');
    });
  });
}
