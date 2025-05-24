import 'dart:typed_data';

import '../crypto.dart';
import 'handshake.dart';

class ServerKeyExchange {
  final List<int> identityHint;
  final EllipticCurveType ellipticCurveType;
  final NamedCurve namedCurve;
  final List<int> publicKey;
  final SignatureHashAlgorithm signatureHashAlgorithm;
  final List<int> signature;

  ServerKeyExchange({
    required this.identityHint,
    required this.ellipticCurveType,
    required this.namedCurve,
    required this.publicKey,
    required this.signatureHashAlgorithm,
    required this.signature,
  });

  ContentType getContentType() {
    return ContentType.content_handshake;
  }

  // Handshake type
  HandshakeType getHandshakeType() {
    return HandshakeType.server_key_exchange;
  }

  // Calculate size
  int size() {
    if (identityHint.isNotEmpty) {
      return 2 + identityHint.length;
    } else {
      return 1 + 2 + 1 + publicKey.length + 2 + 2 + signature.length;
    }
  }

  // Marshal to byte array
  Uint8List marshal() {
    final byteData = BytesBuilder();

    if (identityHint.isNotEmpty) {
      final lengthBytes = Uint8List(2);
      ByteData.sublistView(lengthBytes).setUint16(0, identityHint.length);
      byteData.add(lengthBytes);
      byteData.add(Uint8List.fromList(identityHint));
      return byteData.toBytes();
    }

    byteData.addByte(ellipticCurveType.value);
    byteData.add(Uint8List.fromList([
      (namedCurve.value >> 8) & 0xFF,
      namedCurve.value & 0xFF,
    ]));

    byteData.addByte(publicKey.length);
    byteData.add(Uint8List.fromList(publicKey));

    byteData.addByte(signatureHashAlgorithm.hash.value);
    byteData.addByte(signatureHashAlgorithm.signatureAgorithm.value);

    byteData.add(Uint8List.fromList([
      (signature.length >> 8) & 0xFF,
      signature.length & 0xFF,
    ]));
    byteData.add(Uint8List.fromList(signature));

    return byteData.toBytes();
  }

  // Uint8List marshal() {
  //   return Uint8List.fromList([
  //     0,
  //     21,
  //     119,
  //     101,
  //     98,
  //     114,
  //     116,
  //     99,
  //     45,
  //     114,
  //     115,
  //     32,
  //     68,
  //     84,
  //     76,
  //     83,
  //     32,
  //     67,
  //     108,
  //     105,
  //     101,
  //     110,
  //     116
  //   ]);
  // }

  // Unmarshal from byte array
  static ServerKeyExchange unmarshal(Uint8List data) {
    int pskLength = (data[0] << 8) | data[1];

    if (data.length == pskLength + 2) {
      return ServerKeyExchange(
        identityHint: data.sublist(2),
        ellipticCurveType: EllipticCurveType.unsupported,
        namedCurve: NamedCurve.Unsupported,
        publicKey: [],
        signatureHashAlgorithm: SignatureHashAlgorithm(
          hash: HashAlgorithm.unsupported,
          signatureAgorithm: SignatureAlgorithm.unsupported,
        ),
        signature: [],
      );
    }

    print("Elliptic curve type: ${data[0]}");

    var ellipticCurveType = EllipticCurveType.fromInt(data[0]);
    int offset = 1;

    int namedCurveIndex = ByteData.sublistView(data).getUint16(offset);
    //print("Named curve: $namedCurveIndex");
    var namedCurve = NamedCurve.fromInt(namedCurveIndex);
    offset += 2;

    int publicKeyLength = data[offset];
    offset += 1;
    List<int> publicKey = data.sublist(offset, offset + publicKeyLength);
    offset += publicKeyLength;

    int hashAlgorithmIndex = data[offset];
    offset += 1;
    int signatureAlgorithmIndex = data[offset];
    offset += 1;

    int signatureLength = ByteData.sublistView(data)
        .getUint16(offset); //data[offset] << 8) | data[offset + 1];
    offset += 2;

    List<int> signature = data.sublist(offset, offset + signatureLength);

    //print("signature AlgorithmIndex: $signatureAlgorithmIndex");

    return ServerKeyExchange(
      identityHint: [],
      ellipticCurveType: ellipticCurveType,
      namedCurve: namedCurve,
      publicKey: publicKey,
      signatureHashAlgorithm: SignatureHashAlgorithm(
        hash: HashAlgorithm.fromInt(hashAlgorithmIndex),
        signatureAgorithm: SignatureAlgorithm.fromInt(signatureAlgorithmIndex),
      ),
      signature: signature,
    );
  }

