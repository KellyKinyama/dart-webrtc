import 'dart:typed_data';
import 'dart:io';

const EXTENSION_SUPPORTED_POINT_FORMATS_SIZE = 5;

typedef EllipticCurvePointFormat = int;

const int ELLIPTIC_CURVE_POINT_FORMAT_UNCOMPRESSED = 0;

enum ExtensionValue { supportedPointFormats }

class ExtensionSupportedPointFormats {
  final List<EllipticCurvePointFormat> pointFormats;

  ExtensionSupportedPointFormats({required this.pointFormats});

  int get size {
    return 2 + 1 + pointFormats.length;
  }

  ExtensionValue extensionValue() {
    return ExtensionValue.supportedPointFormats;
  }

  void marshal(ByteData writer) {
    writer.setUint16(0, (1 + pointFormats.length) & 0xFFFF, Endian.big);
    writer.setUint8(2, pointFormats.length);

    int offset = 3;
    for (var format in pointFormats) {
      writer.setUint8(offset, format);
      offset += 1;
    }

    writer.buffer.asUint8List();
  }

  static ExtensionSupportedPointFormats unmarshal(ByteData reader) {
    reader.getUint16(0, Endian.big); // Skip the first 2 bytes

    int pointFormatCount = reader.getUint8(2);
    List<EllipticCurvePointFormat> pointFormats = [];

    int offset = 3;
    for (int i = 0; i < pointFormatCount; i++) {
      var pointFormat = reader.getUint8(offset);
      pointFormats.add(pointFormat);
      offset += 1;
    }

    return ExtensionSupportedPointFormats(pointFormats: pointFormats);
  }
}

void main() {
  // Example usage
  var extension = ExtensionSupportedPointFormats(
      pointFormats: [ELLIPTIC_CURVE_POINT_FORMAT_UNCOMPRESSED]);

  // Create a ByteData to simulate the writer
  var writer = ByteData(extension.size);

  // Marshal the object
  extension.marshal(writer);

  // Unmarshal the object from ByteData (reader simulation)
  var unmarshalledExtension = ExtensionSupportedPointFormats.unmarshal(writer);

  print('Unmarshalled Point Formats: ${unmarshalledExtension.pointFormats}');
}
