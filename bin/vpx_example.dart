// Example: encode a raw RGB24 file to VP8 IVF, then decode it back to YUV,
// using the high-level wrapper API. Demonstrates `package:pure_dart_webrtc`'s
// `VpxEncoder`, `VpxDecoder`, `IvfWriter`, `IvfReader`, and `I420Frame`.
//
// Usage:
//   dart run bin/vpx_example.dart <input.rgb24> <out.ivf> <decoded.yuv> \
//       [--width 384] [--height 216] [--fps 25] [--bitrate 800] [--vp9]

import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';

import 'package:pure_dart_webrtc/src/codecs/vpx/vpx.dart';

Future<int> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('width', defaultsTo: '384')
    ..addOption('height', defaultsTo: '216')
    ..addOption('fps', defaultsTo: '25')
    ..addOption('bitrate', defaultsTo: '800', help: 'kbps')
    ..addFlag('vp9', defaultsTo: false);

  final ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    return 64;
  }
  if (parsed.rest.length != 3) {
    stderr.writeln('Usage: vpx_example <input.rgb24> <out.ivf> <decoded.yuv> '
        '[options]\n${parser.usage}');
    return 64;
  }

  final width = int.parse(parsed['width'] as String);
  final height = int.parse(parsed['height'] as String);
  final fps = int.parse(parsed['fps'] as String);
  final bitrate = int.parse(parsed['bitrate'] as String);
  final codec = (parsed['vp9'] as bool) ? VpxCodec.vp9 : VpxCodec.vp8;

  final inFile = File(parsed.rest[0]);
  final ivfFile = File(parsed.rest[1]);
  final yuvFile = File(parsed.rest[2]);

  // 1) Encode RGB24 -> IVF.
  final encoder = VpxEncoder(
    codec: codec,
    width: width,
    height: height,
    fps: fps,
    bitrateKbps: bitrate,
  );
  final ivf = IvfWriter.toFile(ivfFile,
      codec: codec, width: width, height: height, fps: fps);

  final raw = await inFile.readAsBytes();
  final frameSize = width * height * 3;
  var encoded = 0;
  for (var off = 0; off + frameSize <= raw.length; off += frameSize) {
    final rgb = Uint8List.view(raw.buffer, raw.offsetInBytes + off, frameSize);
    final frame = I420Frame.fromRgb24(rgb, width, height);
    for (final p in encoder.encode(frame, pts: encoded)) {
      ivf.writeFrame(p.data, p.pts);
    }
    encoded++;
  }
  for (final p in encoder.flush()) {
    ivf.writeFrame(p.data, p.pts);
  }
  await ivf.close();
  encoder.dispose();
  stdout.writeln('Encoded $encoded frames -> ${ivfFile.path} '
      '(${ivfFile.lengthSync()} bytes)');

  // 2) Decode IVF -> YUV.
  final reader = IvfReader.open(ivfFile);
  final decoder = VpxDecoder(codec: reader.codec);
  final yuvSink = yuvFile.openWrite();
  var decoded = 0;
  for (final pkt in reader.frames()) {
    for (final f in decoder.decode(pkt.data)) {
      yuvSink.add(f.toBytes());
      decoded++;
    }
  }
  await yuvSink.close();
  decoder.dispose();
  reader.close();
  stdout.writeln('Decoded $decoded frames -> ${yuvFile.path} '
      '(${yuvFile.lengthSync()} bytes)');

  return 0;
}
