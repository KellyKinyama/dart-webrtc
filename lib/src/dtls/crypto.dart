// See for complete overview: https://www.iana.org/assignments/tls-parameters/tls-parameters.xml

// Only TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 was implemented.
// See for further Cipher Suite types: https://www.rfc-editor.org/rfc/rfc8422.html#section-6
typedef CipherSuiteID = int;

// Only NamedCurve was implemented.
// See for further CurveType types: https://www.rfc-editor.org/rfc/rfc8422.html#section-5.4
typedef CurveType = int;

// Only X25519 was implemented.
// See for further NamedCurve types: https://www.rfc-editor.org/rfc/rfc8422.html#section-5.1.1
typedef Curve = int;

// Only Uncompressed was implemented.
// See for further Elliptic Curve Point Format types: https://www.rfc-editor.org/rfc/rfc8422.html#section-5.1.2
typedef PointFormat = int;

// Only SHA256 was implemented.
// See for further Hash Algorithm types (in "HashAlgorithm" enum):  https://www.rfc-editor.org/rfc/rfc5246.html#section-7.4.1.4.1
// typedef HashAlgorithm = int;

// Only ECDSA was implemented.
// See for further Signature Algorithm types: (in "signed_params" bullet, SignatureAlgorithm enum) https://www.rfc-editor.org/rfc/rfc8422.html#section-5.4
// See also (in "SignatureAlgorithm" enum): https://www.rfc-editor.org/rfc/rfc5246.html#section-7.4.1.4.1
// typedef SignatureAlgorithm = int;

// Only ECDSA Sign was implemented.
// See for further ClientCertificateType types (in "ClientCertificateType" enum):  https://www.rfc-editor.org/rfc/rfc8422.html#section-5.5
// See also https://tools.ietf.org/html/rfc5246#section-7.4.4
typedef CertificateType = int;

enum SignatureAlgorithm {
  Rsa(1),
  Ecdsa(3),
  Ed25519(7),
  unsupported(255);

  const SignatureAlgorithm(this.value);
  final int value;

  factory SignatureAlgorithm.fromInt(int key) {
    return values.firstWhere((element) {
      return element.value == key;
    }, orElse: () {
      return SignatureAlgorithm.unsupported;
    });
  }
}

class SignatureHashAlgorithm {
  final HashAlgorithm hash;
  final SignatureAlgorithm signatureAgorithm;

  SignatureHashAlgorithm({required this.hash, required this.signatureAgorithm});

  @override
  String toString() {
    return 'SignatureHashAlgorithm(hash: $hash, signature: $signatureAgorithm)';
  }
}

enum EllipticCurveType {
  NamedCurve(0x03),
  unsupported(255);

  const EllipticCurveType(this.value);
  final int value;

  factory EllipticCurveType.fromInt(int key) {
    return values.firstWhere((element) => element.value == key);
  }
}

enum ECCurveType {
  //  deprecated (1..2),
  NAMED_CURVE(3);
  //  reserved(248..255)

  const ECCurveType(this.value);
  final int value;

  factory ECCurveType.fromInt(int key) {
    return values.firstWhere((element) => element.value == key);
  }
}

enum NamedCurve {
  prime256v1(0x0017),
  prime384v1(0x0018),
  prime521v1(0x0019),
  x25519(0x001D),
  x448(0x001E),
  ffdhe2048(0x0100),
  ffdhe3072(0x0101),
  ffdhe4096(0x0102),
  ffdhe6144(0x0103),
  ffdhe8192(0x0104),
  secp256k1(0x0012),
  Unsupported(0);
  // secp256r1(0x0017),
  // secp384r1(0x0018),
  // secp521r1(0x0019),
  // secp256k1(0x0012),
  // secp256r1(0x0017),
  // secp384r1(0x0018),
  // secp521r1(0x0019),
  // secp256k1(0x0012),
  // secp256r1(0x0017),

  const NamedCurve(this.value);
  final int value;

  factory NamedCurve.fromInt(int key) {
    return values.firstWhere((element) => element.value == key);
  }
}

enum HashAlgorithm {
  Md2(0), // Blacklisted
  Md5(1), // Blacklisted
  Sha1(2), // Blacklisted
  Sha224(3),
  Sha256(4),
  Sha384(5),
  Sha512(6),
  Ed25519(8),
  unsupported(255),
  sha256(2);

  const HashAlgorithm(this.value);
  final int value;

  factory HashAlgorithm.fromInt(int key) {
    return values.firstWhere((element) => element.value == key);
  }
}

typedef KeyExchangeAlgorithm = int;

// Only SRTP_AEAD_AES_128_GCM was implemented.
// See for further SRTP Protection Profile types: https://www.iana.org/assignments/srtp-protection/srtp-protection.xhtml
typedef SRTPProtectionProfile = int;

