import 'dart:typed_data';
import 'crypto_gcm.dart'; // Assuming cryptogcm.dart is in the same package

/// Which side of the DTLS-SRTP exchange this endpoint plays.
///
/// Sending uses the *local* write key/salt and receiving uses the *remote*
/// write key/salt:
///
///   * `client`: outbound = clientMasterKey/Salt, inbound = serverMasterKey/Salt
///   * `server`: outbound = serverMasterKey/Salt, inbound = clientMasterKey/Salt
enum SrtpRole { client, server }

enum ProtectionProfile {
  aes_128_gcm(0x0007, "SRTP_AEAD_AES_128_GCM");

  final int value;
  final String description;

  const ProtectionProfile(this.value, this.description);

  factory ProtectionProfile.fromValue(int value) {
    return ProtectionProfile.values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw Exception("Unknown SRTP Protection Profile: $value"),
    );
  }

  @override
  String toString() {
    return '$description (0x${value.toRadixString(16).padLeft(4, '0')})';
  }

  int keyLength() {
    switch (this) {
      case ProtectionProfile.aes_128_gcm:
        return 16;
    }
  }

  int saltLength() {
    switch (this) {
      case ProtectionProfile.aes_128_gcm:
        return 12;
    }
  }

  int aeadAuthTagLength() {
    switch (this) {
      case ProtectionProfile.aes_128_gcm:
        return 16;
    }
  }
}

class EncryptionKeys {
  final Uint8List serverMasterKey;
  final Uint8List serverMasterSalt;
  final Uint8List clientMasterKey;
  final Uint8List clientMasterSalt;

  EncryptionKeys({
    required this.serverMasterKey,
    required this.serverMasterSalt,
    required this.clientMasterKey,
    required this.clientMasterSalt,
  });
}

Future<GCM> initGCM(Uint8List masterKey, Uint8List masterSalt) async {
  return GCM.newGCM(masterKey, masterSalt);
}
