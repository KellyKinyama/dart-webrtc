import 'dart:typed_data';
import 'constants.dart'; // For common constants
import 'cipher_suites.dart'; // For CipherSuiteIdentifier
// Dependencies to be filled later (e.g., for digest contexts)
// import 'digest.dart'; 
// import 'x509.dart';
// import 'dh.dart';
// import 'ecc.dart';


// From tls.h: typedef enum { connection_end_client, connection_end_server } ConnectionEnd;
enum ConnectionEnd {
  client,
  server,
}

// From tls.h: typedef struct { unsigned char major, minor; } ProtocolVersion;
class ProtocolVersion {
  int major;
  int minor;

  ProtocolVersion({required this.major, required this.minor});

  factory ProtocolVersion.tls12() {
    return ProtocolVersion(major: TLS_VERSION_MAJOR, minor: TLS_VERSION_MINOR);
  }

  Uint8List toBytes() {
    return Uint8List.fromList([major, minor]);
  }

  static ProtocolVersion fromBytes(Uint8List bytes, int offset) {
    if (bytes.length < offset + 2) {
      throw ArgumentError("Not enough bytes for ProtocolVersion");
    }
    return ProtocolVersion(major: bytes[offset], minor: bytes[offset + 1]);
  }

  @override
  String toString() => '$major.$minor';
}

// From tls.h: typedef struct { unsigned int gmt_unix_time; unsigned char random_bytes[28]; } Random;
class TlsRandom {
  int gmtUnixTime; // 32-bit unsigned integer
  Uint8List randomBytes; // 28 bytes

  TlsRandom({required this.gmtUnixTime, required this.randomBytes}) {
    if (randomBytes.length != 28) {
      throw ArgumentError("Random bytes must be 28 bytes long.");
    }
  }

  factory TlsRandom.generate() {
    final random = Random.secure();
    final bytes = Uint8List(28);
    for (int i = 0; i < 28; i++) {
      bytes[i] = random.nextInt(256);
    }
    return TlsRandom(
      gmtUnixTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      randomBytes: bytes,
    );
  }

  Uint8List toBytes() {
    final bytes = ByteData(RANDOM_LENGTH); // 32 bytes
    bytes.setUint32(0, gmtUnixTime, Endian.big);
    for (int i = 0; i < 28; i++) {
      bytes.setUint8(4 + i, randomBytes[i]);
    }
    return bytes.buffer.asUint8List();
  }

  static TlsRandom fromBytes(Uint8List bytes, int offset) {
    if (bytes.length < offset + RANDOM_LENGTH) {
      throw ArgumentError("Not enough bytes for TlsRandom");
    }
    final byteData = ByteData.view(bytes.buffer, bytes.offsetInBytes + offset, RANDOM_LENGTH);
    return TlsRandom(
      gmtUnixTime: byteData.getUint32(0, Endian.big),
      randomBytes: bytes.sublist(offset + 4, offset + RANDOM_LENGTH),
    );
  }
}

// From tls.h: typedef struct { unsigned char type; ProtocolVersion version; unsigned short length; } TLSPlaintext;
class TlsPlaintextHeader {
  int type; // ContentType
  ProtocolVersion version;
  int length; // Length of the fragment

  TlsPlaintextHeader({required this.type, required this.version, required this.length});

  Uint8List toBytes() {
    final bytes = ByteData(5);
    bytes.setUint8(0, type);
    bytes.setUint8(1, version.major);
    bytes.setUint8(2, version.minor);
    bytes.setUint16(3, length, Endian.big);
    return bytes.buffer.asUint8List();
  }

  static TlsPlaintextHeader fromBytes(Uint8List bytes, int offset) {
    if (bytes.length < offset + 5) {
      throw ArgumentError("Not enough bytes for TlsPlaintextHeader");
    }
    return TlsPlaintextHeader(
      type: bytes[offset],
      version: ProtocolVersion(major: bytes[offset + 1], minor: bytes[offset + 2]),
      length: ByteData.view(bytes.buffer).getUint16(bytes.offsetInBytes + offset + 3, Endian.big),
    );
  }
}

