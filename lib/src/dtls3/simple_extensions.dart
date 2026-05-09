// Minimal restoration of the legacy `lib/src/dtls3/simple_extensions.dart`.
//
// Concrete TLS extension types referenced by `lib/src/dtls/handshake/...`.
// They round-trip through [Extension.encode] / their `decode(...)` factory
// so handshake messages can be re-serialized verbatim.

import 'dart:typed_data';

import 'extensions.dart';

/// `use_srtp` (RFC 5764). Carries the negotiated SRTP protection profile
/// list and an MKI value.
class ExtUseSRTP extends Extension {
  final List<int> protectionProfiles;
  final Uint8List mki;

  ExtUseSRTP(this.protectionProfiles, this.mki);

  @override
  ExtensionTypeValue extensionType() => ExtensionTypeValue.UseSrtp;

  @override
  Uint8List encode() {
    final out = Uint8List(2 + protectionProfiles.length * 2 + 1 + mki.length);
    final bd = ByteData.sublistView(out);
    var offset = 0;
    bd.setUint16(offset, protectionProfiles.length * 2);
    offset += 2;
    for (final p in protectionProfiles) {
      bd.setUint16(offset, p);
      offset += 2;
    }
    out[offset++] = mki.length;
    out.setRange(offset, offset + mki.length, mki);
    return out;
  }

  static ExtUseSRTP decode(int extensionLength, Uint8List data) {
    final bd = ByteData.sublistView(data);
    var offset = 0;
    final ppLen = bd.getUint16(offset);
    offset += 2;
    final count = ppLen ~/ 2;
    final pps = List<int>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      pps[i] = bd.getUint16(offset);
      offset += 2;
    }
    final mkiLen = data[offset++];
    final mki = Uint8List.fromList(data.sublist(offset, offset + mkiLen));
    return ExtUseSRTP(pps, mki);
  }

  @override
  String toString() =>
      '[UseSRTP] profiles=$protectionProfiles, mki=${mki.length} bytes';
}

/// `supported_groups` / supported elliptic curves (RFC 8422).
class ExtSupportedEllipticCurves extends Extension {
  final List<int> curves;
  ExtSupportedEllipticCurves(this.curves);

  @override
  ExtensionTypeValue extensionType() =>
      ExtensionTypeValue.SupportedEllipticCurves;

  @override
  Uint8List encode() {
    final out = Uint8List(2 + curves.length * 2);
    final bd = ByteData.sublistView(out);
    bd.setUint16(0, curves.length * 2);
    for (var i = 0; i < curves.length; i++) {
      bd.setUint16(2 + i * 2, curves[i]);
    }
    return out;
  }

  static ExtSupportedEllipticCurves decode(
      int extensionLength, Uint8List data) {
    final bd = ByteData.sublistView(data);
    final byteLen = bd.getUint16(0);
    final count = byteLen ~/ 2;
    final out = List<int>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      out[i] = bd.getUint16(2 + i * 2);
    }
    return ExtSupportedEllipticCurves(out);
  }

  @override
  String toString() => '[SupportedEllipticCurves] $curves';
}

/// `ec_point_formats` (RFC 8422).
class ExtSupportedPointFormats extends Extension {
  final List<int> pointFormats;
  ExtSupportedPointFormats(this.pointFormats);

  @override
  ExtensionTypeValue extensionType() =>
      ExtensionTypeValue.SupportedPointFormats;

  @override
  Uint8List encode() {
    final out = Uint8List(1 + pointFormats.length);
    out[0] = pointFormats.length;
    out.setRange(1, 1 + pointFormats.length, pointFormats);
    return out;
  }

  static ExtSupportedPointFormats decode(int extensionLength, Uint8List data) {
    final count = data[0];
    final pf = List<int>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      pf[i] = data[1 + i];
    }
    return ExtSupportedPointFormats(pf);
  }

  @override
  String toString() => '[SupportedPointFormats] $pointFormats';
}

/// `extended_master_secret` (RFC 7627). Empty body.
class ExtUseExtendedMasterSecret extends Extension {
  @override
  ExtensionTypeValue extensionType() =>
      ExtensionTypeValue.UseExtendedMasterSecret;

  @override
  Uint8List encode() => Uint8List(0);

  static ExtUseExtendedMasterSecret decode(int extensionLength, Uint8List _) =>
      ExtUseExtendedMasterSecret();

  @override
  String toString() => '[UseExtendedMasterSecret]';
}

/// `renegotiation_info` (RFC 5746). Empty body for the initial handshake.
class ExtRenegotiationInfo extends Extension {
  final Uint8List renegotiatedConnection;
  ExtRenegotiationInfo([Uint8List? data])
      : renegotiatedConnection = data ?? Uint8List(0);

  @override
  ExtensionTypeValue extensionType() => ExtensionTypeValue.RenegotiationInfo;

  @override
  Uint8List encode() {
    final out = Uint8List(1 + renegotiatedConnection.length);
    out[0] = renegotiatedConnection.length;
    out.setRange(1, out.length, renegotiatedConnection);
    return out;
  }

  static ExtRenegotiationInfo decode(int extensionLength, Uint8List data) {
    if (data.isEmpty) return ExtRenegotiationInfo();
    final len = data[0];
    return ExtRenegotiationInfo(
      Uint8List.fromList(data.sublist(1, 1 + len)),
    );
  }

  @override
  String toString() => '[RenegotiationInfo] ${renegotiatedConnection.length}B';
}

/// Catch-all for extensions we don't decode. Preserves the body so it can
/// be re-emitted byte-for-byte.
class ExtUnknown extends Extension {
  final int dataLength;
  final Uint8List data;
  final int rawType;

  ExtUnknown({
    required this.dataLength,
    required this.data,
    this.rawType = 0xFFFF,
  });

  @override
  ExtensionTypeValue extensionType() => ExtensionTypeValue.Unsupported;

  @override
  Uint8List encode() => data;

  static ExtUnknown decode(int extensionLength, Uint8List data) =>
      ExtUnknown(dataLength: extensionLength, data: Uint8List.fromList(data));

  @override
  String toString() => '[Unknown ext] ${data.length}B';
}
