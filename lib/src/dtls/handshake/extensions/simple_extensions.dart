import 'dart:typed_data';

// import 'package:dart_webrtc/src/dtls/ch5/tls3.dart';

import '../../crypto.dart';
import 'extensions.dart';

enum SRTPProtectionProfile {
  SRTPProtectionProfile_AEAD_AES_128_GCM(0x0007),

  UnSupported(9999);

  const SRTPProtectionProfile(this.value);
  final int value;

  factory SRTPProtectionProfile.fromInt(int key) {
    return values.firstWhere((element) => element.value == key,
        orElse: () => SRTPProtectionProfile.UnSupported);
  }
}

class ExtUseExtendedMasterSecret extends Extension {
  ExtensionTypeValue extensionType() {
    return ExtensionTypeValue.UseExtendedMasterSecret;
  }

  Uint8List encode() {
    return Uint8List(0);
  }

  static ExtUseExtendedMasterSecret decode(int extensionLength, Uint8List buf) {
    return ExtUseExtendedMasterSecret();
  }
}

// func (e *ExtUseExtendedMasterSecret) String() string {
// 	return "[UseExtendedMasterSecret]"
// }

// func (e *ExtUseExtendedMasterSecret) ExtensionType() ExtensionType {
// 	return ExtensionTypeUseExtendedMasterSecret
// }

class ExtRenegotiationInfo extends Extension {
  ExtensionTypeValue extensionType() {
    return ExtensionTypeValue.RenegotiationInfo;
  }

  @override
  Uint8List encode() {
    // Empty byte array length is zero
    return Uint8List(0);
  }

  static ExtRenegotiationInfo decode(int extensionLength, Uint8List buf) {
    return ExtRenegotiationInfo();
  }
}

class ExtSupportedSignatureAlgorithms extends Extension {
  List<SignatureHashAlgorithm> signatureHashAlgorithms;
  ExtSupportedSignatureAlgorithms(this.signatureHashAlgorithms);

  @override
  Uint8List encode() {
    final result = Uint8List(2 + 2 + signatureHashAlgorithms.length * 2);
    final bd = ByteData.sublistView(result);
    int offset = 0;
    // TODO: implement encode
    bd.setUint16(offset, 2 + 2 * signatureHashAlgorithms.length);
    offset += 2;
    bd.setUint16(offset, 2 * signatureHashAlgorithms.length);
    offset += 2;
    for (SignatureHashAlgorithm signatureHashAlgorithm
        in signatureHashAlgorithms) {
      bd.setUint8(offset++, signatureHashAlgorithm.hash.value);
      bd.setUint8(offset++, signatureHashAlgorithm.signatureAgorithm.value);
    }

    return result;
  }

  static ExtSupportedSignatureAlgorithms decode(
      int extensionLength, Uint8List buf) {
    int offset = 0;
    final bd = ByteData.sublistView(buf);
    //  let _ = reader.read_u16::<BigEndian>()?;

    final algorithmCount = bd.getUint16(offset) / 2;
    offset++;
    List<SignatureHashAlgorithm> signatureHashAlgorithms = [];
    for (int i = 0; i < algorithmCount; i++) {
      final hash = bd.getUint8(offset++);
      final signature = bd.getUint8(offset++);

      final supportHashAlgo = HashAlgorithm.fromInt(hash);
      final signatureAlgo = SignatureAlgorithm.fromInt(signature);

      if (supportHashAlgo != HashAlgorithm.unsupported &&
          signatureAlgo != SignatureAlgorithm.unsupported) {
        signatureHashAlgorithms.add(SignatureHashAlgorithm(
            hash: supportHashAlgo,
            signatureAgorithm: SignatureAlgorithm.fromInt(signature)));
      }
    }

    return ExtSupportedSignatureAlgorithms(signatureHashAlgorithms);
  }

  @override
  ExtensionTypeValue extensionType() {
    // TODO: implement extensionType
    throw UnimplementedError();
  }
}

class ExtUseSRTP extends Extension {
  // int extensionType;
  // int extensionLength;
  // Uint8List extensionData;
  List<SRTPProtectionProfile> protectionProfiles;
  Uint8List mki;
  ExtUseSRTP(this.protectionProfiles, this.mki);
  @override
  ExtensionTypeValue extensionType() {
    return ExtensionTypeValue.UseSrtp;
  }

