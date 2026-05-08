// Conformance runner: decode every VP8 (and optionally VP9) IVF test vector
// and compare per-frame I420 MD5s against the matching `<name>.ivf.md5` file.
//
// Usage:
//   dart run bin/vpx_test_vectors.dart [--dir <path>] [--filter <substr>] [--vp9]
//
// Defaults:
//   --dir lib/src/codecs/vpx/vp8-test-vectors
//
// Each `.ivf.md5` file contains one line per decoded frame, formatted as:
//   <md5>  <name>-WxH-NNNN.i420
// The hash covers the cropped (display-sized) I420 frame exactly as written
// by `vpx_decode.dart` (Y plane WxH, then U/V each W/2 x H/2).

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';

import 'package:pure_dart_webrtc/src/codecs/vpx/vpx_bindings.dart';
import 'package:pure_dart_webrtc/src/codecs/vpx/vpx_loader.dart';

import 'srtp_client.dart' as srtp_demo;

Future<int> main(List<String> args) async {
  String dir = 'lib/src/codecs/vpx/vp8-test-vectors';
  String? filter;
  bool includeVp9 = false;

  // --send mode forwards to the DTLS+SRTP+VP8 demo in `srtp_client.dart`.
  // Any args after `--send` are passed through verbatim.
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--send') {
      return srtp_demo.main(args.sublist(i + 1));
    }
  }

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--dir' && i + 1 < args.length) {
      dir = args[++i];
    } else if (a == '--filter' && i + 1 < args.length) {
      filter = args[++i];
    } else if (a == '--vp9') {
      includeVp9 = true;
    } else if (a == '-h' || a == '--help') {
      stdout.writeln('Usage:\n'
          '  vpx_test_vectors [--dir <path>] [--filter <substr>] [--vp9]\n'
          '  vpx_test_vectors --send [--host H] [--port P] [--ivf F] '
          '[--ssrc N] [--pt N] [--loop]');
      return 0;
    }
  }

  final root = Directory(dir);
  if (!root.existsSync()) {
    stderr.writeln('Test-vector directory not found: $dir');
    return 66;
  }

  final ivfs = root
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.ivf'))
      .where((f) => filter == null || f.path.contains(filter))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (ivfs.isEmpty) {
    stderr.writeln('No .ivf files matched.');
    return 1;
  }

  final lib = loadVpx();
  var pass = 0, fail = 0, skip = 0;
  final failures = <String>[];

  for (final ivf in ivfs) {
    final md5File = File('${ivf.path}.md5');
    if (!md5File.existsSync()) {
      skip++;
      stdout.writeln('SKIP  ${_basename(ivf.path)}  (no .ivf.md5)');
      continue;
    }
    final expected = _parseMd5File(md5File);
    final result = _runOne(lib, ivf, expected, includeVp9: includeVp9);
    switch (result.status) {
      case _Status.pass:
        pass++;
        stdout.writeln('PASS  ${_basename(ivf.path)}  '
            '(${result.frames} frames, ${result.codec})');
        break;
      case _Status.fail:
        fail++;
        failures.add('${_basename(ivf.path)}: ${result.message}');
        stdout.writeln('FAIL  ${_basename(ivf.path)}  ${result.message}');
        break;
      case _Status.skip:
        skip++;
        stdout.writeln('SKIP  ${_basename(ivf.path)}  ${result.message}');
        break;
    }
  }

  stdout.writeln('');
  stdout.writeln('Summary: $pass passed, $fail failed, $skip skipped, '
      'total ${ivfs.length}');
  if (failures.isNotEmpty) {
    stdout.writeln('Failures:');
    for (final f in failures) {
      stdout.writeln('  $f');
    }
  }
  return fail == 0 ? 0 : 1;
}

enum _Status { pass, fail, skip }

class _Result {
  final _Status status;
  final int frames;
  final String codec;
  final String message;
  _Result(this.status, this.frames, this.codec, this.message);
}