enum CipherSuiteId {
  // AES-128-CCM
  Tls_Ecdhe_Ecdsa_With_Aes_128_Ccm(0xc0ac),
  Tls_Ecdhe_Ecdsa_With_Aes_128_Ccm_8(0xc0ae),

  // AES-128-GCM-SHA256
  Tls_Ecdhe_Ecdsa_With_Aes_128_Gcm_Sha256(0xc02b),
  Tls_Ecdhe_Rsa_With_Aes_128_Gcm_Sha256(0xc02f),

  // AES-256-CBC-SHA
  Tls_Ecdhe_Ecdsa_With_Aes_256_Cbc_Sha(0xc00a),
  Tls_Ecdhe_Rsa_With_Aes_256_Cbc_Sha(0xc014),

  Tls_Psk_With_Aes_128_Ccm(0xc0a4),
  Tls_Psk_With_Aes_128_Ccm_8(0xc0a8),
  Tls_Psk_With_Aes_128_Gcm_Sha256(0x00a8),

  Unsupported(0x0000);

  const CipherSuiteId(this.value);
  final int value;

  factory CipherSuiteId.fromInt(int key) {
    return values.firstWhere((element) => element.value == key,
        orElse: () => Unsupported);
  }
}

class CipherSuite {
  CipherSuiteID cipherSuiteID;
  KeyExchangeAlgorithm keyExchangeAlgorithm;
  CertificateType certificateType;
  HashAlgorithm hashAlgorithm;
  SignatureAlgorithm signatureAlgorithm;

  CipherSuite(this.cipherSuiteID, this.keyExchangeAlgorithm,
      this.certificateType, this.hashAlgorithm, this.signatureAlgorithm);

  @override
  String toString() {
    // TODO: implement toString
    return "{CipherSuite: $cipherSuiteID}";
  }
}

// const (
// Only TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 was implemented.
// See for further Cipher Suite types: https://www.rfc-editor.org/rfc/rfc8422.html#section-6
CipherSuiteID CipherSuiteID_TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 = 0xc02b;

// Only NamedCurve was implemented.
// See for further CurveType types: https://www.rfc-editor.org/rfc/rfc8422.html#section-5.4
CurveType CurveTypeNamedCurve = 0x03;

// Only X25519 was implemented.
// See for further NamedCurve types: https://www.rfc-editor.org/rfc/rfc8422.html#section-5.1.1
Curve CurveX25519 = 0x001d;

// Only Uncompressed was implemented.
// See for further Elliptic Curve Point Format types: https://www.rfc-editor.org/rfc/rfc8422.html#section-5.1.2
PointFormat PointFormatUncompressed = 0;

// Only SHA256 was implemented.
// See for further Hash Algorithm types (in "HashAlgorithm" enum):  https://www.rfc-editor.org/rfc/rfc5246.html#section-7.4.1.4.1
HashAlgorithm HashAlgorithmSHA256 = HashAlgorithm.fromInt(4);

// Only ECDSA was implemented.
// See for further Signature Algorithm types: (in "signed_params" bullet, SignatureAlgorithm enum) https://www.rfc-editor.org/rfc/rfc8422.html#section-5.4
// See also (in "SignatureAlgorithm" enum): https://www.rfc-editor.org/rfc/rfc5246.html#section-7.4.1.4.1
SignatureAlgorithm SignatureAlgorithmECDSA = SignatureAlgorithm.fromInt(3);

// Only ECDSA Sign was implemented.
// See for further ClientCertificateType types (in "ClientCertificateType" enum):  https://www.rfc-editor.org/rfc/rfc8422.html#section-5.5
// See also https://tools.ietf.org/html/rfc5246#section-7.4.4
CertificateType CertificateTypeECDSASign = 64;

KeyExchangeAlgorithm KeyExchangeAlgorithmNone = 0; //Value is not important
KeyExchangeAlgorithm KeyExchangeAlgorithmECDHE = 1; //Value is not important

// Only SRTP_AEAD_AES_128_GCM was implemented.
// See for further SRTP Protection Profile types: https://www.iana.org/assignments/srtp-protection/srtp-protection.xhtml
SRTPProtectionProfile SRTPProtectionProfile_AEAD_AES_128_GCM = 0x0007;
// )

final supportedCurves = {
  CurveX25519: true,
};

final supportedSRTPProtectionProfiles = {
  SRTPProtectionProfile_AEAD_AES_128_GCM: true,
};

final supportedCipherSuites = {
  CipherSuiteID_TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256: (
    CipherSuiteID_TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
    KeyExchangeAlgorithmECDHE,
    CertificateTypeECDSASign,
    HashAlgorithmSHA256,
    SignatureAlgorithmECDSA,
  ),
};
