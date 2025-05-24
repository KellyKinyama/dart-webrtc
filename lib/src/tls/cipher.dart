import 'dart:typed_data';

(List<int>, int) decodeCipherSuites(Uint8List data, int offset, int arrayLen) {
  final reader = ByteData.sublistView(data);

  final length = reader.getUint16(offset, Endian.big);
  final count = (length / 2).toInt();
  offset += 2;

  print("Cipher suite length: $length");

  List<int> cipherSuiteList = List.filled(count, 0);
  for (int i = 0; i < count; i++) {
    cipherSuiteList[i] = reader.getUint16(offset, Endian.big);
    offset += 2;
    // print("cipher suite: ${result[i]}");
  }

  // print("Cipher suites: $result");
  return (cipherSuiteList, offset);
}
