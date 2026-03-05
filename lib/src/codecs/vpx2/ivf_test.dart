import 'dart:io';
import 'dart:typed_data';

import 'dart_ivf.dart'; // your IVF library

Future<void> main() async {
  // Create IVF demuxer
  final vectorPath = 'lib/src/codecs/vpx2/vp8-test-vectors/';
  final filePath = '${vectorPath}vp80-00-comprehensive-001.ivf';

  // Read IVF file
  final bytes = await File(filePath).readAsBytes();

  // Create reader
  final ivf = IVFReader(bytes);

  // Create temp directory
  final dir = Directory('./tmp');
  if (!await dir.exists()) {
    await dir.create();
  }

  // Parse header
  print(ivf.header);

  int frameIndex = 0;

  // Dump frames
  while (ivf.hasNextFrame()) {
    final frame = ivf.nextFrame();
    frameIndex++;

    final filename = 'frame_$frameIndex.bin';
    final outputFile = File('${dir.path}/$filename');

    await outputFile.writeAsBytes(frame.data);

    print('Wrote $filename (${frame.size} bytes)');
  }

  print('Total frames dumped: $frameIndex');
}
