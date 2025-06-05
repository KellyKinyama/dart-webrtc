// lib/srtp/cryptogcm.dart
import 'dart:typed_data';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
// import 'package:pointycastle/modes/gcm.dart';
import 'rtp_header.dart';
import 'rtp_packet.dart';
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

    // final ParametersWithIV<AEADParameters> params = ParametersWithIV(
    final params = AEADParameters(
        KeyParameter(srtpSessionKey), aeadAuthTagLen * 8, iv, headerBytes);
    //   iv,
    // );

    srtpGCM.init(false, params); // false for decryption

    // The AAD (Additional Authenticated Data) is the RTP header
    // srtpGCM.aad = headerBytes;

    // final Uint8List plaintext =
    //     Uint8List(encryptedPayloadWithTag.length - aeadAuthTagLen);
    // final Uint8List tag = Uint8List.fromList(encryptedPayloadWithTag
    //     .sublist(encryptedPayloadWithTag.length - aeadAuthTagLen));

    // Combine payload and tag for decryption
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

    // final ParametersWithIV<AEADParameters> params = ParametersWithIV(
    final params = AEADParameters(
        KeyParameter(srtpSessionKey), aeadAuthTagLen * 8, iv, headerBytes);
    // iv,
    // );

    srtpGCM.init(true, params); // true for encryption

    // The AAD (Additional Authenticated Data) is the RTP header
    // srtpGCM.aad = headerBytes;

    final Uint8List encryptedPayload = srtpGCM.process(plaintext);

    // The GCM process function returns the ciphertext followed by the authentication tag.
    // We need to combine the header, the encrypted payload, and the authentication tag.
    final Uint8List ciphertextWithAuthTag =
        Uint8List.fromList(encryptedPayload);

    // The final SRTP packet structure is:
    // RTP Header | Encrypted RTP Payload | Authentication Tag
    final Uint8List result =
        Uint8List.fromList(headerBytes + ciphertextWithAuthTag);
    return result;
  }

  // Corresponds to aesCmKeyDerivation in Go
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

// extension GCMEncrypt on GCM {
//   Future<Uint8List> encrypt(Packet packet, int roc) async {
//     final Uint8List plaintext = packet.payload;
//     final int aeadAuthTagLen =
//         16; // Defined in protectionprofiles.go for AES_128_GCM

//     final Uint8List iv = _rtpInitializationVector(packet.header, roc);

//     final Uint8List headerBytes =
//         Uint8List.fromList(packet.rawData.sublist(0, packet.headerSize));

//     final ParametersWithIV<AEADParameters> params = ParametersWithIV(
//       AEADParameters(KeyParameter(Uint8List(0)), aeadAuthTagLen * 8, iv),
//       iv,
//     );

//     srtpGCM.init(true, params); // true for encryption

//     // The AAD (Additional Authenticated Data) is the RTP header
//     srtpGCM.aad = headerBytes;

//     final Uint8List encryptedPayload = srtpGCM.process(plaintext);

//     // The GCM process function returns the ciphertext followed by the authentication tag.
//     // We need to combine the header, the encrypted payload, and the authentication tag.
//     final Uint8List ciphertextWithAuthTag =
//         Uint8List.fromList(encryptedPayload);

//     // The final SRTP packet structure is:
//     // RTP Header | Encrypted RTP Payload | Authentication Tag
//     final Uint8List result =
//         Uint8List.fromList(headerBytes + ciphertextWithAuthTag);
//     return result;
//   }
// }
