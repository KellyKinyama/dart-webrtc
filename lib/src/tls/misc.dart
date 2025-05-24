import 'dart:typed_data';

(List<int>, int) decodeCompressionMethodIDs(
    Uint8List buf, int offset, int arrayLen) {
  final count = buf[offset];
  offset += 1;
  List<int> result = List.filled(count, 0);
  for (int i = 0; i < count; i++) {
    result[i] = ByteData.sublistView(buf, offset, offset + 2).getUint8(0);
    offset += 1;
  }

  return (result, offset);
}
