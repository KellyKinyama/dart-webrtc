import "dart:typed_data";

class Extension {
  int extensionType;
  int extensionLength;
  Uint8List extensionData;

  Extension(this.extensionType, this.extensionLength, this.extensionData);

  @override
  String toString() {
    // TODO: implement toString
    return """Extension (extensionType: $extensionType,
        extensionLength: $extensionLength,
        extensionData: $extensionData, 
        """;
  }
}

(List<Extension>, int) decodeExtensions(
    Uint8List data, int offset, int arrayLen) {
  ByteData reader = ByteData.sublistView(data);
  List<Extension> result = [];
  final length = reader.getUint16(offset);
  offset += 2;
  final offsetBackup = offset;

  while (offset < offsetBackup + length) {
    final extensionType = reader.getUint16(offset);
    // final extensionType = ExtensionType.fromInt(intExtensionType);
    offset += 2;
    final extensionLength = reader.getUint16(offset);
    offset += 2;
    final extensionData = data.sublist(offset, offset + extensionLength);
    offset += extensionData.length;
    result.add(Extension(extensionType, extensionLength, extensionData));
  }
  return (result, offset);
}

Uint8List encodeExtensions(List<Extension> extensions) {
  final extensionBuilder = BytesBuilder();
  final length = Uint8List(2);

  for (var extension in extensions) {
    final extensionType = Uint8List(2);

    final extensionLength = Uint8List(2);
    ByteData.sublistView(extensionType).setUint16(0, extension.extensionType);
    ByteData.sublistView(extensionLength)
        .setUint16(0, extension.extensionLength);
    extensionBuilder.add(
        [...extensionType, ...extensionLength, ...extension.extensionData]);
  }

  final extensionsBytes = extensionBuilder.toBytes();

  ByteData.sublistView(length).setUint16(0, extensionsBytes.length);

  return Uint8List.fromList([...length, ...extensionsBytes]);
}
