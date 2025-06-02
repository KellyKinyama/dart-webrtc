import "dart:typed_data";

import "package:dart_webrtc/src/dtls/handshake/extensions/simple_extensions.dart";

enum ExtensionTypeValue {
  ServerName(0),
  SupportedEllipticCurves(10),
  SupportedPointFormats(11),
  SupportedSignatureAlgorithms(13),
  UseSrtp(14),
  UseExtendedMasterSecret(23),
  RenegotiationInfo(65281),
  Unsupported(9999);

  const ExtensionTypeValue(this.value);
  final int value;

  factory ExtensionTypeValue.fromInt(int key) {
    return values.firstWhere((element) => element.value == key,
        orElse: () => ExtensionTypeValue.Unsupported);
  }
}

abstract class Extension {
  // int extensionType;
  // int extensionLength;
  // Uint8List extensionData;
  // ExtensionTypeValue extensionTypeValue = ExtensionTypeValue.Unsupported;

  // Extension(this.extensionType, this.extensionLength, this.extensionData) {
  //   extensionTypeValue = ExtensionTypeValue.fromInt(extensionType);
  // }

  // @override
  // String toString() {
  //   // TODO: implement toString
  //   return """Extension (extensionType: $extensionType,
  //       extensionTypeValue: $extensionTypeValue,
  //       extensionLength: $extensionLength,
  //       extensionData: $extensionData,
  //       """;
  // }

  Uint8List encode();
  ExtensionTypeValue extensionType();
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
    // result.add(Extension(extensionType, extensionLength, extensionData));

    switch (ExtensionTypeValue.fromInt(extensionType)) {
      case ExtensionTypeValue.UseSrtp:
        result.add(ExtUseSRTP.decode(extensionLength, extensionData));
      case ExtensionTypeValue.ServerName:
      // TODO: Handle this case.
      // throw UnimplementedError();
      case ExtensionTypeValue.SupportedEllipticCurves:
      // TODO: Handle this case.
      // result.add(ExtSupportedEllipticCurves.decode(
      //     extensionLength, extensionData));
      case ExtensionTypeValue.SupportedPointFormats:
      // TODO: Handle this case.
      // result.add(
      //     ExtSupportedPointFormats.decode(extensionLength, extensionData));
      case ExtensionTypeValue.SupportedSignatureAlgorithms:
      // TODO: Handle this case.
      // throw UnimplementedError();
      case ExtensionTypeValue.UseExtendedMasterSecret:
        // TODO: Handle this case.
        result.add(
            ExtUseExtendedMasterSecret.decode(extensionLength, extensionData));
      case ExtensionTypeValue.RenegotiationInfo:
      // TODO: Handle this case.
      // result.add(ExtRenegotiationInfo.decode(extensionLength, extensionData));
      case ExtensionTypeValue.Unsupported:
      // TODO: Handle this case.
      // throw UnimplementedError();
    }
  }
  return (result, offset);
}

// Uint8List encodeExtensions(List<Extension> extensions) {
//   final extensionBuilder = BytesBuilder();
//   final length = Uint8List(2);

//   for (var extension in extensions) {
//     final extensionType = Uint8List(2);

//     final extensionLength = Uint8List(2);
//     ByteData.sublistView(extensionType).setUint16(0, extension.extensionType);
//     ByteData.sublistView(extensionLength)
//         .setUint16(0, extension.extensionLength);
//     extensionBuilder.add(
//         [...extensionType, ...extensionLength, ...extension.extensionData]);
//   }

//   final extensionsBytes = extensionBuilder.toBytes();

//   ByteData.sublistView(length).setUint16(0, extensionsBytes.length);

//   return Uint8List.fromList([...length, ...extensionsBytes]);
// }
