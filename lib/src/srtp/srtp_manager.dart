import 'dart:io';
import 'dart:typed_data';

import 'package:dartls/src/srtp/srtp_context.dart';

import 'protection_profiles.dart';

class SRTPManager {
  SRTPContext newContext(
      RawDatagramSocket conn, ProtectionProfile protectionProfile) {
    // return SRTPContext{
    // 	Addr:              addr,
    // 	Conn:              conn,
    // 	ProtectionProfile: protectionProfile,
    // 	srtpSSRCStates:    map[uint32]*srtpSSRCState{},
    // }
    return SRTPContext(conn, protectionProfile, {});
  }

  EncryptionKeys extractEncryptionKeys(
      ProtectionProfile protectionProfile, Uint8List keyingMaterial) {
    // https://github.com/pion/srtp/blob/82008b58b1e7be7a0cb834270caafacc7ba53509/keying.go#L14
    final keyLength = protectionProfile.keyLength();
    // if err != nil {
    // 	return nil, err
    // }
    final saltLength = protectionProfile.saltLength();
    // if err != nil {
    // 	return nil, err
    // }

    int offset = 0;
    final clientMasterKey = keyingMaterial.sublist(offset, offset + keyLength);
    offset += keyLength;
    final serverMasterKey = keyingMaterial.sublist(offset, offset + keyLength);
    offset += keyLength;
    final clientMasterSalt =
        keyingMaterial.sublist(offset, offset + saltLength);
    offset += saltLength;
    final serverMasterSalt =
        keyingMaterial.sublist(offset, offset + saltLength);

    return EncryptionKeys(
      clientMasterKey,
      clientMasterSalt,
      serverMasterKey,
      serverMasterSalt,
    );
  }

  bool? initCipherSuite(SRTPContext context, Uint8List keyingMaterial) {
    // logging.Descf(logging.ProtoSRTP, "Initializing SRTP Cipher Suite...")
    final keys =
        extractEncryptionKeys(context.protectionProfile, keyingMaterial);
    // if err != nil {
    // 	return err
    // }
    // logging.Descf(logging.ProtoSRTP, "Extracted encryption keys from keying material (<u>%d bytes</u>) [protection profile <u>%s</u>]\n\tClientMasterKey: <u>0x%x</u> (<u>%d bytes</u>)\n\tClientMasterSalt: <u>0x%x</u> (<u>%d bytes</u>)\n\tServerMasterKey: <u>0x%x</u> (<u>%d bytes</u>)\n\tServerMasterSalt: <u>0x%x</u> (<u>%d bytes</u>)",
    // 	len(keyingMaterial), context.ProtectionProfile,
    // 	keys.ClientMasterKey, len(keys.ClientMasterKey),
    // 	keys.ClientMasterSalt, len(keys.ClientMasterSalt),
    // 	keys.ServerMasterKey, len(keys.ServerMasterKey),
    // 	keys.ServerMasterSalt, len(keys.ServerMasterSalt))
    // logging.Descf(logging.ProtoSRTP, "Initializing GCM using ClientMasterKey and ClientMasterSalt")
    final gcm = initGCM(keys.clientMasterKey, keys.clientMasterSalt);
    // if err != nil {
    // 	return err
    // }
    context.gcm = gcm;
    return null;
  }
}
