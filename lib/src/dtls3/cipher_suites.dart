// cipher_suites.dart (Converted from ciphersuites.go)

import 'dart:typed_data';
import 'package:crypto/crypto.dart'; // For SHA256, if needed. Assuming common.dart handles it.

// Placeholder for common DTLS types if they are not defined elsewhere
// If they are in dtls.dart, you might need to import it.
// import 'dtls.dart';

enum CipherSuiteId {
  TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256(0xc02b),
  TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256(0xc02f),
  TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA(0xc009),
  TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA(0xc013),
  TLS_NULL_WITH_NULL_NULL(0x0000), // Added from dtls.dart in previous turn
  Unsupported(0x0000); // Updated to 0x0000 as per dtls.dart in previous turn

  const CipherSuiteId(this.value);
  final int value;

  factory CipherSuiteId.fromInt(int val) {
    return values.firstWhere((e) => e.value == val,
        orElse: () => CipherSuiteId.Unsupported);
  }

  @override
  String toString() {
    switch (this) {
      case TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256:
        return 'TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256';
      case TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256:
        return 'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256';
      case TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA:
        return 'TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA';
      case TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA:
        return 'TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA';
      case TLS_NULL_WITH_NULL_NULL:
        return 'TLS_NULL_WITH_NULL_NULL';
      default:
        return 'Unsupported';
    }
  }
}

enum CurveType {
  NamedCurve(0x03), // Assuming this is the only one implemented
  Unsupported(0x00);

  const CurveType(this.value);
  final int value;

  factory CurveType.fromInt(int val) {
    return values.firstWhere((e) => e.value == val,
        orElse: () => CurveType.Unsupported);
  }
}

enum Curve {
  X25519(0x001d), // Assuming this is the only one implemented
  Unsupported(0x0000);

  const Curve(this.value);
  final int value;

  factory Curve.fromInt(int val) {
    return values.firstWhere((e) => e.value == val,
        orElse: () => Curve.Unsupported);
  }
}

enum PointFormat {
  Uncompressed(0x00),
  Unsupported(0x00);

  const PointFormat(this.value);
  final int value;

  factory PointFormat.fromInt(int val) {
    return values.firstWhere((e) => e.value == val,
        orElse: () => PointFormat.Unsupported);
  }
}

enum HashAlgorithm {
  SHA256(0x04), // As per RFC 5246, Section 7.4.1.4.1
  Unsupported(0x00);

  const HashAlgorithm(this.value);
  final int value;

  factory HashAlgorithm.fromInt(int val) {
    return values.firstWhere((e) => e.value == val,
        orElse: () => HashAlgorithm.Unsupported);
  }

  Hash get hashFunction {
    switch (this) {
      case SHA256:
        return sha256;
      default:
        throw Exception('Unsupported hash algorithm');
    }
  }

  @override
  String toString() {
    switch (this) {
      case SHA256:
        return 'SHA256';
      default:
        return 'Unknown Hash Algorithm';
    }
  }
}

enum SignatureAlgorithm {
  ECDSA(0x03), // As per RFC 5246, Section 7.4.1.4.1
  Unsupported(0x00);

  const SignatureAlgorithm(this.value);
  final int value;

  factory SignatureAlgorithm.fromInt(int val) {
    return values.firstWhere((e) => e.value == val,
        orElse: () => SignatureAlgorithm.Unsupported);
  }

  @override
  String toString() {
    switch (this) {
      case ECDSA:
        return 'ECDSA';
      default:
        return 'Unknown Signature Algorithm';
    }
  }
}

enum CertificateType {
  ECDSASign(0x01),
  Unsupported(0x00);

  const CertificateType(this.value);
  final int value;

  factory CertificateType.fromInt(int val) {
    return values.firstWhere((e) => e.value == val,
        orElse: () => CertificateType.Unsupported);
  }

  @override
  String toString() {
    switch (this) {
      case ECDSASign:
        return 'ECDSASign';
      default:
        return 'Unknown Certificate Type';
    }
  }
}

enum KeyExchangeAlgorithm {
  None(0x00),
  ECDHE(0x02),
  Unsupported(0x00);

  const KeyExchangeAlgorithm(this.value);
  final int value;

  factory KeyExchangeAlgorithm.fromInt(int val) {
    return values.firstWhere((e) => e.value == val,
        orElse: () => KeyExchangeAlgorithm.Unsupported);
  }

  @override
  String toString() {
    switch (this) {
      case None:
        return 'None';
      case ECDHE:
        return 'ECDHE';
      default:
        return 'Unknown Key Exchange Algorithm';
    }
  }
}

enum SRTPProtectionProfile {
  SRTPProtectionProfile_AEAD_AES_128_GCM(0x0007),
  UnSupported(9999); // This value was in `simple_extensions.dart` previously

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
        return 'SRTPProtectionProfile_AEAD_AES_128_GCM';
      default:
        return 'Unsupported';
    }
  }
}

class AlgoPair {
  HashAlgorithm hashAlgorithm;
  SignatureAlgorithm signatureAlgorithm;

  AlgoPair({
    required this.hashAlgorithm,
    required this.signatureAlgorithm,
  });

  static (AlgoPair, int) decode(Uint8List buf, int offset) {
    final reader = ByteData.sublistView(buf);
    final hashAlg = HashAlgorithm.fromInt(reader.getUint8(offset));
    offset++;
    final sigAlg = SignatureAlgorithm.fromInt(reader.getUint8(offset));
    offset++;
    return (
      AlgoPair(hashAlgorithm: hashAlg, signatureAlgorithm: sigAlg),
      offset
    );
  }

  Uint8List encode() {
    return Uint8List.fromList([hashAlgorithm.value, signatureAlgorithm.value]);
  }

  @override
  String toString() {
    return '{HashAlg: $hashAlgorithm Signature Alg: $signatureAlgorithm}';
  }
}