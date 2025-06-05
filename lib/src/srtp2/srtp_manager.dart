// lib/srtp/srtpmanager.dart
import 'dart:io';
import 'dart:typed_data';

import 'protection_profiles.dart';
import 'srtp_context.dart';

// You would define your logging utility here if needed
// import 'package:webrtc_nuts_and_bolts/src/logging.dart';

class SRTPManager {
  SRTPManager();

  SRTPContext newContext(
      InternetAddress addr, RawDatagramSocket conn, ProtectionProfile protectionProfile) {
    return SRTPContext(
      addr: addr,
      conn: conn,
      protectionProfile: protectionProfile,
    );
  }

  EncryptionKeys _extractEncryptionKeys(
      ProtectionProfile protectionProfile, Uint8List keyingMaterial) {
    final int keyLength = protectionProfile.keyLength();
    final int saltLength = protectionProfile.saltLength();

    int offset = 0;
    final Uint8List clientMasterKey = Uint8List.fromList(keyingMaterial.sublist(offset, offset + keyLength));
    offset += keyLength;
    final Uint8List serverMasterKey = Uint8List.fromList(keyingMaterial.sublist(offset, offset + keyLength));
    offset += keyLength;
    final Uint8List clientMasterSalt = Uint8List.fromList(keyingMaterial.sublist(offset, offset + saltLength));
    offset += saltLength;
    final Uint8List serverMasterSalt = Uint8List.fromList(keyingMaterial.sublist(offset, offset + saltLength));

    return EncryptionKeys(
      clientMasterKey: clientMasterKey,
      clientMasterSalt: clientMasterSalt,
      serverMasterKey: serverMasterKey,
      serverMasterSalt: serverMasterSalt,
    );
  }

  Future<void> initCipherSuite(
      SRTPContext context, Uint8List keyingMaterial) async {
    // logging.Descf(logging.ProtoSRTP, "Initializing SRTP Cipher Suite...");
    print("Initializing SRTP Cipher Suite..."); // Placeholder for logging

    final EncryptionKeys keys =
        _extractEncryptionKeys(context.protectionProfile, keyingMaterial);

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
        "Extracted encryption keys from keying material (${keyingMaterial.length} bytes) [protection profile ${context.protectionProfile}]\n\tClientMasterKey: 0x${keys.clientMasterKey.map((e) => e.toRadixString(16).padLeft(2, '0')).join()} (${keys.clientMasterKey.length} bytes)\n\tClientMasterSalt: 0x${keys.clientMasterSalt.map((e) => e.toRadixString(16).padLeft(2, '0')).join()} (${keys.clientMasterSalt.length} bytes)\n\tServerMasterKey: 0x${keys.serverMasterKey.map((e) => e.toRadixString(16).padLeft(2, '0')).join()} (${keys.serverMasterKey.length} bytes)\n\tServerMasterSalt: 0x${keys.serverMasterSalt.map((e) => e.toRadixString(16).padLeft(2, '0')).join()} (${keys.serverMasterSalt.length} bytes)");

    // logging.Descf(
    //     logging.ProtoSRTP, "Initializing GCM using ClientMasterKey and ClientMasterSalt");
    print("Initializing GCM using ClientMasterKey and ClientMasterSalt");

    final gcm = await initGCM(keys.clientMasterKey, keys.clientMasterSalt);
    context.gcm = gcm;
  }
}

// Analyze this snippet to create a main function usage example:

// func (ms *UDPClientSocket) OnDTLSStateChangeEvent(dtlsState dtls.DTLSState) {

//     logging.Infof(logging.ProtoDTLS, "State Changed: <u>%s</u> [<u>%v:%v</u>].\n", dtlsState, ms.HandshakeContext.Addr.IP, ms.HandshakeContext.Addr.Port)

//     switch dtlsState {

//     case dtls.DTLSStateConnected:

//         logging.Descf(logging.ProtoDTLS, "DTLS Handshake succeeded. Will be waiting for SRTP packets, but before them, we should init SRTP context and SRTP cipher suite, with SRTP Protection Profile <u>%s</u>.", ms.HandshakeContext.SRTPProtectionProfile)

//         ms.SRTPContext = srtpManager.NewContext(ms.Addr, ms.Conn, srtp.ProtectionProfile(ms.HandshakeContext.SRTPProtectionProfile))

//         keyLength, err := ms.SRTPContext.ProtectionProfile.KeyLength()

//         if err != nil {

//             panic(err)

//         }

//         saltLength, err := ms.SRTPContext.ProtectionProfile.SaltLength()

//         if err != nil {

//             panic(err)

//         }

//         logging.Descf(logging.ProtoDTLS, "We should generate keying material from DTLS context. Key length: %d, Salt Length: %d, Total bytes length (consists of client and server key-salt pairs): <u>%d</u>", keyLength, saltLength, keyLength*2+saltLength*2)

//         keyingMaterial, err := ms.HandshakeContext.ExportKeyingMaterial(keyLength*2 + saltLength*2)

//         if err != nil {

//             panic(err)

//         }

//         srtpManager.InitCipherSuite(ms.SRTPContext, keyingMaterial)

//     }

// }