_Result _runOne(NativeLibrary lib, File ivf, List<String> expectedMd5s,
    {required bool includeVp9}) {
  final raf = ivf.openSync();
  try {
    final header = _readIvfHeader(raf);
    if (header == null) {
      return _Result(_Status.fail, 0, '', 'invalid IVF header');
    }
    final ffi.Pointer<vpx_codec_iface_t> iface;
    switch (header.codec) {
      case 'VP80':
        iface = lib.vpx_codec_vp8_dx();
        break;
      case 'VP90':
        if (!includeVp9) {
          return _Result(_Status.skip, 0, header.codec,
              'VP9 disabled (pass --vp9 to enable)');
        }
        iface = lib.vpx_codec_vp9_dx();
        break;
      default:
        return _Result(
            _Status.skip, 0, header.codec, 'unsupported codec ${header.codec}');
    }

    final ctx = calloc<vpx_codec_ctx_t>();
    final iter = calloc<vpx_codec_iter_t>();
    try {
      final r = lib.vpx_codec_dec_init_ver(
          ctx, iface, ffi.nullptr, 0, VPX_DECODER_ABI_VERSION);
      if (r != vpx_codec_err_t.VPX_CODEC_OK) {
        return _Result(_Status.fail, 0, header.codec, 'init failed: $r');
      }

      var frameIndex = 0;
      while (true) {
        final f = _readIvfFrame(raf);
        if (f == null) break;
        final buf = malloc.allocate<ffi.Uint8>(f.size);
        buf.asTypedList(f.size).setAll(0, f.data);
        final dr = lib.vpx_codec_decode(ctx, buf, f.size, ffi.nullptr, 0);
        malloc.free(buf);
        if (dr != vpx_codec_err_t.VPX_CODEC_OK) {
          return _Result(_Status.fail, frameIndex, header.codec,
              'decode error at frame $frameIndex: $dr');
        }

        iter.value = ffi.nullptr;
        ffi.Pointer<vpx_image_t> img;
        while ((img = lib.vpx_codec_get_frame(ctx, iter)) != ffi.nullptr) {
          if (frameIndex >= expectedMd5s.length) {
            return _Result(
                _Status.fail,
                frameIndex,
                header.codec,
                'more decoded frames than expected MD5s '
                '(${expectedMd5s.length})');
          }
          final got = _md5OfI420(img);
          final want = expectedMd5s[frameIndex];
          if (got != want) {
            return _Result(_Status.fail, frameIndex, header.codec,
                'MD5 mismatch at frame $frameIndex: got $got want $want');
          }
          frameIndex++;
        }
      }
      if (frameIndex != expectedMd5s.length) {
        return _Result(
            _Status.fail,
            frameIndex,
            header.codec,
            'frame count mismatch: decoded $frameIndex, '
            'expected ${expectedMd5s.length}');
      }
      return _Result(_Status.pass, frameIndex, header.codec, '');
    } finally {
      lib.vpx_codec_destroy(ctx);
      calloc.free(ctx);
      calloc.free(iter);
    }
  } finally {
    raf.closeSync();
  }
}

String _md5OfI420(ffi.Pointer<vpx_image_t> imgPtr) {
  final img = imgPtr.ref;
  // Use the decoder's reported display dimensions; the IVF header value can
  // be the encoded size, which differs from displayed size for some vectors.
  final dw = img.d_w;
  final dh = img.d_h;
  // Honour 4:2:0 chroma subsampling rounding (odd dims -> ceil).
  final cw = (dw + 1) >> 1;
  final ch = (dh + 1) >> 1;

  final y = img.planes[0].cast<ffi.Uint8>();
  final u = img.planes[1].cast<ffi.Uint8>();
  final v = img.planes[2].cast<ffi.Uint8>();
  final yStride = img.stride[0];
  final uStride = img.stride[1];
  final vStride = img.stride[2];

  final out = Uint8List(dw * dh + 2 * cw * ch);
  var off = 0;

  final yBuf = y.asTypedList(yStride * dh);
  for (var row = 0; row < dh; row++) {
    out.setRange(off, off + dw, yBuf, row * yStride);
    off += dw;
  }
  final uBuf = u.asTypedList(uStride * ch);
  for (var row = 0; row < ch; row++) {
    out.setRange(off, off + cw, uBuf, row * uStride);
    off += cw;
  }
  final vBuf = v.asTypedList(vStride * ch);
  for (var row = 0; row < ch; row++) {
    out.setRange(off, off + cw, vBuf, row * vStride);
    off += cw;
  }
  // Suppress "unused" warnings for parameters kept for API symmetry.
  return md5.convert(out).toString();
}

class _IvfHeader {
  final int width;
  final int height;
  final String codec;
  _IvfHeader(this.width, this.height, this.codec);
}

_IvfHeader? _readIvfHeader(RandomAccessFile f) {
  final data = f.readSync(32);
  if (data.length < 32) return null;
  if (String.fromCharCodes(data.sublist(0, 4)) != 'DKIF') return null;
  final hdr = ByteData.sublistView(data);
  return _IvfHeader(
    hdr.getUint16(12, Endian.little),
    hdr.getUint16(14, Endian.little),
    String.fromCharCodes(data.sublist(8, 12)),
  );
}

class _IvfFrame {
  final int size;
  final Uint8List data;
  _IvfFrame(this.size, this.data);
}

_IvfFrame? _readIvfFrame(RandomAccessFile f) {
  final hdr = f.readSync(12);
  if (hdr.length < 12) return null;
  final size = ByteData.sublistView(hdr).getUint32(0, Endian.little);
  final body = f.readSync(size);
  if (body.length < size) return null;
  return _IvfFrame(size, body);
}

List<String> _parseMd5File(File f) {
  final out = <String>[];
  for (final line in const LineSplitter().convert(f.readAsStringSync())) {
    final t = line.trim();
    if (t.isEmpty) continue;
    final ws = t.indexOf(RegExp(r'\s'));
    out.add((ws < 0 ? t : t.substring(0, ws)).toLowerCase());
  }
  return out;
}

String _basename(String p) => p.replaceAll('\\', '/').split('/').last;
