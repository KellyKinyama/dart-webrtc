import 'dart:typed_data';

import 'package:dartls/src/srtp/crypto_gcm.dart';

// typedef ProtectionProfile = int;

// const (
final ProtectionProfile ProtectionProfile_AEAD_AES_128_GCM =
    ProtectionProfile(0x0007);

// )
class ProtectionProfile {
  int protectionProfile = 0x0007;

  ProtectionProfile(this.protectionProfile);

  int keyLength() {
    switch (protectionProfile) {
      case 0x0007:
        return 16;
    }

    throw "unknown protection profile: $protectionProfile";
  }

  int saltLength() {
    switch (protectionProfile) {
      case 0x0007:
        return 12;
    }

    throw "unknown protection profile: $protectionProfile";
  }

  int aeadAuthTagLength() {
    switch (protectionProfile) {
      case 0x0007:
        return 16;
    }

    throw "unknown protection profile: $protectionProfile";
  }
}

class EncryptionKeys {
  Uint8List serverMasterKey;
  Uint8List serverMasterSalt;
  Uint8List clientMasterKey;
  Uint8List clientMasterSalt;

  EncryptionKeys(this.serverMasterKey, this.serverMasterSalt,
      this.clientMasterKey, this.clientMasterSalt);
}

// func (p ProtectionProfile) String() string {
// 	var result string
// 	switch p {
// 	case ProtectionProfile_AEAD_AES_128_GCM:
// 		result = "SRTP_AEAD_AES_128_GCM"
// 	default:
// 		result = "Unknown SRTP Protection Profile"
// 	}
// 	return fmt.Sprintf("%s (0x%04x)", result, uint16(p))
// }

// func (p ProtectionProfile) KeyLength() (int, error) {
// 	switch p {
// 	case ProtectionProfile_AEAD_AES_128_GCM:
// 		return 16, nil
// 	}
// 	return 0, fmt.Errorf("unknown protection profile: %d", p)
// }

// func (p ProtectionProfile) SaltLength() (int, error) {
// 	switch p {
// 	case ProtectionProfile_AEAD_AES_128_GCM:
// 		return 12, nil
// 	}
// 	return 0, fmt.Errorf("unknown protection profile: %d", p)
// }

// func (p ProtectionProfile) AeadAuthTagLength() (int, error) {
// 	switch p {
// 	case ProtectionProfile_AEAD_AES_128_GCM:
// 		return 16, nil
// 	}
// 	return 0, fmt.Errorf("unknown protection profile: %d", p)
// }

GCM initGCM(Uint8List masterKey, Uint8List masterSalt) {
  final gcm = GCM.newGCM(masterKey, masterSalt);
  // if err != nil {
  // 	return nil, err
  // }
  return gcm;
}