// From tls.h: typedef struct { unsigned char level; unsigned char description; } Alert;
class TlsAlert {
  int level; // AlertLevel
  int description; // AlertDescription

  TlsAlert({required this.level, required this.description});

  Uint8List toBytes() {
    return Uint8List.fromList([level, description]);
  }

  static TlsAlert fromBytes(Uint8List bytes, int offset) {
    if (bytes.length < offset + 2) {
      throw ArgumentError("Not enough bytes for TlsAlert");
    }
    return TlsAlert(level: bytes[offset], description: bytes[offset + 1]);
  }
  
  @override
  String toString() {
    String levelStr;
    switch (level) {
      case AlertLevel.warning: levelStr = "Warning"; break;
      case AlertLevel.fatal: levelStr = "Fatal"; break;
      default: levelStr = "UnknownLevel($level)"; break;
    }
    String descStr;
    // Add cases for all AlertDescription constants
    switch (description) {
        case AlertDescription.closeNotify: descStr = "CloseNotify"; break;
        case AlertDescription.unexpectedMessage: descStr = "UnexpectedMessage"; break;
        case AlertDescription.badRecordMac: descStr = "BadRecordMac"; break;
        // ... other descriptions
        default: descStr = "UnknownDescription($description)"; break;
    }
    return "Alert: $levelStr - $descStr";
  }
}

// From tls.h: typedef struct { unsigned char msg_type; unsigned int length; } Handshake; (length is 24 bits)
class HandshakeHeader {
  int msgType; // HandshakeType
  int length; // 24-bit length of the handshake message body

  HandshakeHeader({required this.msgType, required this.length});

  Uint8List toBytes() {
    final bytes = ByteData(4);
    bytes.setUint8(0, msgType);
    bytes.setUint8(1, (length >> 16) & 0xFF); // msb
    bytes.setUint8(2, (length >> 8) & 0xFF);  // middle byte
    bytes.setUint8(3, length & 0xFF);         // lsb
    return bytes.buffer.asUint8List();
  }

  static HandshakeHeader fromBytes(Uint8List bytes, int offset) {
    if (bytes.length < offset + 4) {
      throw ArgumentError("Not enough bytes for HandshakeHeader");
    }
    return HandshakeHeader(
      msgType: bytes[offset],
      length: (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3],
    );
  }
}

// From tls.h: ClientHello structure
class ClientHello {
  ProtocolVersion clientVersion;
  TlsRandom random;
  Uint8List sessionId; // Length is sessionId.length (0-32)
  List<int> cipherSuites; // List of CipherSuiteIDs (each 2 bytes)
  List<int> compressionMethods; // List of compression methods (each 1 byte)
  Uint8List? extensions; // Optional extensions block

  ClientHello({
    required this.clientVersion,
    required this.random,
    required this.sessionId,
    required this.cipherSuites,
    required this.compressionMethods,
    this.extensions,
  });

  // toBytes and fromBytes methods would be complex due to variable lengths
  // and would be implemented in the tls_core.dart where message construction/parsing happens.
}

// From tls.h: ServerHello structure
class ServerHello {
  ProtocolVersion serverVersion;
  TlsRandom random;
  Uint8List sessionId; // session_id_length followed by session_id
  int cipherSuite; // Selected CipherSuiteID (2 bytes)
  int compressionMethod; // Selected compression method (1 byte)
  Uint8List? extensions; // Optional extensions block (TLS 1.0+)

  ServerHello({
    required this.serverVersion,
    required this.random,
    required this.sessionId,
    required this.cipherSuite,
    required this.compressionMethod,
    this.extensions,
  });
    // toBytes and fromBytes methods would be complex and implemented in tls_core.dart
}


// From tls.h: ProtectionParameters
class ProtectionParameters {
  Uint8List? macSecret;
  Uint8List? key;
  Uint8List? iv; // For CBC mode, this is the IV. For stream ciphers like RC4, it might hold state. For AEAD, it's the nonce.
  CipherSuiteIdentifier suite;
  BigInt seqNum; // Sequence number (64-bit)