  @override
  String toString() {
    return 'ServerKeyExchange(identityHint: $identityHint, ellipticCurveType: $ellipticCurveType, namedCurve: $namedCurve, publicKey: $publicKey, algorithm: $signatureHashAlgorithm, signature: $signature)';
  }

  static decode(Uint8List buf, int offset, int arrayLen) {}
}

// Curve type 1: secp256r1 (also known as prime256v1 or NIST P-256)
// Curve type 2: secp521r1 (NIST P-521)
// Curve type 3: secp384r1 (NIST P-384)
// Curve type 4: x25519 (X25519, widely used for Diffie-Hellman)
// Curve type 5: x448 (X448, a high-security curve)

void main() {
  // Example usage
  // final handshake = ServerKeyExchange(
  //   identityHint: [1, 2, 3],
  //   ellipticCurveType: EllipticCurveType.NamedCurve,
  //   namedCurve: NamedCurve.x25519,
  //   publicKey: serverKeyExchange.sublist(4, 69), // Example public key
  //   signatureHashAlgorithm: SignatureHashAlgorithm(
  //     hash: HashAlgorithm.sha256,
  //     signatureAgorithm: SignatureAlgorithm.Ecdsa,
  //   ),
  //   signature: serverKeyExchange.sublist(73, 144), // Example signature
  // );

  // Marshal the data to a byte array
  // Uint8List marshalledData = handshake.marshal();
  //print('Marshalled Data: $marshalledData');
  // print("Content type: ${serverKeyExchange[0]}");
  // Unmarshal the byte array
  final unmarshalled = ServerKeyExchange.unmarshal(pskServerKeyExchange);
  print('Server key exchange: $unmarshalled');
  print("");
  print('Server key exchange: ${unmarshalled.marshal()}');
  print("");
  print('expected:            $pskServerKeyExchange');
//   print("""
// """);

//   print('Public key: ${unmarshalled.publicKey}');
//   print('expected:   ${raw_server_key_exchange.sublist(4, 69)}');
}

final pskServerKeyExchange = Uint8List.fromList([
  0x00,
  0x15,
  0x77,
  0x65,
  0x62,
  0x72,
  0x74,
  0x63,
  0x2d,
  0x72,
  0x73,
  0x20,
  0x44,
  0x54,
  0x4c,
  0x53,
  0x20,
  0x43,
  0x6c,
  0x69,
  0x65,
  0x6e,
  0x74
]);

final serverKeyExchange = Uint8List.fromList([
  0x03,
  0x00,
  0x1d,
  0x41,
  0x04,
  0x0c,
  0xb9,
  0xa3,
  0xb9,
  0x90,
  0x71,
  0x35,
  0x4a,
  0x08,
  0x66,
  0xaf,
  0xd6,
  0x88,
  0x58,
  0x29,
  0x69,
  0x98,
  0xf1,
  0x87,
  0x0f,
  0xb5,
  0xa8,
  0xcd,
  0x92,
  0xf6,
  0x2b,
  0x08,
  0x0c,
  0xd4,
  0x16,
  0x5b,
  0xcc,
  0x81,
  0xf2,
  0x58,
  0x91,
  0x8e,
  0x62,
  0xdf,
  0xc1,
  0xec,
  0x72,
  0xe8,
  0x47,
  0x24,
  0x42,
  0x96,
  0xb8,
  0x7b,
  0xee,
  0xe7,
  0x0d,
  0xdc,
  0x44,
  0xec,
  0xf3,
  0x97,
  0x6b,
  0x1b,
  0x45,
  0x28,
  0xac,
  0x3f,
  0x35,
  0x02,
  0x03,
  0x00,
  0x47,
  0x30,
  0x45,
  0x02,
  0x21,
  0x00,
  0xb2,
  0x0b,
  0x22,
  0x95,
  0x3d,
  0x56,
  0x57,
  0x6a,
  0x3f,
  0x85,
  0x30,
  0x6f,
  0x55,
  0xc3,
  0xf4,
  0x24,
  0x1b,
  0x21,
  0x07,
  0xe5,
  0xdf,
  0xba,
  0x24,
  0x02,
  0x68,
  0x95,
  0x1f,
  0x6e,
  0x13,
  0xbd,
  0x9f,
  0xaa,
  0x02,
  0x20,
  0x49,
  0x9c,
  0x9d,
  0xdf,
  0x84,
  0x60,
  0x33,
  0x27,
  0x96,
  0x9e,
  0x58,
  0x6d,
  0x72,
  0x13,
  0xe7,
  0x3a,
  0xe8,
  0xdf,
  0x43,
  0x75,
  0xc7,
  0xb9,
  0x37,
  0x6e,
  0x90,
  0xe5,
  0x3b,
  0x81,
  0xd4,
  0xda,
  0x68,
  0xcd,
]);
