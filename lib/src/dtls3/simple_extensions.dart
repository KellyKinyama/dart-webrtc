// simple_extensions.dart (Converted from simpleextensions.go)

import 'dart:typed_data';
import 'extensions.dart'; // For Extension and ExtensionTypeValue

// Define enums based on Go types
enum SRTPProtectionProfile {
  SRTPProtectionProfile_AEAD_AES_128_GCM(0x0007),
  UnSupported(9999);

  const SRTPProtectionProfile(this.value);
  final int value;

  factory SRTPProtectionProfile.fromInt(int key) {
    return values.firstWhere((element) => element.value == key,
        orElse: () => SRTPProtectionProfile.UnSupported);
  }

  @override
  String toString() {
    switch (this) {
      case SRTPProtectionProfile_AEAD_AES_128_GCM:
        return "SRTPProtectionProfile_AEAD_AES_128_GCM";
      default:
        return "Unsupported";
    }
  }
}

enum PointFormat {
  Uncompressed(0x00);

  const PointFormat(this.value);
  final int value;

  factory PointFormat.fromInt(int key) {
    return values.firstWhere((element) => element.value == key,
        orElse: () => PointFormat.Uncompressed);
  }

  @override
  String toString() {
    switch (this) {
      case Uncompressed:
        return "Uncompressed";
      default:
        return "Unsupported";
    }
  }
}

enum Curve {
  X25519(0x001D),
  Unsupported(9999);

  const Curve(this.value);
  final int value;

  factory Curve.fromInt(int key) {
    return values.firstWhere((element) => element.value == key,
        orElse: () => Curve.Unsupported);
  }

  @override
  String toString() {
    switch (this) {
      case X25519:
        return "X25519";
      default:
        return "Unsupported";
    }
  }
}

// ExtUseExtendedMasterSecret
class ExtUseExtendedMasterSecret extends Extension {
  @override
  String toString() {
    return "[UseExtendedMasterSecret]";
  }

  @override
  ExtensionTypeValue extensionType() {
    return ExtensionTypeValue.UseExtendedMasterSecret;
  }

  @override
  Uint8List encode() {
    return Uint8List(0); // Empty byte array
  }

  static ExtUseExtendedMasterSecret decode(int extensionLength, Uint8List buf) {
    return ExtUseExtendedMasterSecret();
  }
}

// ExtRenegotiationInfo
class ExtRenegotiationInfo extends Extension {
  @override
  String toString() {
    return "[RenegotiationInfo]";
  }

  @override
  ExtensionTypeValue extensionType() {
    return ExtensionTypeValue.RenegotiationInfo;
  }

  @override
  Uint8List encode() {
    return Uint8List.fromList(
        [0]); // Go version encodes a single byte '0' for length
  }

  static ExtRenegotiationInfo decode(int extensionLength, Uint8List buf) {
    return ExtRenegotiationInfo();
  }
}

// ExtUseSRTP
class ExtUseSRTP extends Extension {
  List<SRTPProtectionProfile> protectionProfiles;
  Uint8List mki;

  ExtUseSRTP({required this.protectionProfiles, required this.mki});

  @override
  String toString() {
    final protectionProfilesStr = protectionProfiles
        .map((p) => p.toString())
        .join('\n')
        .split('\n')
        .map((line) => '    $line')
        .join('\n');
    return "[UseSRTP]\n" + "  Protection Profiles:\n" + protectionProfilesStr;
  }

  @override
  ExtensionTypeValue extensionType() {
    return ExtensionTypeValue.UseSrtp;
  }

  @override
  Uint8List encode() {
    final builder = BytesBuilder();
    final lengthBytes = (ByteData(2)
          ..setUint16(0, protectionProfiles.length * 2))
        .buffer
        .asUint8List();
    builder.add(lengthBytes);
    for (var p in protectionProfiles) {
      builder.add((ByteData(2)..setUint16(0, p.value)).buffer.asUint8List());
    }
    builder.addByte(mki.length);
    builder.add(mki);
    return builder.toBytes();
  }

