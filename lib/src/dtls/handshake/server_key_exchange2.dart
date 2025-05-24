// import 'dart:typed_data';

// import '../crypto.dart';

// class ServerKeyExchange {
//   final List<int> identityHint;
//   final EllipticCurveType ellipticCurveType;
//   final NamedCurve namedCurve;
//   final List<int> publicKey;
//   final SignatureHashAlgorithm signatureHashAlgorithm;
//   final List<int> signature;

//   ServerKeyExchange({
//     required this.identityHint,
//     required this.ellipticCurveType,
//     required this.namedCurve,
//     required this.publicKey,
//     required this.signatureHashAlgorithm,
//     required this.signature,
//   });

//   // Marshal to byte array
//   Uint8List marshal() {
//     final byteData = BytesBuilder();

//     if (identityHint.isNotEmpty) {
//       final lengthBytes = Uint8List(2);
//       ByteData.sublistView(lengthBytes).setUint16(0, identityHint.length);
//       byteData.add(lengthBytes);
//       byteData.add(Uint8List.fromList(identityHint));
//       return byteData.toBytes();
//     }

//     byteData.addByte(ellipticCurveType.value);
//     byteData.add(Uint8List.fromList([
//       (namedCurve.value >> 8) & 0xFF,
//       namedCurve.value & 0xFF,
//     ]));

//     byteData.addByte(publicKey.length);
//     byteData.add(Uint8List.fromList(publicKey));

//     byteData.addByte(signatureHashAlgorithm.hash.value);
//     byteData.addByte(signatureHashAlgorithm.signatureAgorithm.value);

//     byteData.add(Uint8List.fromList([
//       (signature.length >> 8) & 0xFF,
//       signature.length & 0xFF,
//     ]));
//     byteData.add(Uint8List.fromList(signature));

//     return byteData.toBytes();
//   }

//   // Unmarshal from byte array
//   static ServerKeyExchange unmarshal(Uint8List data) {
//     ByteData reader = ByteData.sublistView(data);
//     int pskLength = reader.getUint16(0);

//     print("PSK length: $pskLength");

//     if (data.length == pskLength + 2) {
//       return ServerKeyExchange(
//         identityHint: data.sublist(2),
//         ellipticCurveType: EllipticCurveType.unsupported,
//         namedCurve: NamedCurve.Unsupported,
//         publicKey: [],
//         signatureHashAlgorithm: SignatureHashAlgorithm(
//           hash: HashAlgorithm.unsupported,
//           signatureAgorithm: SignatureAlgorithm.unsupported,
//         ),
//         signature: [],
//       );
//     }

//     print("Elliptic curve type: ${data[0]}");

//     var ellipticCurveType = EllipticCurveType.fromInt(data[0]);
//     int offset = 1;

//     int namedCurveIndex = ByteData.sublistView(data).getUint16(offset);
//     //print("Named curve: $namedCurveIndex");
//     var namedCurve = NamedCurve.fromInt(namedCurveIndex);
//     offset += 2;

//     int publicKeyLength = data[offset];
//     offset += 1;
//     List<int> publicKey = data.sublist(offset, offset + publicKeyLength);
//     offset += publicKeyLength;

//     int hashAlgorithmIndex = data[offset];
//     offset += 1;
//     int signatureAlgorithmIndex = data[offset];
//     offset += 1;

//     int signatureLength = ByteData.sublistView(data)
//         .getUint16(offset); //data[offset] << 8) | data[offset + 1];
//     offset += 2;

//     List<int> signature = data.sublist(offset, offset + signatureLength);

//     //print("signature AlgorithmIndex: $signatureAlgorithmIndex");

//     return ServerKeyExchange(
//       identityHint: [],
//       ellipticCurveType: ellipticCurveType,
//       namedCurve: namedCurve,
//       publicKey: publicKey,
//       signatureHashAlgorithm: SignatureHashAlgorithm(
//         hash: HashAlgorithm.fromInt(hashAlgorithmIndex),
//         signatureAgorithm: SignatureAlgorithm.fromInt(signatureAlgorithmIndex),
//       ),
//       signature: signature,
//     );
//   }

//   @override
//   String toString() {
//     // TODO: implement toString
//     return """
// ServerKeyExchange(
//       identityHint: $identityHint,
//       ellipticCurveType: $ellipticCurveType,
//       namedCurve: $namedCurve,
//       publicKey: $publicKey,
//       signatureHashAlgorithm: $signatureHashAlgorithm
//       signature: $signature,
//     )""";
//   }
// }

// void main() {
//   // Example usage
//   // final handshake = ServerKeyExchange(
//   //   identityHint: [1, 2, 3],
//   //   ellipticCurveType: EllipticCurveType.NamedCurve,
//   //   namedCurve: NamedCurve.x25519,
//   //   publicKey: serverKeyExchange.sublist(4, 69), // Example public key
//   //   signatureHashAlgorithm: SignatureHashAlgorithm(
//   //     hash: HashAlgorithm.sha256,
//   //     signatureAgorithm: SignatureAlgorithm.Ecdsa,
//   //   ),
//   //   signature: serverKeyExchange.sublist(73, 144), // Example signature
//   // );

//   // Marshal the data to a byte array
//   // Uint8List marshalledData = handshake.marshal();
//   //print('Marshalled Data: $marshalledData');
//   // print("Content type: ${serverKeyExchange[0]}");
//   // Unmarshal the byte array
//   final unmarshalled = ServerKeyExchange.unmarshal(pskServerKeyExchange);
//   print('Server key exchange: $unmarshalled');
//   print("");
//   print('Server key exchange: ${unmarshalled.marshal()}');
//   print("");
//   print('expected:            $pskServerKeyExchange');
// //   print("""
// // """);

// //   print('Public key: ${unmarshalled.publicKey}');
// //   print('expected:   ${raw_server_key_exchange.sublist(4, 69)}');
// }

// final pskServerKeyExchange = Uint8List.fromList([
//   0x00,
//   0x15,
//   0x77,
//   0x65,
//   0x62,
//   0x72,
//   0x74,
//   0x63,
//   0x2d,
//   0x72,
//   0x73,
//   0x20,
//   0x44,
//   0x54,
//   0x4c,
//   0x53,
//   0x20,
//   0x43,
//   0x6c,
//   0x69,
//   0x65,
//   0x6e,
//   0x74
// ]);
