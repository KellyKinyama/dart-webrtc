import "dart:typed_data";

import "../../../dtls3/extensions.dart";
import "../../../dtls3/simple_extensions.dart";

// import "package:dart_webrtc/src/dtls/handshake/extensions/simple_extensions.dart";

// import "../../../dtls3/extensions.dart";
// import "../../../dtls3/simple_extensions.dart";

// enum ExtensionTypeValue {
//   ServerName(0),
//   SupportedEllipticCurves(10),
//   SupportedPointFormats(11),
//   SupportedSignatureAlgorithms(13),
//   UseSrtp(14),
//   UseExtendedMasterSecret(23),
//   RenegotiationInfo(65281),
//   Unsupported(9999);

//   const ExtensionTypeValue(this.value);
//   final int value;

//   factory ExtensionTypeValue.fromInt(int key) {
//     return values.firstWhere((element) => element.value == key,
//         orElse: () => ExtensionTypeValue.Unsupported);
//   }
// }

// abstract class Extension {
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

// Uint8List encode();
// ExtensionTypeValue extensionType();
// }

// Go-style DecodeExtensionMap (returns a Map)
(Map<ExtensionTypeValue, Extension>, int) decodeExtensionMap(
    Uint8List data, int offset, int arrayLen) {
  var reader = ByteData.sublistView(data);
  Map<ExtensionTypeValue, Extension> result = {};

  if (offset + 2 > arrayLen) {
    // Check if there are enough bytes for extensions length
    return (result, offset); // No extensions or malformed
  }

  final extensionsLength = reader.getUint16(offset);
  offset += 2;
  final extensionsEndOffset = offset + extensionsLength;

  while (offset < extensionsEndOffset && offset + 4 <= extensionsEndOffset) {
    // Ensure enough bytes for type and length
    final extensionTypeInt = reader.getUint16(offset);
    offset += 2;
    final extensionLength = reader.getUint16(offset);
    offset += 2;

    if (offset + extensionLength > extensionsEndOffset) {
      // Malformed extension: declared length goes beyond remaining extensions data
      print(
          "Warning: Malformed extension (type: $extensionTypeInt) - length exceeds bounds. Skipping remaining extensions.");
      break; // Stop parsing to avoid out-of-bounds access
    }

    final extensionData = data.sublist(offset, offset + extensionLength);
    offset += extensionLength;

    final extensionTypeValue = ExtensionTypeValue.fromInt(extensionTypeInt);

    Extension? ext;
    switch (extensionTypeValue) {
      case ExtensionTypeValue.UseSrtp:
        ext = ExtUseSRTP.decode(extensionLength, extensionData);
        break;
      case ExtensionTypeValue.ServerName:
        // TODO: Implement ExtServerName.decode
        break;
      case ExtensionTypeValue.SupportedEllipticCurves:
        ext = ExtSupportedEllipticCurves.decode(extensionLength, extensionData);
        break;
      case ExtensionTypeValue.SupportedPointFormats:
        ext = ExtSupportedPointFormats.decode(extensionLength, extensionData);
        break;
      case ExtensionTypeValue.SupportedSignatureAlgorithms:
        // TODO: Implement ExtSupportedSignatureAlgorithms.decode
        break;
      case ExtensionTypeValue.UseExtendedMasterSecret:
        // In Go, map assignments would naturally handle duplicates by overwriting.
        // If strict duplicate check is needed, it should be done after parsing the map
        // or here with a warning/error.
        ext = ExtUseExtendedMasterSecret.decode(extensionLength, extensionData);
        break;
      case ExtensionTypeValue.RenegotiationInfo:
        ext = ExtRenegotiationInfo.decode(extensionLength, extensionData);
        break;
      case ExtensionTypeValue.Unsupported:
      default:
        ext = ExtUnknown.decode(extensionLength,
            extensionData); // Use ExtUnknown for unsupported/unknown types
        break;
    }

    if (ext != null) {
      result[extensionTypeValue] = ext;
    }
  }
  return (result, offset);
}

// Go-style EncodeExtensionMap (takes a Map)
Uint8List encodeExtensionMap(Map<ExtensionTypeValue, Extension> extensions) {
  final extensionsBuilder = BytesBuilder();
  for (var entry in extensions.entries) {
    final extensionType = entry.key.value;
    final extensionData = entry.value.encode();
    final extensionLength = extensionData.length;

    final typeBytes = ByteData(2)..setUint16(0, extensionType);
    extensionsBuilder.add(typeBytes.buffer.asUint8List());
    extensionsBuilder
        .add((ByteData(2)..setUint16(0, extensionLength)).buffer.asUint8List());
    extensionsBuilder.add(extensionData);
  }

  final extensionsBytes = extensionsBuilder.toBytes();
  final totalLengthBytes = ByteData(2)..setUint16(0, extensionsBytes.length);

  final resultBuilder = BytesBuilder();
  resultBuilder.add(totalLengthBytes.buffer.asUint8List());
  resultBuilder.add(extensionsBytes);

  return resultBuilder.toBytes();
}

// (List<Extension>, int) decodeExtensions(
//     Uint8List data, int offset, int arrayLen) {
//   ByteData reader = ByteData.sublistView(data);
//   List<Extension> result = [];
//   final length = reader.getUint16(offset);
//   offset += 2;
//   final offsetBackup = offset;

//   bool exMasterSecretFound = false;

//   while (offset < offsetBackup + length) {
//     // while (offset < arrayLen) {
//     final extensionType = reader.getUint16(offset);
//     // final extensionType = ExtensionType.fromInt(intExtensionType);
//     offset += 2;
//     final extensionLength = reader.getUint16(offset);
//     offset += 2;
//     final extensionData = data.sublist(offset, offset + extensionLength);
//     offset += extensionLength;
//     // result.add(Extension(extensionType, extensionLength, extensionData));
//     print("Extension type: ${ExtensionTypeValue.fromInt(extensionType)}");

//     switch (ExtensionTypeValue.fromInt(extensionType)) {
//       case ExtensionTypeValue.UseSrtp:
//         result.add(ExtUseSRTP.decode(extensionLength, extensionData));
//       case ExtensionTypeValue.ServerName:
//       // TODO: Handle this case.
//       // throw UnimplementedError();
//       case ExtensionTypeValue.SupportedEllipticCurves:
//         // TODO: Handle this case.
//         result.add(
//             ExtSupportedEllipticCurves.decode(extensionLength, extensionData));
//       case ExtensionTypeValue.SupportedPointFormats:
//       // TODO: Handle this case.
//       // result.add(
//       //     ExtSupportedPointFormats.decode(extensionLength, extensionData));
//       case ExtensionTypeValue.SupportedSignatureAlgorithms:
//       // TODO: Handle this case.
//       // throw UnimplementedError();
//       case ExtensionTypeValue.UseExtendedMasterSecret:
//         if (exMasterSecretFound) {
//           // throw Exception(
//           //     "Extended Master Secret extension found multiple times.");
//           continue;
//         }
//         exMasterSecretFound = true;
//         // TODO: Handle this case.
//         result.add(
//             ExtUseExtendedMasterSecret.decode(extensionLength, extensionData));
//       case ExtensionTypeValue.RenegotiationInfo:
//       // TODO: Handle this case.
//       // result.add(ExtRenegotiationInfo.decode(extensionLength, extensionData));
//       case ExtensionTypeValue.Unsupported:
//       // TODO: Handle this case.
//       // throw UnimplementedError();
//     }
//   }
//   return (result, offset);
// }

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
