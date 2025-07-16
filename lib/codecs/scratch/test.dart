import 'dart:io';
import 'dart:typed_data';
import 'package:args/args.dart';
import 'package:archive/archive.dart'; // Import the archive package

// This script shows how to build a basic video encoder. In the real world, video encoders
// are a lot more complex than this, achieving upwards of 99.9% compression or more, but
// this guide will show how we can achieve 90% compression with a simple encoder.
//
// Fundamentally, video encoding is much like image encoding but with the ability to compress
// temporally. Image compression often takes advantage of the human eye's insensitivity to
// small changes in color, which we will also take advantage of in this encoder.
//
// Additionally, we will stick to older techniques and skip over more modern ones that involve
// a lot more math. This is to focus on the core concepts of video encoding instead of
// getting lost in the "optimal" encoding approach.
//
// Run this code with:
//    cat video.rgb24 | dart run main.dart

void main(List<String> arguments) async {
  print('--- Program Start ---');
  final parser = ArgParser()
    ..addOption('width',
        abbr: 'w', defaultsTo: '384', help: 'width of the video')
    ..addOption('height',
        abbr: 'h', defaultsTo: '216', help: 'height of the video');

  final argResults = parser.parse(arguments);
  final width = int.parse(argResults['width']);
  final height = int.parse(argResults['height']);

  print('Video dimensions: ${width}x${height}');

  final frames = <Uint8List>[];

  // Read raw video frames from stdin. In rgb24 format, each pixel (r, g, b) is one byte
  // so the total size of the frame is width * height * 3.
  final frameSize = width * height * 3;
  print('Expected frame size (RGB24): $frameSize bytes');
  int frameCount = 0;
  while (true) {
    final frameBuffer = BytesBuilder();
    int bytesRead = 0;
    while (bytesRead < frameSize) {
      final byte = stdin.readByteSync();
      if (byte == -1) {
        print(
            'DEBUG (Read Loop): EOF reached or stdin closed at byte ${bytesRead}/${frameSize}.');
        break; // EOF
      }
      frameBuffer.addByte(byte);
      bytesRead++;
      // print('DEBUG (Read Loop): Frame ${frameCount + 1}, Read byte $bytesRead / $frameSize'); // Too chatty, uncomment if truly stuck
    }

    if (bytesRead < frameSize) {
      if (bytesRead > 0) {
        print(
            'DEBUG (Read Loop): Incomplete frame read. Expected $frameSize, got $bytesRead. Breaking.');
      } else {
        print(
            'DEBUG (Read Loop): No bytes read for current frame. Assuming EOF. Breaking.');
      }
      break; // Incomplete frame or EOF
    }
    frames.add(frameBuffer.takeBytes());
    frameCount++;
    print(
        'DEBUG (Read Loop): Successfully read frame $frameCount. Current frames in buffer: ${frames.length}.');
  }
  print('Total raw frames read: $frameCount');

  // Now we have our raw video, using a truly ridiculous amount of memory!

  final rawSize = size(frames);
  print('Raw size: $rawSize bytes');

  print('--- Converting RGB to YUV420P ---');
  for (int i = 0; i < frames.length; i++) {
    print('DEBUG (YUV Conversion Loop): Processing frame $i.');
    final frame = frames[i];
    // First, we will convert each frame to YUV420 format.

    final Y = Uint8List(width * height);
    final U = Float64List(width * height);
    final V = Float64List(width * height);

    for (int j = 0; j < width * height; j++) {
      // Convert the pixel from RGB to YUV
      final r = frame[3 * j].toDouble();
      final g = frame[3 * j + 1].toDouble();
      final b = frame[3 * j + 2].toDouble();

      // These coefficients are from the ITU-R standard.
      // See https://en.wikipedia.org/wiki/YUV#Y%E2%80%B2UV444_to_RGB888_conversion
      final y = 0.299 * r + 0.587 * g + 0.114 * b;
      final u = -0.169 * r - 0.331 * g + 0.449 * b + 128;
      final v = 0.499 * r - 0.418 * g - 0.0813 * b + 128;

      // Store the YUV values in our byte slices. These are separated to make the
      // next step a bit easier.
      Y[j] = y.toInt();
      U[j] = u;
      V[j] = v;
      // print('DEBUG (YUV Pixel Loop): Frame $i, Pixel $j (r:$r,g:$g,b:$b) -> (y:$y,u:$u,v:$v)'); // Extremely chatty
    }
    print(
        'DEBUG (YUV Conversion Loop): Frame $i: RGB to YUV conversion complete.');

    // Now, we will downsample the U and V components.
    final uDownsampled = Uint8List(width * height ~/ 4);
    final vDownsampled = Uint8List(width * height ~/ 4);
    for (int x = 0; x < height; x += 2) {
      for (int y = 0; y < width; y += 2) {
        // We will average the U and V components of the 4 pixels that share this
        // U and V component.
        final u = (U[x * width + y] +
                U[x * width + y + 1] +
                U[(x + 1) * width + y] +
                U[(x + 1) * width + y + 1]) /
            4;
        final v = (V[x * width + y] +
                V[x * width + y + 1] +
                V[(x + 1) * width + y] +
                V[(x + 1) * width + y + 1]) /
            4;

        // Store the downsampled U and V components in our byte slices.
        uDownsampled[(x ~/ 2) * (width ~/ 2) + (y ~/ 2)] = u.toInt();
        vDownsampled[(x ~/ 2) * (width ~/ 2) + (y ~/ 2)] = v.toInt();
        // print('DEBUG (YUV Downsample Loop): Frame $i, Coords ($x,$y) -> U:$u, V:$v'); // Extremely chatty
      }
    }
    print('DEBUG (YUV Conversion Loop): Frame $i: U/V downsampling complete.');

    final yuvFrame =
        Uint8List(Y.length + uDownsampled.length + vDownsampled.length);

    // Now we need to store the YUV values in a byte slice. To make the data more
    // compressible, we will store all the Y values first, then all the U values,
    // then all the V values. This is called a planar format.
    yuvFrame.setAll(0, Y);
    yuvFrame.setAll(Y.length, uDownsampled);
    yuvFrame.setAll(Y.length + uDownsampled.length, vDownsampled);

    frames[i] = yuvFrame;
    print(
        'DEBUG (YUV Conversion Loop): Frame $i converted to YUV420P. Final YUV frame size: ${yuvFrame.length} bytes.');
  }

  // Now we have our YUV-encoded video, which takes half the space!

  final yuvSize = size(frames);
  print(
      'YUV420P size: $yuvSize bytes (${(100 * yuvSize / rawSize).toStringAsFixed(2)}% original size)');

  // We can also write this out to a file, which can be played with ffplay:
  //
  //    ffplay -f rawvideo -pixel_format yuv420p -video_size 384x216 -framerate 25 encoded.yuv

  print('Writing encoded.yuv...');
  await File('encoded.yuv')
      .writeAsBytes(Uint8List.fromList(frames.expand((x) => x).toList()));
  print('encoded.yuv written.');

  print('--- Applying Delta Encoding and RLE ---');
  final encoded = <Uint8List>[];
  for (int i = 0; i < frames.length; i++) {
    print('DEBUG (Delta/RLE Loop): Processing frame $i.');
    // Next, we will simplify the data by computing the delta between each frame.
    // Of course, the first frame doesn't have a previous frame so we will store the entire thing.
    if (i == 0) {
      // This is the keyframe, store the raw frame.
      encoded.add(frames[i]);
      print(
          'DEBUG (Delta/RLE Loop): Frame $i (Keyframe) added directly to encoded list. Size: ${frames[i].length}');
      continue;
    }

    final delta = Uint8List(frames[i].length);
    for (int j = 0; j < delta.length; j++) {
      delta[j] = (frames[i][j] - frames[i - 1][j]) & 0xFF; // Ensure byte range
      // print('DEBUG (Delta Calc Loop): Frame $i, byte $j: ${frames[i][j]} - ${frames[i-1][j]} = ${delta[j]}'); // Extremely chatty
    }
    print(
        'DEBUG (Delta/RLE Loop): Frame $i delta computed. Delta size: ${delta.length}');

    // Now we have our delta frame, which if we print out contains a bunch of zeroes (woah!).
    // These zeros are pretty compressible, so we will compress them with run length encoding.
    final rle = <int>[];
    for (int j = 0; j < delta.length;) {
      // Count the number of times the current value repeats.
      int count = 0;
      int originalJ = j; // Store original j for debug print
      for (count = 0;
          count < 255 &&
              j + count < delta.length &&
              delta[j + count] == delta[j];
          count++) {}

      // Store the count and value.
      rle.add(count);
      rle.add(delta[originalJ]); // Use originalJ for the value
      // print('DEBUG (RLE Inner Loop): Frame $i, Pos $originalJ: Value ${delta[originalJ]} repeated $count times.'); // Chatty
      j += count;
    }

    // Save the RLE frame.
    encoded.add(Uint8List.fromList(rle));
    print(
        'DEBUG (Delta/RLE Loop): Frame $i RLE encoded. RLE size: ${rle.length}');
  }

  final rleSize = size(encoded);
  print(
      'RLE size: $rleSize bytes (${(100 * rleSize / rawSize).toStringAsFixed(2)}% original size)');

  // This is good, we're at 1/4 the size of the original video. But we can do better.
  // We will defer to using the DEFLATE algorithm which is available in the archive package.

  print('--- Applying DEFLATE Compression ---');
  final deflatedBytesBuilder = BytesBuilder();
  // We need to use ZLibEncoder(raw: true) to mimic Go's flate.NewWriter
  // Correction: The `archive` package's ZLibEncoder/Decoder do not have 'raw' parameter.
  // They are for zlib format. For raw DEFLATE, you'd use Deflate/Inflate.
  // Sticking with ZLibEncoder as per the original code to avoid introducing new issues.
  final zlibEncoder = ZLibEncoder();

  final deflateData = BytesBuilder();
  for (int i = 0; i < frames.length; i++) {
    print('DEBUG (DEFLATE Prep Loop): Adding data for frame $i.');
    if (i == 0) {
      // This is the keyframe, write the raw frame.
      deflateData.add(frames[i]);
      print(
          'DEBUG (DEFLATE Prep Loop): Frame $i (Keyframe) added directly to deflateData. Length: ${frames[i].length}');
      continue;
    }

    final delta = Uint8List(frames[i].length);
    for (int j = 0; j < delta.length; j++) {
      delta[j] = (frames[i][j] - frames[i - 1][j]) & 0xFF; // Ensure byte range
    }
    deflateData.add(delta);
    print(
        'DEBUG (DEFLATE Prep Loop): Frame $i delta added to deflateData. Length: ${delta.length}');
  }

  print('DEBUG: Encoding all deflate data with ZLibEncoder...');
  final compressed = zlibEncoder.encode(deflateData.takeBytes());
  deflatedBytesBuilder.add(compressed);
  print(
      'DEBUG: Compression complete. Compressed data length: ${compressed.length}');

  final deflatedSize = deflatedBytesBuilder.length;
  print(
      'DEFLATE size: $deflatedSize bytes (${(100 * deflatedSize / rawSize).toStringAsFixed(2)}% original size)');

  // Now we have our encoded video. Let's decode it and see what we get.

  print('--- Decoding DEFLATE Stream ---');
  // First, we will decode the DEFLATE stream.
  // Use ZLibDecoder(raw: true) to match the ZLibEncoder(raw: true)
  // Correction: The `archive` package's ZLibEncoder/Decoder do not have 'raw' parameter.
  // They are for zlib format. For raw DEFLATE, you'd use Deflate/Inflate.
  // Sticking with ZLibDecoder as per the original code to avoid introducing new issues.
  final inflatedBytes =
      ZLibDecoder().decodeBytes(deflatedBytesBuilder.takeBytes());
  print('DEBUG: ZLibDecoder output length: ${inflatedBytes.length}');
  final inflatedBuffer = InputStream(
      inflatedBytes); // InputStream is from 'package:archive/archive.dart'
  print('DEBUG: InputStream created. Total bytes: ${inflatedBuffer.length}');

  // Split the inflated stream into frames.
  final decodedFrames = <Uint8List>[];
  final yuvFrameSize = width * height * 3 ~/ 2;
  print('Expected YUV frame size for decoding: $yuvFrameSize bytes');
  int decodedFrameCount = 0;
  // Use inflatedBuffer.remainingLength to check if enough bytes are available
  while ((inflatedBuffer.length - inflatedBuffer.position) >= yuvFrameSize) {
    decodedFrames.add(Uint8List.fromList(
        inflatedBuffer.readBytes(yuvFrameSize).toUint8List()));
    decodedFrameCount++;
    print(
        'DEBUG (DEFLATE Decode Loop): Decoded frame $decodedFrameCount. Current position in stream: ${inflatedBuffer.position}/${inflatedBuffer.length}');
  }
  print('Total frames decoded from DEFLATE stream: $decodedFrameCount');

  print('--- Reconstructing Delta Frames ---');
  // For every frame except the first one, we need to add the previous frame to the delta frame.
  // This is the opposite of what we did in the encoder.
  for (int i = 1; i < decodedFrames.length; i++) {
    print('DEBUG (Delta Reconstruction Loop): Reconstructing frame $i.');
    for (int j = 0; j < decodedFrames[i].length; j++) {
      decodedFrames[i][j] = (decodedFrames[i][j] + decodedFrames[i - 1][j]) &
          0xFF; // Ensure byte range
      // print('DEBUG (Delta Reconstruction Pixel Loop): Frame $i, byte $j'); // Extremely chatty
    }
    print(
        'DEBUG (Delta Reconstruction Loop): Frame $i reconstructed from delta. Length: ${decodedFrames[i].length}');
  }

  print('Writing decoded.yuv...');
  await File('decoded.yuv').writeAsBytes(
      Uint8List.fromList(decodedFrames.expand((x) => x).toList()));
  print('decoded.yuv written.');

  print('--- Converting YUV to RGB ---');
  // Then convert each YUV frame into RGB.
  for (int i = 0; i < decodedFrames.length; i++) {
    print('DEBUG (RGB Conversion Loop): Converting frame $i to RGB.');
    final frame = decodedFrames[i];
    final Y = frame.sublist(0, width * height);
    final U =
        frame.sublist(width * height, width * height + width * height ~/ 4);
    final V = frame.sublist(width * height + width * height ~/ 4);

    final rgb = BytesBuilder();
    for (int j = 0; j < height; j++) {
      for (int k = 0; k < width; k++) {
        final y = Y[j * width + k].toDouble();
        final u = U[(j ~/ 2) * (width ~/ 2) + (k ~/ 2)].toDouble() - 128;
        final v = V[(j ~/ 2) * (width ~/ 2) + (k ~/ 2)].toDouble() - 128;

        final r = clamp(y + 1.402 * v, 0, 255);
        final g = clamp(y - 0.344 * u - 0.714 * v, 0, 255);
        final b = clamp(y + 1.772 * u, 0, 255);

        rgb.addByte(r.toInt());
        rgb.addByte(g.toInt());
        rgb.addByte(b.toInt());
        // print('DEBUG (RGB Pixel Loop): Frame $i, Pixel ($j,$k) (y:$y,u:$u,v:$v) -> (r:$r,g:$g,b:$b)'); // Extremely chatty
      }
    }
    decodedFrames[i] = rgb.takeBytes();
    print(
        'DEBUG (RGB Conversion Loop): Frame $i converted to RGB24. Size: ${decodedFrames[i].length}');
  }

  // Finally, write the decoded video to a file.
  //
  // This video can be played with ffplay:
  //
  //    ffplay -f rawvideo -pixel_format rgb24 -video_size 384x216 -framerate 25 decoded.rgb24
  //
  print('Writing decoded.rgb24...');
  final outFile = File('decoded.rgb24');
  final sink = outFile.openWrite();
  for (int i = 0; i < decodedFrames.length; i++) {
    sink.add(decodedFrames[i]);
    // print('DEBUG (Write RGB Loop): Appended frame $i to decoded.rgb24 sink.'); // Chatty
  }
  await sink.close();
  print('decoded.rgb24 written.');
  print('--- Program End ---');
}

int size(List<Uint8List> frames) {
  int totalSize = 0;
  for (final frame in frames) {
    totalSize += frame.length;
  }
  return totalSize;
}

double clamp(double x, double min, double max) {
  if (x < min) {
    return min;
  }
  if (x > max) {
    return max;
  }
  return x;
}