  static ExtUseSRTP decode(int extensionLength, Uint8List buf) {
    var reader = ByteData.sublistView(buf);
    int offset = 0;

    final protectionProfilesLength = reader.getUint16(offset);
    offset += 2;
    final protectionProfilesCount = protectionProfilesLength ~/ 2;
    List<SRTPProtectionProfile> protectionProfiles = [];
    for (int i = 0; i < protectionProfilesCount; i++) {
      final protectionProfile =
          SRTPProtectionProfile.fromInt(reader.getUint16(offset));

      if (protectionProfile != SRTPProtectionProfile.UnSupported) {
        protectionProfiles.add(protectionProfile);
      }
      offset += 2;
    }

    final mkiLength = reader.getUint8(offset);
    offset++;
    final mki = buf.sublist(offset, offset + mkiLength);

    return ExtUseSRTP(protectionProfiles: protectionProfiles, mki: mki);
  }
}

// ExtSupportedPointFormats
class ExtSupportedPointFormats extends Extension {
  List<PointFormat> pointFormats;

  ExtSupportedPointFormats({required this.pointFormats});

  @override
  String toString() {
    return "[SupportedPointFormats] Point Formats: ${pointFormats.map((pf) => pf.toString()).join(', ')}";
  }

  @override
  ExtensionTypeValue extensionType() {
    return ExtensionTypeValue.SupportedPointFormats;
  }

  @override
  Uint8List encode() {
    final builder = BytesBuilder();
    builder.addByte(pointFormats.length);
    for (var pf in pointFormats) {
      builder.addByte(pf.value);
    }
    return builder.toBytes();
  }

  static ExtSupportedPointFormats decode(int extensionLength, Uint8List buf) {
    var reader = ByteData.sublistView(buf);
    int offset = 0;

    final pointFormatsCount = reader.getUint8(offset);
    offset++;
    List<PointFormat> pointFormats = [];
    for (int i = 0; i < pointFormatsCount; i++) {
      pointFormats.add(PointFormat.fromInt(reader.getUint8(offset)));
      offset++;
    }
    return ExtSupportedPointFormats(pointFormats: pointFormats);
  }
}

// ExtSupportedEllipticCurves
class ExtSupportedEllipticCurves extends Extension {
  List<Curve> curves;

  ExtSupportedEllipticCurves({required this.curves});

  @override
  String toString() {
    final curvesStr = curves
        .map((c) => c.toString())
        .join('\n')
        .split('\n')
        .map((line) => '    $line')
        .join('\n');
    return "[SupportedEllipticCurves]\n" + "  Curves:\n" + curvesStr;
  }

  @override
  ExtensionTypeValue extensionType() {
    return ExtensionTypeValue.SupportedEllipticCurves;
  }

  @override
  Uint8List encode() {
    final builder = BytesBuilder();
    builder.add(
        (ByteData(2)..setUint16(0, curves.length * 2)).buffer.asUint8List());
    for (var c in curves) {
      final curveBytes =
          (ByteData(2)..setUint16(0, c.value)).buffer.asUint8List();
      builder.add(curveBytes);
    }
    return builder.toBytes();
  }

  static ExtSupportedEllipticCurves decode(int extensionLength, Uint8List buf) {
    var reader = ByteData.sublistView(buf);
    int offset = 0;

    final curvesLength = reader.getUint16(offset);
    offset += 2;
    final curvesCount = curvesLength ~/ 2;
    List<Curve> curves = [];
    for (int i = 0; i < curvesCount; i++) {
      final curve = Curve.fromInt(reader.getUint16(offset));
      if (curve != Curve.Unsupported) {
        curves.add(curve);
      }
      offset += 2;
    }
    return ExtSupportedEllipticCurves(curves: curves);
  }
}

// ExtUnknown (for debugging, as per Go file)
class ExtUnknown extends Extension {
  ExtensionTypeValue type;
  int dataLength;

  ExtUnknown({required this.type, required this.dataLength});

  @override
  String toString() {
    return "[Unknown Extension Type] Ext Type: ${type.value}, Data: $dataLength bytes";
  }

  @override
  ExtensionTypeValue extensionType() {
    return ExtensionTypeValue.Unsupported; // Or any appropriate unknown value
  }

  @override
  Uint8List encode() {
    throw UnimplementedError("ExtUnknown cannot be encoded, it's readonly");
  }

  static ExtUnknown decode(int extensionLength, Uint8List buf) {
    // In Go, it takes extensionLength directly, but the constructor likely needs the type.
    // Assuming type would come from the outer parsing loop.
    return ExtUnknown(
        type: ExtensionTypeValue.Unsupported, dataLength: extensionLength);
  }
}
