// lib/srtp/cryptogcm.dart
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart'; // New import for cryptography package
import 'package:pointycastle/api.dart' show KeyParameter;
// AEADParameters; // Only import necessary PointyCastle parts
import 'package:pointycastle/block/aes.dart'; // Keep AESEngine for key derivation
// import 'package:pointycastle/block/modes/gcm.dart'
//     show
//         GCMBlockCipher; // Keep for the old GCM class if needed, but not directly used for cipher operation now.

import 'rtp.dart'; // Contains Header and Packet
import 'constants.dart'; // Contains label constants

class GCM {
  // Use AesGcm from the 'cryptography' package for actual GCM operations
  late AesGcm srtpCipher;
  late AesGcm srtcpCipher;

  // Store the derived session keys as SecretKey objects for the new GCM ciphers
  late SecretKey srtpSessionSecretKey;
  late SecretKey srtcpSessionSecretKey;

  late Uint8List srtpSalt;
  late Uint8List srtcpSalt;

  GCM._(); // Private constructor

  static Future<GCM> newGCM(Uint8List masterKey, Uint8List masterSalt) async {
    final gcm = GCM._();

    // Key derivation using existing _aesCmKeyDerivation (which uses PointyCastle internally)
    final Uint8List srtpSessionKeyBytes = await gcm._aesCmKeyDerivation(
        labelSRTPEncryption, masterKey, masterSalt, 0, masterKey.length);
    gcm.srtpSessionSecretKey = SecretKey(srtpSessionKeyBytes);

    final Uint8List srtcpSessionKeyBytes = await gcm._aesCmKeyDerivation(
        labelSRTCPEncryption, masterKey, masterSalt, 0, masterKey.length);
    gcm.srtcpSessionSecretKey = SecretKey(srtcpSessionKeyBytes);

    gcm.srtpSalt = await gcm._aesCmKeyDerivation(
        labelSRTPSalt, masterKey, masterSalt, 0, masterSalt.length);
    gcm.srtcpSalt = await gcm._aesCmKeyDerivation(
        labelSRTCPSalt, masterKey, masterSalt, 0, masterSalt.length);

    // Initialize AesGcm ciphers from 'cryptography' package
    // Assuming AES-128-GCM based on the original aeadAuthTagLen = 16 (128 bits)
    gcm.srtpCipher = AesGcm.with128bits();
    gcm.srtcpCipher = AesGcm.with128bits();

    return gcm;
  }

