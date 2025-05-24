import 'dart:typed_data';
import 'dart:io';

const EXTENSION_USE_EXTENDED_MASTER_SECRET_HEADER_SIZE = 4;

enum ExtensionValue { useExtendedMasterSecret }

class ExtensionUseExtendedMasterSecret {
  final bool supported;

  ExtensionUseExtendedMasterSecret({required this.supported});

  int get size {
    return 2;
  }

  ExtensionValue extensionValue() {
    return ExtensionValue.useExtendedMasterSecret;
  }

  Future<void> marshal(ByteData writer) async {
    // length
    writer.setUint16(
        0, 0, Endian.big); // Setting length to 0 (as in the Rust code)
    await writer.buffer.asUint8List();
  }

  static Future<ExtensionUseExtendedMasterSecret> unmarshal(
      ByteData reader) async {
    reader.getUint16(0, Endian.big); // Skip the length byte

    return ExtensionUseExtendedMasterSecret(supported: true);
  }
}

void main() async {
  // Example usage
  var extension = ExtensionUseExtendedMasterSecret(supported: true);

  // Create a ByteData to simulate the writer
  var writer = ByteData(extension.size);

  // Marshal the object
  await extension.marshal(writer);

  // Unmarshal the object from ByteData (reader simulation)
  var unmarshalledExtension =
      await ExtensionUseExtendedMasterSecret.unmarshal(writer);

  print(
      'Unmarshalled Extension Use Extended Master Secret: ${unmarshalledExtension.supported}');
}
