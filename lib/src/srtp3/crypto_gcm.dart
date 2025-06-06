// lib/srtp/cryptogcm.dart
import 'dart:typed_data';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
// import 'package:pointycastle/modes/gcm.dart';
import 'rtp.dart'; // Changed import
import 'constants.dart';

class GCM {
  late GCMBlockCipher srtpGCM;
  late GCMBlockCipher srtcpGCM;
  late Uint8List srtpSalt;
  late Uint8List srtcpSalt;
  late Uint8List srtpSessionKey;

  GCM._(); // Private constructor

  static Future<GCM> newGCM(Uint8List masterKey, Uint8List masterSalt) async {
    final gcm = GCM._();

    final srtpSessionKey = await gcm._aesCmKeyDerivation(
        labelSRTPEncryption, masterKey, masterSalt, 0, masterKey.length);

    gcm.srtpSessionKey = srtpSessionKey;
    final srtpBlockCipher = AESEngine();
    srtpBlockCipher.init(
        true,
        KeyParameter(
            srtpSessionKey)); // true for encryption, but GCM handles both

    gcm.srtpGCM = GCMBlockCipher(srtpBlockCipher);

    final srtcpSessionKey = await gcm._aesCmKeyDerivation(
        labelSRTCPEncryption, masterKey, masterSalt, 0, masterKey.length);
    final srtcpBlockCipher = AESEngine();
    srtcpBlockCipher.init(true, KeyParameter(srtcpSessionKey));

    gcm.srtcpGCM = GCMBlockCipher(srtcpBlockCipher);

    gcm.srtpSalt = await gcm._aesCmKeyDerivation(
        labelSRTPSalt, masterKey, masterSalt, 0, masterSalt.length);
    gcm.srtcpSalt = await gcm._aesCmKeyDerivation(
        labelSRTCPSalt, masterKey, masterSalt, 0, masterSalt.length);

    return gcm;
  }

  Uint8List _rtpInitializationVector(Header header, int roc) {
    final iv = Uint8List(12);
    final byteData = ByteData.view(iv.buffer);

    byteData.setUint32(2, header.ssrc, Endian.big);
    byteData.setUint32(6, roc, Endian.big);
    byteData.setUint16(10, header.sequenceNumber, Endian.big);

    for (int i = 0; i < iv.length; i++) {
      iv[i] ^= srtpSalt[i];
    }
    return iv;
  }

  Future<Uint8List> decrypt(Packet packet, int roc) async {
    final Uint8List ciphertext = packet.rawData;
    final int aeadAuthTagLen =
        16; // Defined in protectionprofiles.go for AES_128_GCM

    final int resultLength = ciphertext.length - aeadAuthTagLen;
    if (resultLength < 0) {
      throw Exception("Ciphertext too short for GCM authentication tag");
    }

    final Uint8List iv = _rtpInitializationVector(packet.header, roc);

    final Uint8List headerBytes =
        Uint8List.fromList(ciphertext.sublist(0, packet.headerSize));
    final Uint8List encryptedPayloadWithTag =
        Uint8List.fromList(ciphertext.sublist(packet.headerSize));

    final params = AEADParameters(
        KeyParameter(srtpSessionKey), aeadAuthTagLen * 8, iv, headerBytes);

    srtpGCM.init(false, params); // false for decryption

    final Uint8List payloadAndTag = Uint8List.fromList(encryptedPayloadWithTag);

    try {
      final decryptedBytes = srtpGCM.process(payloadAndTag);
      return Uint8List.fromList(headerBytes + decryptedBytes);
    } catch (e) {
      throw Exception("SRTP GCM decryption failed: $e");
    }
  }

  Future<Uint8List> encrypt(Packet packet, int roc) async {
    final Uint8List plaintext = packet.payload;
    final int aeadAuthTagLen =
        16; // Defined in protectionprofiles.go for AES_128_GCM

    final Uint8List iv = _rtpInitializationVector(packet.header, roc);

    final Uint8List headerBytes =
        Uint8List.fromList(packet.rawData.sublist(0, packet.headerSize));

    final params = AEADParameters(
        KeyParameter(srtpSessionKey), aeadAuthTagLen * 8, iv, headerBytes);

    srtpGCM.init(true, params); // true for encryption

    final Uint8List encryptedPayload = srtpGCM.process(plaintext);

    final Uint8List ciphertextWithAuthTag =
        Uint8List.fromList(encryptedPayload);

    // The GCM process function returns the ciphertext followed by the authentication tag.
    // We need to combine the header, the encrypted payload, and the authentication tag.
    // The `process` method for GCM in PointyCastle already returns ciphertext + tag.
    // So, we just need to prepend the header.
    return Uint8List.fromList(headerBytes + ciphertextWithAuthTag);
  }

  // Future<Uint8List> _aesCmKeyDerivation(int label, Uint8List masterKey,
  //     Uint8List masterSalt, int index, int length) async {
  //   final result = Uint8List(length);
  //   final kdr = Uint8List(16); // Key Derivation Rate constant (RFC 3711)

  //   // For SRTP, the KDR is 0. So, we'll treat it as zero.
  //   // kdr is filled with zeros.

  //   final AESEngine aesEngine = AESEngine();
  //   aesEngine.init(true, KeyParameter(masterKey)); // True for encryption

  //   for (int i = 0; i < length; i += aesEngine.blockSize) {
  //     final input = Uint8List(16);
  //     final byteData = ByteData.view(input.buffer);

  //     byteData.setUint8(0, label);
  //     byteData.setUint64(2, masterSalt[0] + index, Endian.big); // Example, need to align with Go's behavior

  //     // In Go, it would be:
  //     // binary.BigEndian.PutUint32(input[1:], uint32(label))
  //     // binary.BigEndian.PutUint64(input[4:], uint64(salt) ^ uint64(index))
  //     // This part might need careful adjustment if `masterSalt` is longer or used differently.
  //     // For now, using a simple xor with first byte of salt and index.

  //     final Uint8List output = aesEngine.processBlock(input);
  //     for (int n = 0; n < aesEngine.blockSize && i + n < length; n++) {
  //       result[i + n] = output[n];
  //     }
  //   }
  //   return result;
  // }

  Future<Uint8List> _aesCmKeyDerivation(int label, Uint8List masterKey,
      Uint8List masterSalt, int indexOverKdr, int outLen) async {
    if (indexOverKdr != 0) {
      throw Exception("Non-zero kdr not supported");
    }

    final int nMasterKey = masterKey.length;
    final int nMasterSalt = masterSalt.length;

    final Uint8List prfIn = Uint8List(nMasterKey);
    prfIn.setAll(0, masterSalt.sublist(0, nMasterSalt));

    prfIn[7] ^= label;

    final AESEngine blockCipher = AESEngine();
    blockCipher.init(true, KeyParameter(masterKey)); // true for encryption

    final Uint8List out =
        Uint8List(((outLen + nMasterKey - 1) ~/ nMasterKey) * nMasterKey);
    final ByteData prfInByteData = ByteData.view(prfIn.buffer);

    int i = 0;
    for (int n = 0; n < outLen; n += nMasterKey) {
      prfInByteData.setUint16(nMasterKey - 2, i, Endian.big);
      blockCipher.processBlock(prfIn, 0, out, n);
      i++;
    }
    return Uint8List.fromList(out.sublist(0, outLen));
  }
}
