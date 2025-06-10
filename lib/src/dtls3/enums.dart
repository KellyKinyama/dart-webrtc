enum Flight {
  Flight0(0),
  Flight2(2),
  Flight3(3),
  Flight4(4),
  Flight6(6);

  const Flight(this.value);
  final int value;
}

enum DTLSState {
  connected,
  connecting,
  disconnected;
}

enum ECCurveType {
  Named_Curve(3),
  Unsupported(65555);

  const ECCurveType(this.value);
  final int value;

  factory ECCurveType.fromInt(int value) {
    switch (value) {
      case 3:
        return Named_Curve;
      default:
        throw ArgumentError('Invalid ECCurveType value: $value');
    }
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
    return values.firstWhere(
      (element) => element.value == key,
      orElse: () => NamedCurve.Unsupported,
    );
  }
}
