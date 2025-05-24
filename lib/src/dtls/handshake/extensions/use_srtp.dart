import 'dart:typed_data';
import 'dart:io';

const EXTENSION_USE_SRTP_HEADER_SIZE = 6;

enum SrtpProtectionProfile {
  srtpAes128CmHmacSha180(0x0001),
  srtpAes128CmHmacSha132(0x0002),
  srtpAeadAes128Gcm(0x0007),
  srtpAeadAes256Gcm(0x0008),
  unsupported(0x0000);

  final int value;
  const SrtpProtectionProfile(this.value);

  factory SrtpProtectionProfile.fromValue(int value) {
    switch (value) {
      case 0x0001:
        return SrtpProtectionProfile.srtpAes128CmHmacSha180;
      case 0x0002:
        return SrtpProtectionProfile.srtpAes128CmHmacSha132;
      case 0x0007:
        return SrtpProtectionProfile.srtpAeadAes128Gcm;
      case 0x0008:
        return SrtpProtectionProfile.srtpAeadAes256Gcm;
      default:
        return SrtpProtectionProfile.unsupported;
    }
  }
}

class ExtensionUseSrtp {
  final List<SrtpProtectionProfile> protectionProfiles;

  ExtensionUseSrtp({required this.protectionProfiles});

  int get size {
    return 2 + 2 + protectionProfiles.length * 2 + 1;
  }

  ExtensionValue extensionValue() {
    return ExtensionValue.useSrtp;
  }

  void marshal(Uint8List data) {
    ByteData writer = ByteData.sublistView(data);
    // Total size including MKI Length and protection profiles
    writer.setUint16(0, 2 + 1 + 2 * protectionProfiles.length, Endian.big);
    writer.setUint16(2, 2 * protectionProfiles.length, Endian.big);

    int offset = 4;
    for (var profile in protectionProfiles) {
      writer.setUint16(offset, profile.value, Endian.big);
      offset += 2;
    }

    // MKI Length (always 0 in this case)
    writer.setUint8(offset, 0x00);
    writer.buffer.asUint8List();
  }

  static ExtensionUseSrtp unmarshal(Uint8List data) {
    ByteData reader = ByteData.sublistView(data);
    reader.getUint16(0, Endian.big); // Skip the first 2 bytes (length)

    int profileCount = reader.getUint16(2, Endian.big) ~/ 2;
    List<SrtpProtectionProfile> protectionProfiles = [];

    int offset = 4;
    for (int i = 0; i < profileCount; i++) {
      int profileValue = reader.getUint16(offset, Endian.big);
      protectionProfiles.add(SrtpProtectionProfile.fromValue(profileValue));
      offset += 2;
    }

    // MKI Length (skip it)
    reader.getUint8(offset);

    return ExtensionUseSrtp(protectionProfiles: protectionProfiles);
  }
}

enum ExtensionValue { useSrtp }

void main() async {
  // // Example usage
  // var extension = ExtensionUseSrtp(protectionProfiles: [
  //   SrtpProtectionProfile.srtpAes128CmHmacSha180,
  //   SrtpProtectionProfile.srtpAeadAes128Gcm,
  // ]);

  // // Create a ByteData to simulate the writer
  // var writer = ByteData(extension.size);

  // // Marshal the object
  //  extension.marshal(writer);

  // Unmarshal the object from ByteData (reader simulation)
  var unmarshalledExtension = ExtensionUseSrtp.unmarshal(raw_use_srtp);

  print(
      'Unmarshalled Protection Profiles: ${unmarshalledExtension.protectionProfiles}');
}

final raw_use_srtp = Uint8List.fromList(
    [0x00, 0x05, 0x00, 0x02, 0x00, 0x01, 0x00]); //0x00, 0x0e,