  ProtectionParameters({
    this.macSecret,
    this.key,
    this.iv,
    required this.suite,
    BigInt? sequenceNum,
  }) : seqNum = sequenceNum ?? BigInt.zero;

  // Helper to create an initial (null) state
  factory ProtectionParameters.initial() {
    return ProtectionParameters(suite: CipherSuiteID.TLS_NULL_WITH_NULL_NULL);
  }

  void resetSequenceNumber() {
    seqNum = BigInt.zero;
  }

  void incrementSequenceNumber() {
    seqNum += BigInt.one;
  }

  // Note: In C, IV could be a pointer to RC4 state. In Dart, if RC4 is used,
  // the 'iv' field might hold an instance of an RC4State class.
  // For AEAD ciphers, this 'iv' would be the nonce.
}

// Placeholder for public key info, will be detailed when x509.dart is created
class PublicKeyInfo {
  // Details depend on algorithm (RSA, DSA, ECDSA)
  // For now, just a placeholder
  late final AlgorithmIdentifier algorithm;
  // rsa_key rsaPublicKey;
  // dsa_params dsaParameters;
  // BigInt dsaPublicKey;
  // EllipticCurve ecdsaCurve;
  // ECPoint ecdsaPublicKey;

  PublicKeyInfo(); // Placeholder constructor
}
enum AlgorithmIdentifier { rsa, dsa, dh, ecdsa }


// Placeholder for DH key, will be detailed when dh.dart is created
class DhKey {
  // BigInt p, g, y; // Public components
  DhKey(); // Placeholder
}

// Placeholder for ECC curve and point, will be detailed when ecc.dart is created
class EllipticCurve {
  // BigInt p, a, b, n;
  // ECPoint G;
  EllipticCurve(); // Placeholder
}

class ECPoint {
  // BigInt x, y;
  ECPoint(); // Placeholder
}

// DigestContext placeholder - will be replaced by actual digest implementation
// from package:crypto or a custom one if needed.
typedef DigestContext = List<int>; // Simplified placeholder

// Function signature for creating a new digest
typedef NewDigestFunction = DigestContext Function();


// ExtensionType from tls.c (internal enum)
class ExtensionType {
  static const int serverName = 0;
  static const int secureRenegotiation = 0xFF01;
  // Other extension types can be added here
}

// SignatureAndHashAlgorithm from tls.c (for CertificateRequest)
class SignatureAndHashAlgorithm {
  final int hash; // HashAlgorithm enum
  final int signature; // SignatureAlgorithm enum

  SignatureAndHashAlgorithm({required this.hash, required this.signature});

  Uint8List toBytes() => Uint8List.fromList([hash, signature]);

  static SignatureAndHashAlgorithm fromBytes(Uint8List bytes, int offset) {
    if (bytes.length < offset + 2) throw ArgumentError("Not enough bytes for SignatureAndHashAlgorithm");
    return SignatureAndHashAlgorithm(hash: bytes[offset], signature: bytes[offset+1]);
  }
}

// CertificateRequest structure from tls.c
class CertificateRequestMessage {
  List<int> certificateTypes; // e.g., rsa_sign, dss_sign
  List<SignatureAndHashAlgorithm> supportedSignatureAlgorithms;
  List<Uint8List> certificateAuthorities; // List of DER-encoded X.500 names

  CertificateRequestMessage({
    required this.certificateTypes,
    required this.supportedSignatureAlgorithms,
    required this.certificateAuthorities,
  });
  // toBytes and fromBytes would be implemented in tls_core.dart
}

// Certificate types for CertificateRequest
class ClientCertificateType {
  static const int rsaSign = 1;
  static const int dssSign = 2;
  static const int rsaFixedDh = 3;
  static const int dssFixedDh = 4;
  static const int rsaFixedEcdh = 5; // From RFC 4492
  static const int ecdsaFixedEcdh = 6; // From RFC 4492
  // ... other types from RFC 5246, RFC 8422
  static const int ecdsaSign = 64; // From RFC 4492 / RFC 8422
  static const int rsaPssRsaeSha256 = 65; // From RFC 8446 (TLS 1.3)
  static const int rsaPssPssSha256 = 66; // From RFC 8446 (TLS 1.3)
}