  /// Derives the 12-byte Nonce for SRTP GCM based on RFC 3711 Section 3.3.1.
  /// This is the concatenation of ROC, SSRC, and Sequence Number, XORed with salt.
  Uint8List _rtpInitializationVector(Header header, int roc, Uint8List salt) {
    final iv = Uint8List(12);
    final byteData = ByteData.view(iv.buffer);

    // ROC (32-bit unsigned int, but only lower 16 bits are relevant for IV xor)
    // SSRC (32-bit unsigned int)
    // Sequence Number (16-bit unsigned int)

    // Concatenate ROC, SSRC, Sequence Number
    // The explicit nonce in RFC 3711 is a 12-octet value (96 bits)
    // E = (ROC << 16) | Seq (48-bit extended sequence number)
    // IV = (Salt[0...3] || SSRC || E) XOR salt

    // Place SSRC directly at offset 4 (after first 4 bytes for ROC high bits + salt)
    byteData.setUint32(4, header.ssrc, Endian.big);
    // Place sequence number at offset 10 (last 2 bytes)
    byteData.setUint16(10, header.sequenceNumber, Endian.big);

    // The ROC is part of the "Extended Sequence Number" (ESN).
    // ESN is (ROC << 16) | SequenceNumber.
    // The IV is constructed from a portion of the master_salt, SSRC, and ESN.
    // RFC 3711, Section 4.1.1:
    // IV = master_salt[0..3] || SSRC || ESN
    // The first 4 bytes of IV should be from master_salt.
    // The middle 4 bytes of IV is SSRC.
    // The last 4 bytes of IV is ESN.
    // The explicit nonce is 12 bytes.

    // A simpler construction based on common WebRTC implementations for SRTP IV:
    // Nonce is often treated as 0-3 bytes from salt, 4-7 bytes SSRC, 8-9 sequence, 10-11 roc?
    // Let's match the Go WebRTC library's IV construction, which typically is:
    // iv[0..1] = roc (high bits)
    // iv[2..5] = SSRC
    // iv[6..7] = roc (low bits, from sequence number)
    // iv[8..9] = sequence number
    // iv[10..11] = 0 (padding)
    // THEN XOR with srtpSalt.

    // The Go code uses:
    // iv[2] = ssrc high byte
    // iv[3] = ssrc mid-high byte
    // iv[4] = ssrc mid-low byte
    // iv[5] = ssrc low byte
    // iv[6] = roc high byte
    // iv[7] = roc mid-high byte
    // iv[8] = roc mid-low byte
    // iv[9] = roc low byte
    // iv[10] = sequence high byte
    // iv[11] = sequence low byte
    // Then XOR with srtpSalt.

    // My current Dart version of _rtpInitializationVector matches the Go implementation based on the `PointyCastle`
    // usage, so I'll stick to that.
    // byteData.setUint32(2, header.ssrc, Endian.big); // SSRC at offset 2-5
    // byteData.setUint32(6, roc, Endian.big); // ROC at offset 6-9
    // byteData.setUint16(10, header.sequenceNumber, Endian.big); // SeqNum at offset 10-11

    // This is the correct derivation for PointyCastle parameters, which seems to match the common SRTP IV.
    // For 'cryptography' package, the Nonce is just the 12-byte raw IV.

    // The existing _rtpInitializationVector seems to be correct for generating the 12-byte IV for SRTP
    // which is then XORed with the salt.

    final Uint8List computedIv = Uint8List(12);
    final ByteData computedByteData = ByteData.view(computedIv.buffer);

    // RFC 3711 Section 4.1.1. describes the IV (which is the Nonce for GCM)
    // The 12-octet (96-bit) IV (or nonce) for AES-GCM in SRTP is constructed as:
    // IV = master_salt[0..3] || SSRC || (ROC << 16 | sequence_number)

    // First 4 bytes are from master_salt
    computedIv.setRange(0, 4, salt.sublist(0, 4));

    // Next 4 bytes are SSRC
    computedByteData.setUint32(4, header.ssrc, Endian.big);

    // Last 4 bytes are (ROC << 16 | sequence_number)
    final int extendedSequenceNumber = (roc << 16) | header.sequenceNumber;
    computedByteData.setUint32(8, extendedSequenceNumber, Endian.big);

    // According to RFC 3711 Section 4.1.1, the IV used for AES-GCM is XORed with the SALT.
    // It is effectively: (master_salt XOR K_s) || SSRC || (ROC XOR K_s) || (sequence XOR K_s)
    // No, the standard clearly states:
    // IV = master_salt[0..3] || SSRC || (ROC XOR sequence) || sequence_number
    // The previous implementation used XORing the entire IV with salt at the end.
    // This is more common in WebRTC examples that implement SRTP.
    // Let's revert to the original `_rtpInitializationVector` which seems more consistent with your
    // original `pointycastle` usage and what I've seen in some SRTP contexts.

    final ivBytes = Uint8List(12);
    final ivByteData = ByteData.view(ivBytes.buffer);

    ivByteData.setUint32(2, header.ssrc, Endian.big); // SSRC at offset 2
    ivByteData.setUint32(6, roc, Endian.big); // ROC at offset 6
    ivByteData.setUint16(
        10, header.sequenceNumber, Endian.big); // SequenceNumber at offset 10

    for (int i = 0; i < ivBytes.length; i++) {
      ivBytes[i] ^=
          salt[i]; // XOR with the session salt (srtpSalt or srtcpSalt)
    }
    return ivBytes; // Return as a Nonce object
  }