  static ExtUseSRTP decode(int extensionLength, Uint8List buf) {
    int offset = 0;
    final bd = ByteData.sublistView(buf);
    final protectionProfilesLength = bd.getUint16(offset);
    offset += 2;
    final protectionProfilesCount = protectionProfilesLength / 2;
    final List<SRTPProtectionProfile> protectionProfiles = [];
    for (int i = 0; i < protectionProfilesCount; i++) {
      final supportedProfile =
          SRTPProtectionProfile.fromInt(bd.getUint16(offset));
      if (supportedProfile != SRTPProtectionProfile.UnSupported) {
        protectionProfiles.add(supportedProfile);
      }
      offset += 2;
    }
    final mkiLength = buf[offset];
    offset++;

    final mki = buf.sublist(offset, offset + mkiLength);
    offset += mkiLength;

    return ExtUseSRTP(protectionProfiles, mki);
  }

  @override
  Uint8List encode() {
    Uint8List result =
        Uint8List((2 + (protectionProfiles.length) * 2) + 1 + mki.length);
    int offset = 0;
    final bd = ByteData.sublistView(result);
    bd.setUint16(offset, protectionProfiles.length * 2);
    offset += 2;
    for (int i = 0; i < protectionProfiles.length; i++) {
      // binary.BigEndian.PutUint16(result[offset:], uint16(e.ProtectionProfiles[i]))
      bd.setUint16(offset, protectionProfiles[i].value);
      offset += 2;
    }
    result[offset] = mki.length;
    offset++;
    result.setAll(offset, mki);
    // copy(result[offset:], e.Mki)
    offset += mki.length;
    return result;
  }
}

// Only Uncompressed was implemented.
// See for further Elliptic Curve Point Format types: https://www.rfc-editor.org/rfc/rfc8422.html#section-5.1.2
class ExtSupportedPointFormats extends Extension {
  List<PointFormat> pointFormats;

  ExtSupportedPointFormats(this.pointFormats);

  @override
  ExtensionTypeValue extensionType() {
    return ExtensionTypeValue.SupportedPointFormats;
  }

  @override
  Uint8List encode() {
    final result = Uint8List(1 + (pointFormats.length));
    int offset = 0;
    result[offset] = pointFormats.length;
    offset++;
    for (int i = 0; i < pointFormats.length; i++) {
      result[offset] = pointFormats[i];
      offset++;
    }
    return result;
  }

  static ExtSupportedPointFormats decode(int extensionLength, Uint8List buf) {
    int offset = 0;
    int pointFormatsCount = buf[offset];
    offset++;
    List<PointFormat> pointFormats = [];
    for (int i = 0; i < pointFormatsCount; i++) {
      pointFormats.add(buf[offset]);
      offset++;
    }

    return ExtSupportedPointFormats(pointFormats);
  }
}

// func (e *ExtSupportedPointFormats) String() string {
// 	return fmt.Sprintf("[SupportedPointFormats] Point Formats: %s", fmt.Sprint(e.PointFormats))
// }

// func (e *ExtSupportedPointFormats) ExtensionType() ExtensionType {
// 	return ExtensionTypeSupportedPointFormats
// }

// Only X25519 was implemented.
// See for further NamedCurve types: https://www.rfc-editor.org/rfc/rfc8422.html#section-5.1.1
class ExtSupportedEllipticCurves extends Extension {
  List<NamedCurve> curves;
  ExtSupportedEllipticCurves(this.curves);

  @override
  ExtensionTypeValue extensionType() {
    return ExtensionTypeValue.SupportedEllipticCurves;
  }

  @override
  Uint8List encode() {
    final result = Uint8List(1 + (curves.length * 2));
    int offset = 0;
    final bd = ByteData.sublistView(result);
    bd.setUint16(offset, curves.length);
    offset += 2;
    for (int i = 0; i < curves.length; i++) {
      // if (curves[i] != NamedCurve.Unsupported) {
      bd.setUint16(offset, curves[i].value);
      offset += 2;
      // }
    }
    return result;
  }

  static ExtSupportedEllipticCurves decode(int extensionLength, Uint8List buf) {
    int offset = 0;
    final bd = ByteData.sublistView(buf);
    final curvesLength = bd.getUint16(offset);
    offset += 2;

    print("Curves count: $curvesLength");
    final curvesCount = (curvesLength ~/ 2);
    List<NamedCurve> curves = [];
    for (int i = 0; i < curvesCount; i++) {
      curves.add(NamedCurve.fromInt(bd.getUint16(offset)));
      print("Curve: ${curves[i]}");
      offset += 2;
    }

    return ExtSupportedEllipticCurves(curves);
  }
}

// func (e *ExtSupportedEllipticCurves) String() string {
// 	curvesStr := make([]string, len(e.Curves))
// 	for i, c := range e.Curves {
// 		curvesStr[i] = c.String()
// 	}
// 	return common.JoinSlice("\n", false,
// 		"[SupportedEllipticCurves]",
// 		common.ProcessIndent("Curves:", "+", curvesStr),
// 	)
// }

// func (e *ExtSupportedEllipticCurves) ExtensionType() ExtensionType {
// 	return ExtensionTypeSupportedEllipticCurves
// }
