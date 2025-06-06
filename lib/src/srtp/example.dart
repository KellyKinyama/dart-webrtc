import 'package:pointycastle/export.dart';
import 'dart:typed_data';
import 'package:convert/convert.dart';

void main() {
  Uint8List key =
      Uint8List.fromList(hex.decode("6dbe8f8c87d58e61c2ec29321f42e9ff"));
  Uint8List nonce = Uint8List.fromList(hex.decode("101112131415161718191A1B"));
  Uint8List aad = Uint8List.fromList(hex.decode("6465764944"));
  Uint8List plaintext = Uint8List.fromList(
      hex.decode("00626c742e332e3132397649356b744455415443"));

// Encrypt with AES/CCM
  CCMBlockCipher encrypter = CCMBlockCipher(AESEngine());
  AEADParameters paramsEnc = AEADParameters(KeyParameter(key), 32, nonce, aad);
  encrypter.init(true, paramsEnc);
  Uint8List ciphertextTag = encrypter.process(plaintext);
  print(hex.encode(
      ciphertextTag)); // a2bbe65fcc7d13a8aeef2309055c3e2d24cd2f07bd2265cc - the last 4 bytes are the tag

// Decrypt with AES/CCM
  CCMBlockCipher decrypter = CCMBlockCipher(AESEngine());
  AEADParameters paramsDec = AEADParameters(KeyParameter(key), 32, nonce, aad);
  decrypter.init(false, paramsDec);
  Uint8List decrypted = decrypter.process(ciphertextTag);
  print("Decrypted: $decrypted");
  print("Wanted:    $plaintext");
}
