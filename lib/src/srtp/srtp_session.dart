// lib/srtp/srtpmanager.dart
import 'dart:typed_data';

import 'protection_profiles.dart';
import 'rtp2.dart';
import 'srtp_context.dart';
import 'crypto_gcm.dart';

// You would define your logging utility here if needed
// import 'package:webrtc_nuts_and_bolts/src/logging.dart';

class SRTPSession {
  ProtectionProfile protectionProfile = ProtectionProfile.aes_128_gcm;

  late SRTPContext localContext;
  late SRTPContext remoteContext;

  SRTPSession() {
    localContext = SRTPContext(protectionProfile: protectionProfile);
    remoteContext = SRTPContext(protectionProfile: protectionProfile);
  }
  SRTPContext newContext(
      //InternetAddress addr, RawDatagramSocket conn,
      ProtectionProfile protectionProfile) {
    return SRTPContext(
      // addr: addr,
      // conn: conn,
      protectionProfile: protectionProfile,
    );
  }

  EncryptionKeys _extractEncryptionKeys(Uint8List keyingMaterial) {
    final int keyLength = protectionProfile.keyLength();
    final int saltLength = protectionProfile.saltLength();

    int offset = 0;
    final Uint8List clientMasterKey =
        Uint8List.fromList(keyingMaterial.sublist(offset, offset + keyLength));
    offset += keyLength;
    final Uint8List serverMasterKey =
        Uint8List.fromList(keyingMaterial.sublist(offset, offset + keyLength));
    offset += keyLength;
    final Uint8List clientMasterSalt =
        Uint8List.fromList(keyingMaterial.sublist(offset, offset + saltLength));
    offset += saltLength;
    final Uint8List serverMasterSalt =
        Uint8List.fromList(keyingMaterial.sublist(offset, offset + saltLength));

    return EncryptionKeys(
      clientMasterKey: clientMasterKey,
      clientMasterSalt: clientMasterSalt,
      serverMasterKey: serverMasterKey,
      serverMasterSalt: serverMasterSalt,
    );
  }

  Future<void> initCipherSuite(Uint8List keyingMaterial) async {
    // logging.Descf(logging.ProtoSRTP, "Initializing SRTP Cipher Suite...");
    print("Initializing SRTP Cipher Suite..."); // Placeholder for logging

    final EncryptionKeys keys = _extractEncryptionKeys(keyingMaterial);

    // logging.Descf(
    //     logging.ProtoSRTP,
    //     "Extracted encryption keys from keying material (%d bytes) [protection profile %s]\n\tClientMasterKey: 0x%x (%d bytes)\n\tClientMasterSalt: 0x%x (%d bytes)\n\tServerMasterKey: 0x%x (%d bytes)\n\tServerMasterSalt: 0x%x (%d bytes)",
    //     keyingMaterial.length,
    //     context.protectionProfile,
    //     keys.clientMasterKey,
    //     keys.clientMasterKey.length,
    //     keys.clientMasterSalt,
    //     keys.clientMasterSalt.length,
    //     keys.serverMasterKey,
    //     keys.serverMasterKey.length,
    //     keys.serverMasterSalt,
    //     keys.serverMasterSalt.length);
    print(
        "Extracted encryption keys from keying material (${keyingMaterial.length} bytes) [protection profile $protectionProfile]\n\tClientMasterKey: 0x${keys.clientMasterKey.map((e) => e.toRadixString(16).padLeft(2, '0')).join()} (${keys.clientMasterKey.length} bytes)\n\tClientMasterSalt: 0x${keys.clientMasterSalt.map((e) => e.toRadixString(16).padLeft(2, '0')).join()} (${keys.clientMasterSalt.length} bytes)\n\tServerMasterKey: 0x${keys.serverMasterKey.map((e) => e.toRadixString(16).padLeft(2, '0')).join()} (${keys.serverMasterKey.length} bytes)\n\tServerMasterSalt: 0x${keys.serverMasterSalt.map((e) => e.toRadixString(16).padLeft(2, '0')).join()} (${keys.serverMasterSalt.length} bytes)");

    localContext.gcm =
        await GCM.newGCM(keys.clientMasterKey, keys.clientMasterSalt);
    remoteContext.gcm =
        await GCM.newGCM(keys.serverMasterKey, keys.serverMasterSalt);
  }

  Future<Uint8List> decryptRtpPacket(Uint8List encryptedRTPPacket) async {
    final packet = Packet.unmarshal(encryptedRTPPacket);
    return await localContext.decryptRtpPacket(packet);
  }

  Future<Uint8List> encryptRtpPacket(Uint8List decryptedRTPPacket) async {
    final packet = Packet.unmarshal(decryptedRTPPacket);
    return await remoteContext.encryptRtpPacket(packet);
  }
}
