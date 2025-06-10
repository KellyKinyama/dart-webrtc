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
