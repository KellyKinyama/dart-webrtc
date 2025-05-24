import 'dart:typed_data';
import 'dart:io';
import 'package:crypto/crypto.dart';

import '../../crypto.dart';

// enum NamedCurve {
//   curve1, // Example, replace with actual named curves.
//   curve2,
//   // Add other curves as needed
// }

class ExtensionSupportedEllipticCurves {
  final List<NamedCurve> ellipticCurves;

  ExtensionSupportedEllipticCurves({required this.ellipticCurves});

  int get size {
    return 2 + 2 + ellipticCurves.length * 2;
  }

  ExtensionValue extensionValue() {
    return ExtensionValue.supportedEllipticCurves;
  }

  void marshal(ByteData writer) {
    writer.setUint16(0, (2 + 2 * ellipticCurves.length) & 0xFFFF, Endian.big);
    writer.setUint16(2, (2 * ellipticCurves.length) & 0xFFFF, Endian.big);

    int offset = 4;
    for (var curve in ellipticCurves) {
      writer.setUint16(
          offset, curve.index, Endian.big); // Assuming NamedCurve has an index
      offset += 2;
    }

    writer.buffer.asUint8List();
  }

  static ExtensionSupportedEllipticCurves unmarshal(Uint8List data) {
    ByteData reader = ByteData.sublistView(data);
    reader.getUint16(0, Endian.big); // Skip the first 2 bytes

    int groupCount = reader.getUint16(2, Endian.big) ~/ 2;
    List<NamedCurve> ellipticCurves = [];

    int offset = 4;
    for (int i = 0; i < groupCount; i++) {
      var ellipticCurve =
          NamedCurve.fromInt(reader.getUint16(offset, Endian.big));
      ellipticCurves.add(ellipticCurve);
      offset += 2;
    }

    return ExtensionSupportedEllipticCurves(ellipticCurves: ellipticCurves);
  }
}

enum ExtensionValue { supportedEllipticCurves }

void main() {
  // Example usage
  // var extension = ExtensionSupportedEllipticCurves(
  //     ellipticCurves: [NamedCurve.prime256v1, NamedCurve.x25519]);

  // // Create a ByteData to simulate the writer
  // var writer = ByteData(extension.size);

  // // Marshal the object
  // extension.marshal(writer);

  // Unmarshal the object from ByteData (reader simulation)
  var unmarshalledExtension =
      ExtensionSupportedEllipticCurves.unmarshal(raw_supported_groups);

  print(
      'Unmarshalled Elliptic Curves: ${unmarshalledExtension.ellipticCurves}');
}

final raw_supported_groups =
    Uint8List.fromList([0x0, 0x4, 0x0, 0x2, 0x0, 0x1d]); // 0x0, 0xa,