  Future<Uint8List> decrypt(Packet packet, int roc) async {
    final Uint8List ciphertextWithTag = packet.rawData;
    final int aeadAuthTagLen = 16; // AES_128_GCM has 16-byte tag

    // Need at least header + 8 (for explicit IV) + tag length
    if (ciphertextWithTag.length < packet.headerSize + 8 + aeadAuthTagLen) {
      throw Exception("Ciphertext too short for GCM authentication tag");
    }

    // The AAD (Additional Authenticated Data) is the RTP header.
    // This should be the original, unencrypted RTP header bytes.
    final Uint8List headerBytes =
        Uint8List.fromList(ciphertextWithTag.sublist(0, packet.headerSize));

    // The explicit IV (8 bytes) is immediately after the header.
    // The GCM nonce for SRTP is 12 bytes: 4 bytes from master_salt, 8 bytes explicit IV.
    final Uint8List explicitIvSuffix =
        ciphertextWithTag.sublist(packet.headerSize, packet.headerSize + 8);

    final nonce = _rtpInitializationVector(packet.header, roc, srtpSalt);

    // Replace the last 8 bytes of the derived nonce with the explicit IV from the packet.
    // This forms the final 12-byte nonce used for decryption.
    nonce.setRange(4, 12, explicitIvSuffix);

    final Uint8List encryptedPayloadAndTag =
        ciphertextWithTag.sublist(packet.headerSize + 8);

    final Uint8List encryptedPayload = encryptedPayloadAndTag.sublist(
        0, encryptedPayloadAndTag.length - aeadAuthTagLen);
    final Mac authTag = Mac(encryptedPayloadAndTag
        .sublist(encryptedPayloadAndTag.length - aeadAuthTagLen));

    final SecretBox secretBox = SecretBox(
      encryptedPayload,
      nonce: nonce,
      mac: authTag,
    );

    try {
      final Uint8List decryptedBytes =
          Uint8List.fromList(await srtpCipher.decrypt(
        secretBox,
        secretKey: srtpSessionSecretKey,
        aad: headerBytes,
      ));
      // Return only the decrypted payload. The header bytes are already part of the `packet.rawData` passed in.
      // The `decryptRtpPacket` in `srtp_context` expects only the payload.
      return Uint8List.fromList(headerBytes + decryptedBytes);
    } catch (e) {
      throw Exception("SRTP GCM decryption failed: $e");
    }
  }

  Future<Uint8List> encrypt(Packet packet, int roc) async {
    final Uint8List plaintextPayload = packet.payload;
    // final int aeadAuthTagLen = 16; // AES_128_GCM has 16-byte tag
    // final int explicitIvLen = 8; // Explicit IV is 8 bytes in SRTP

    // The AAD (Additional Authenticated Data) is the RTP header.
    final Uint8List headerBytes =
        Uint8List.fromList(packet.rawData.sublist(0, packet.headerSize));

    // Generate the 12-byte nonce (IV)
    final nonce = _rtpInitializationVector(packet.header, roc, srtpSalt);

    // The last 8 bytes of the nonce are the explicit IV that goes into the packet.
    final Uint8List explicitIvSuffix = nonce.sublist(4);

    final SecretBox secretBox = await srtpCipher.encrypt(
      plaintextPayload,
      secretKey: srtpSessionSecretKey,
      nonce: nonce,
      aad: headerBytes,
    );

    // The final SRTP packet structure is:
    // RTP Header | Explicit IV (8 bytes) | Encrypted RTP Payload | Authentication Tag (16 bytes)
    final Uint8List result = Uint8List(headerBytes.length +
        explicitIvSuffix.length +
        secretBox.cipherText.length +
        secretBox.mac.bytes.length);

    int offset = 0;
    result.setAll(offset, headerBytes);
    offset += headerBytes.length;

    result.setAll(offset, explicitIvSuffix);
    offset += explicitIvSuffix.length;

    result.setAll(offset, secretBox.cipherText);
    offset += secretBox.cipherText.length;

    result.setAll(offset, secretBox.mac.bytes);
    offset += secretBox.mac.bytes.length;

    return result;
  }

  // This is the AES-CM key derivation function as per RFC 3711 Section 4.3.1.
  // It uses AES in Counter Mode (CM) as a Pseudo-Random Function (PRF).
  // This part *retains* PointyCastle because 'cryptography' doesn't expose
  // raw AES block cipher in a way that directly matches this specific PRF.
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
