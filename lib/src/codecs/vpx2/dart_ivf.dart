import 'dart:io';
import 'dart:typed_data';

class IVFHeader {
  final String signature;
  final int version;
  final int headerSize;
  final String codec;
  final int width;
  final int height;
  final int timebaseDen;
  final int timebaseNum;
  final int frameCount;

  IVFHeader({
    required this.signature,
    required this.version,
    required this.headerSize,
    required this.codec,
    required this.width,
    required this.height,
    required this.timebaseDen,
    required this.timebaseNum,
    required this.frameCount,
  });

  static IVFHeader decode(Uint8List data) {
    final bd = ByteData.sublistView(data);

    final signature = String.fromCharCodes(data.sublist(0, 4));
    if (signature != "DKIF") {
      throw FormatException("Invalid IVF file");
    }

    final version = bd.getUint16(4, Endian.little);
    final headerSize = bd.getUint16(6, Endian.little);

    final codec = String.fromCharCodes(data.sublist(8, 12));

    final width = bd.getUint16(12, Endian.little);
    final height = bd.getUint16(14, Endian.little);

    final timebaseDen = bd.getUint32(16, Endian.little);
    final timebaseNum = bd.getUint32(20, Endian.little);

    final frameCount = bd.getUint32(24, Endian.little);

    return IVFHeader(
      signature: signature,
      version: version,
      headerSize: headerSize,
      codec: codec,
      width: width,
      height: height,
      timebaseDen: timebaseDen,
      timebaseNum: timebaseNum,
      frameCount: frameCount,
    );
  }

  @override
  String toString() {
    return '''
Signature: $signature
Codec: $codec
Resolution: ${width}x$height
Frames: $frameCount
Timebase: $timebaseDen/$timebaseNum
''';
  }
}

class IVFFrame {
  final int size;
  final int timestamp;
  final Uint8List data;

  IVFFrame({
    required this.size,
    required this.timestamp,
    required this.data,
  });
}

class IVFReader {
  final Uint8List bytes;
  late IVFHeader header;

  int offset = 32;

  IVFReader(this.bytes) {
    header = IVFHeader.decode(bytes.sublist(0, 32));
  }

  bool hasNextFrame() {
    return offset < bytes.length;
  }

  IVFFrame nextFrame() {
    final headerBytes = bytes.sublist(offset, offset + 12);
    final bd = ByteData.sublistView(headerBytes);

    final frameSize = bd.getUint32(0, Endian.little);
    final timestamp = bd.getUint64(4, Endian.little);

    offset += 12;

    final frameData = bytes.sublist(offset, offset + frameSize);

    offset += frameSize;

    return IVFFrame(
      size: frameSize,
      timestamp: timestamp,
      data: frameData,
    );
  }

  Iterable<IVFFrame> frames() sync* {
    while (hasNextFrame()) {
      yield nextFrame();
    }
  }
}

class IVFWriter {
  final List<Uint8List> _frames = [];
  final List<int> _timestamps = [];

  final int width;
  final int height;
  final String codec;
  final int fps;

  IVFWriter({
    required this.width,
    required this.height,
    this.fps = 30, // Default
    this.codec = "VP80",
  });

  void addFrame(Uint8List frame, int timestamp) {
    _frames.add(frame);
    _timestamps.add(timestamp);
  }

  Uint8List build() {
    final header = Uint8List(32);
    final bd = ByteData.sublistView(header);

    header.setAll(0, "DKIF".codeUnits);

    bd.setUint16(4, 0, Endian.little);
    bd.setUint16(6, 32, Endian.little);

    header.setAll(8, codec.codeUnits);

    bd.setUint16(12, width, Endian.little);
    bd.setUint16(14, height, Endian.little);

    bd.setUint32(16, fps, Endian.little);
    bd.setUint32(20, 1, Endian.little);

    bd.setUint32(24, _frames.length, Endian.little);

    final output = BytesBuilder();
    output.add(header);

    for (int i = 0; i < _frames.length; i++) {
      final frame = _frames[i];
      final timestamp = _timestamps[i];

      final frameHeader = Uint8List(12);
      final fbd = ByteData.sublistView(frameHeader);

      fbd.setUint32(0, frame.length, Endian.little);
      fbd.setUint64(4, timestamp, Endian.little);

      output.add(frameHeader);
      output.add(frame);
    }

    return output.toBytes();
  }
}

void main() async {
  final file = File("output.ivf");
  final bytes = await file.readAsBytes();

  final reader = IVFReader(bytes);

  print(reader.header);

  int count = 0;

  for (final frame in reader.frames()) {
    count++;
    print("Frame $count size: ${frame.size}");
  }

  print("Total decoded frames: $count");
}
