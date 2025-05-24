import 'package:ecdsa/ecdsa.dart';
import 'package:elliptic/elliptic.dart';
import 'package:pointycastle/asn1.dart';

import 'hex2.dart';

List<int> ecdsaSign(List<int> privateKeyBytes, List<int> hash) {
  final priv = PrivateKey.fromBytes(getP256(), privateKeyBytes);

  final sig = signature(priv, hash);

  final encoded = ASN1Sequence(elements: [
    ASN1Integer(sig.R),
    ASN1Integer(sig.S),
  ]).encode();

  return encoded;
}

bool ecdsaVerify(
    List<int> publicKeyBytes, List<int> hash, List<int> signatureBytes) {
  final pub = PublicKey.fromHex(getP256(), hexEncode(publicKeyBytes));
  var result = verify(pub, hash, Signature.fromCompact(signatureBytes));
  // print("Is verified: $result");
  return result;
}

bool ecdsaVerify2(
    List<int> publicKeyBytes, List<int> hash, List<int> signatureBytes) {
  final pub = PublicKey.fromHex(getP256(), hexEncode(publicKeyBytes));
  var result = verify(pub, hash, Signature.fromCompact(signatureBytes));
  // print("Is verified: $result");
  return result;
}
// void main() {
//   var ec = getP256();
//   var priv = ec.generatePrivateKey();
//   var pub = priv.publicKey;

//   print("public key: ${hexDecode(pub.toHex()).length}");
//   print(priv);
//   print("public key: ${pub.toHex()}");
//   var hashHex =
//       'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9';
//   var hash = hexDecode(hashHex);
//   final signatureBytes = ecdsaSign(priv.bytes, hash);

//   var result = ecdsaVerify(hexDecode(pub.toHex()), hash, signatureBytes);

//   // var result = verify(pub, hash, Signature.fromCompact(signatureBytes));
//   print("Is verified: $result");
//   assert(result);
// }

// bool ecdsaVerify(PublicKey pub, List<int> hash, List<int> signatureBytes) {
//   // final pub = PublicKey.fromHex(getP256(), hexEncode(publicKeyBytes));
//   var result = verify(pub, hash, Signature.fromCompact(signatureBytes));
//   // print("Is verified: $result");
//   return result;
// }

// void main() {
//   var ec = getP256();
//   var priv = ec.generatePrivateKey();
//   var pub = priv.publicKey;
//   print(priv);
//   print(pub);
//   var hashHex =
//       'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9';
//   var hash = hexDecode(hashHex);
//   print("hash: $hash");

//   var sig = signature(priv, hash);

//   var result = verify(pub, hash, sig);
//   assert(result);
// }
void main() {
  var ec = getP256();
  var priv = ec.generatePrivateKey();
  var pub = priv.publicKey;

  print("public key: ${hexDecode(pub.toHex()).length}");
  print("priv: ${priv.bytes.length}");
  print("public key: ${hexDecode(pub.X.toRadixString(16)).length}");

  var hashHex =
      'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9';
  var hash = hexDecode(hashHex);
  final signatureBytes = ecdsaSign(priv.bytes, hash);

  // var result = ecdsaVerify(hexDecode(pub.toHex()), hash, signatureBytes);
  var result = ecdsaVerify(hexDecode(pub.toHex()), hash, signatureBytes);

  print("Is verified: $result");
  // return (
  //   privateKey: Uint8List.fromList(priv.bytes),
  //   publicKey: Uint8List.fromList(hexDecode(pub.toHex()))
  // );
}
