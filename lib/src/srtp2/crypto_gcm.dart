// lib/srtp/cryptogcm.dart
import 'dart:typed_data';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'constants.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/digests/sha1.dart';

class GCM {
  late GCMBlockCipher srtpGCM;
  late GCMBlockCipher srtcpGCM;
  late Uint8List srtpSalt;
  late Uint8List srtcpSalt;
  late Uint8List srtpSessionKey;
  late Uint8List srtcpSessionKey;

  GCM._(); // Private constructor

  static Future<GCM> newGCM(Uint8List masterKey, Uint8List masterSalt) async {
    final gcm = GCM._();

    gcm.srtpSessionKey = await gcm._aesCmKeyDerivation(
        labelSRTPEncryption, masterKey, masterSalt, 0, masterKey.length);
    gcm.srtpSalt = await gcm._aesCmKeyDerivation(
        labelSRTPSalt, masterKey, masterSalt, 0, masterSalt.length);

    final srtpBlockCipher = AESEngine();
    gcm.srtpGCM = GCMBlockCipher(srtpBlockCipher);

    gcm.srtcpSessionKey = await gcm._aesCmKeyDerivation(
        labelSRTCPEncryption, masterKey, masterSalt, 0, masterKey.length);
    gcm.srtcpSalt = await gcm._aesCmKeyDerivation(
        labelSRTCPSalt, masterKey, masterSalt, 0, masterSalt.length);

    final srtcpBlockCipher = AESEngine();
    gcm.srtcpGCM = GCMBlockCipher(srtcpBlockCipher);

    return gcm;
  }

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
        Uint8List(outLen); // Use outLen directly for AES-CM output size

    // AES-CM key derivation process (simplified for now, actual PRF required)
    // This part would typically involve a PRF (Pseudo-random function) based on AES-CM.
    // For demonstration, we'll use a basic HMAC-SHA1 which is not the standard for AES-CM PRF,
    // but serves as a placeholder. A proper implementation would use AES-CM's PRF.
    final hmac = HMac(SHA1Digest(), 64);
    hmac.init(KeyParameter(masterKey));
    hmac.update(prfIn, 0, prfIn.length);
    final hmacOutput = hmac.process(Uint8List(0)); // Pass empty Uint8List for no additional data

    // Take the first `outLen` bytes from the HMAC output as the derived key/salt
    out.setAll(0, hmacOutput.sublist(0, outLen));

    return out;
  }

  Uint8List getSRTPKey() {
    return srtpSessionKey;
  }

  Uint8List getSRTPSalt() {
    return srtpSalt;
  }

  Uint8List getSRTCPKey() {
    return srtcpSessionKey;
  }

  Uint8List getSRTCPSalt() {
    return srtcpSalt;
  }

  /// Encrypts an SRTP payload.
  /// [key]: The SRTP session key.
  /// [salt]: The SRTP session salt.
  /// [roc]: The rollover counter.
  /// [sequenceNumber]: The RTP sequence number.
  /// [header]: The RTP header (used as AAD in AES-GCM).
  /// [payload]: The RTP payload to encrypt.
  /// [authTagLength]: The length of the authentication tag (e.g., 16 for AES-GCM).
  Uint8List encrypt(Uint8List key, Uint8List salt, int roc, int sequenceNumber,
      Uint8List header, Uint8List payload, int authTagLength) {
    final Uint8List nonce = Uint8List(12); // GCM nonce is 12 bytes

    // Construct the 96-bit (12-byte) GCM nonce (RFC 7714, Section 3.3)
    // Salt (96 bits / 12 bytes) XOR (ROC (32 bits) | Sequence Number (16 bits) | 0x0000 (48 bits))
    final ByteData saltView = salt.buffer.asByteData();
    final ByteData nonceView = nonce.buffer.asByteData();

    // Salt (96 bits)
    for (int i = 0; i < 12; i++) {
      nonceView.setUint8(i, saltView.getUint8(i));
    }

    // ROC (32 bits) - XOR with bytes 4-7 of nonce
    nonceView.setUint32(4, nonceView.getUint32(4) ^ roc, Endian.big);

    // Sequence Number (16 bits) - XOR with bytes 10-11 of nonce
    nonceView.setUint16(10, nonceView.getUint16(10) ^ sequenceNumber, Endian.big);


    final gcmCipher = GCMBlockCipher(AESEngine());
    final ParametersWithAAD<KeyParameter> params =
        ParametersWithAAD(KeyParameter(key), authTagLength * 8, header); // Auth tag length in bits
    gcmCipher.init(true, params); // true for encryption

    final Uint8List encryptedPayload =
        Uint8List(payload.length + (authTagLength ~/ 8)); // Allocate space for payload + tag
    
    int bytesProcessed = gcmCipher.processBytes(
        payload, 0, payload.length, encryptedPayload, 0);

    // The GCM processBytes method includes the authentication tag at the end of the output.
    return encryptedPayload.sublist(0, bytesProcessed);
  }

  /// Decrypts an SRTP payload.
  /// [key]: The SRTP session key.
  /// [salt]: The SRTP session salt.
  /// [roc]: The rollover counter.
  /// [sequenceNumber]: The RTP sequence number.
  /// [header]: The RTP header (used as AAD in AES-GCM).
  /// [encryptedPayloadWithTag]: The encrypted RTP payload including the authentication tag.
  /// [authTagLength]: The length of the authentication tag (e.g., 16 for AES-GCM).
  Uint8List decrypt(Uint8List key, Uint8List salt, int roc, int sequenceNumber,
      Uint8List header, Uint8List encryptedPayloadWithTag, int authTagLength) {
    final Uint8List nonce = Uint8List(12);

    // Construct the 96-bit (12-byte) GCM nonce (RFC 7714, Section 3.3)
    final ByteData saltView = salt.buffer.asByteData();
    final ByteData nonceView = nonce.buffer.asByteData();

    for (int i = 0; i < 12; i++) {
      nonceView.setUint8(i, saltView.getUint8(i));
    }
    nonceView.setUint32(4, nonceView.getUint32(4) ^ roc, Endian.big);
    nonceView.setUint16(10, nonceView.getUint16(10) ^ sequenceNumber, Endian.big);

    final gcmCipher = GCMBlockCipher(AESEngine());
    final ParametersWithAAD<KeyParameter> params =
        ParametersWithAAD(KeyParameter(key), authTagLength * 8, header);
    gcmCipher.init(false, params); // false for decryption

    final Uint8List decryptedPayload =
        Uint8List(encryptedPayloadWithTag.length - authTagLength);

    try {
      int bytesProcessed = gcmCipher.processBytes(encryptedPayloadWithTag, 0,
          encryptedPayloadWithTag.length, decryptedPayload, 0);
      return decryptedPayload.sublist(0, bytesProcessed);
    } on ArgumentError catch (e) {
      if (e.message == 'mac check in GCM failed') {
        throw Exception('SRTP authentication failed: MAC check failed');
      }
      rethrow;
    }
  }
}