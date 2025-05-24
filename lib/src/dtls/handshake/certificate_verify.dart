import 'dart:typed_data';

import '../crypto.dart';

class CertificateVerify {
  final SignatureHashAlgorithm algorithm;
  final Uint8List signature;

  CertificateVerify({
    required this.algorithm,
    required this.signature,
  });

  // Handshake type
  // HandshakeType handshakeType() {
  //   return HandshakeType.CertificateVerify;
  // }

  // Calculate size
  int size() {
    return 1 + 1 + 2 + signature.length;
  }

  // Marshal to byte array
  Uint8List marshal() {
    final byteData = BytesBuilder();

    // Write algorithm
    byteData.addByte(algorithm.hash.value);
    byteData.addByte(algorithm.signatureAgorithm.value);

    // Write signature length
    byteData.addByte(signature.length >> 8);
    byteData.addByte(signature.length & 0xFF);

    // Write signature
    byteData.add(signature);

    return byteData.toBytes();
  }

  // Unmarshal from byte array
  static CertificateVerify unmarshal(Uint8List data) {
    final reader = ByteData.sublistView(data);
    int offset = 0;

    // Read algorithm
    final hashAlgorithm = HashAlgorithm.fromInt(reader.getUint8(offset++));
    final signatureAlgorithm =
        SignatureAlgorithm.fromInt(reader.getUint8(offset++));
    final algorithm = SignatureHashAlgorithm(
        hash: hashAlgorithm, signatureAgorithm: signatureAlgorithm);

    // Read signature length
    final signatureLength = reader.getUint16(offset);
    offset += 2;

    // Read signature
    final signature =
        Uint8List.fromList(data.sublist(offset, offset + signatureLength));

    return CertificateVerify(
      algorithm: algorithm,
      signature: signature,
    );
  }

  @override
  String toString() {
    return 'HandshakeMessageCertificateVerify(algorithm: $algorithm, signature: ${signature.length} bytes)';
  }

  static decode(Uint8List buf, int offset, int arrayLen) {}
}
