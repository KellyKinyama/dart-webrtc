import 'dart:io';
import 'dart:typed_data';
import 'dart_ivf.dart'; // Assuming your IVF classes are here

void main() async {
  final file = File("output3.ivf");

  if (!await file.exists()) {
    print("Error: output3.ivf not found!");
    return;
  }

  final bytes = await file.readAsBytes();
  final reader = IVFReader(bytes);

  print('--- IVF Header Metadata ---');
  print(reader.header.toString());

  print('--- Scanning Frames ---');
  int actualFrameCount = 0;
  int totalBytesParsed = 32; // Start with header size

  for (final frame in reader.frames()) {
    actualFrameCount++;
    totalBytesParsed += (12 + frame.size); // 12 bytes for frame header + data

    if (actualFrameCount % 50 == 0 || actualFrameCount == 1) {
      print(
          'Validated Frame $actualFrameCount: [Size: ${frame.size} bytes, TS: ${frame.timestamp}]');
    }
  }

  print('---------------------------');
  print('Header Frame Count: ${reader.header.frameCount}');
  print('Actual Frames Found: $actualFrameCount');
  print('File Size on Disk: ${bytes.length} bytes');
  print('Calculated Size:   $totalBytesParsed bytes');

  if (reader.header.frameCount == actualFrameCount &&
      bytes.length == totalBytesParsed) {
    print('\n✅ SUCCESS: IVF file is structurally sound.');
  } else {
    print('\n❌ WARNING: Mismatch detected in frame count or file size.');
  }
}
