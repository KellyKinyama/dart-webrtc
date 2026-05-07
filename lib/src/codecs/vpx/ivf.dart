// Minimal IVF reader/writer. IVF is the trivial container libvpx tools (and
// the VP8/VP9 conformance suites) use to wrap raw codec packets.
//
// File header — 32 bytes, little-endian:
//   0  'DKIF'   8 fourcc   12 width(u16)  14 height(u16)
//   16 fps(u32) 20 1(u32)  24 frame count 28 reserved
//
// Per-frame header — 12 bytes:
//   0  size(u32 LE)   4 pts(u64 LE)   followed by `size` payload bytes

import 'dart:io';
import 'dart:typed_data';

import 'vpx_codec_kind.dart';

const int _kIvfMagic = 0x46494B44; // 'DKIF' as a little-endian u32

class IvfWriter {
  final IOSink _sink;
  final VpxCodec codec;
  final int width;
  final int height;
  final int fps;

  IvfWriter._(this._sink, this.codec, this.width, this.height, this.fps);

  /// Open [file] for writing and emit the IVF file header. Always call
  /// [close] to flush the trailing bytes.
  factory IvfWriter.toFile(File file,
      {required VpxCodec codec,
      required int width,
      required int height,
      int fps = 30}) {
    final sink = file.openWrite();
    _writeFileHeader(sink, codec, width, height, fps);
    return IvfWriter._(sink, codec, width, height, fps);
  }

  /// Wrap an existing [IOSink]. The sink is not closed by [close].
  factory IvfWriter.toSink(IOSink sink,
      {required VpxCodec codec,
      required int width,
      required int height,
      int fps = 30}) {
    _writeFileHeader(sink, codec, width, height, fps);
    return IvfWriter._(sink, codec, width, height, fps);
  }

  /// Append one compressed frame.
  void writeFrame(Uint8List payload, int pts) {
    final hdr = ByteData(12);
    hdr.setUint32(0, payload.length, Endian.little);
    hdr.setUint64(4, pts, Endian.little);
    _sink.add(hdr.buffer.asUint8List());
    _sink.add(payload);
  }

  Future<void> close() => _sink.close();

  static void _writeFileHeader(
      IOSink sink, VpxCodec codec, int w, int h, int fps) {
    final fourccBytes = codec.fourcc.codeUnits;
    final h32 = ByteData(32);
    h32.setUint32(0, _kIvfMagic, Endian.little);
    h32.setUint16(4, 0, Endian.little);
    h32.setUint16(6, 32, Endian.little);
    h32.setUint8(8, fourccBytes[0]);
    h32.setUint8(9, fourccBytes[1]);
    h32.setUint8(10, fourccBytes[2]);
    h32.setUint8(11, fourccBytes[3]);
    h32.setUint16(12, w, Endian.little);
    h32.setUint16(14, h, Endian.little);
    h32.setUint32(16, fps, Endian.little);
    h32.setUint32(20, 1, Endian.little);
    h32.setUint32(24, 0, Endian.little);
    h32.setUint32(28, 0, Endian.little);
    sink.add(h32.buffer.asUint8List());
  }
}

/// One compressed frame read from an IVF container.
class IvfFrame {
  final Uint8List data;
  final int pts;
  const IvfFrame(this.data, this.pts);
}

class IvfReader {
  final RandomAccessFile _raf;
  final VpxCodec codec;
  final int width;
  final int height;
  final int fps;

  IvfReader._(this._raf, this.codec, this.width, this.height, this.fps);

  /// Open [file], parse the IVF header, and position the cursor at the first
  /// frame. Throws [FormatException] if the file is not a valid IVF.
  factory IvfReader.open(File file) {
    final raf = file.openSync();
    final hdr = raf.readSync(32);
    if (hdr.length < 32) {
      raf.closeSync();
      throw const FormatException('IVF file too short');
    }
    final bd = ByteData.sublistView(hdr);
    if (bd.getUint32(0, Endian.little) != _kIvfMagic) {
      raf.closeSync();
      throw const FormatException('Missing DKIF magic');
    }
    final fourcc = String.fromCharCodes(hdr.sublist(8, 12));
    return IvfReader._(
      raf,
      VpxCodec.fromFourcc(fourcc),
      bd.getUint16(12, Endian.little),
      bd.getUint16(14, Endian.little),
      bd.getUint32(16, Endian.little),
    );
  }

  /// Lazy iterator over compressed frames. Stops at EOF.
  Iterable<IvfFrame> frames() sync* {
    while (true) {
      final hdr = _raf.readSync(12);
      if (hdr.length < 12) return;
      final bd = ByteData.sublistView(hdr);
      final size = bd.getUint32(0, Endian.little);
      final pts = bd.getUint64(4, Endian.little);
      final body = _raf.readSync(size);
      if (body.length < size) return;
      yield IvfFrame(body, pts);
    }
  }

  void close() => _raf.closeSync();
}
