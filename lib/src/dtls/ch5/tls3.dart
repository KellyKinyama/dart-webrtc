// x509_certificate_parser.dart

import 'dart:typed_data';
import 'dart:convert'; // For utf8 and base64
import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/md5.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/asymmetric/dsa.dart';
import 'package:pointycastle/signers/rsa_signer.dart';
import 'package:pointycastle/signers/dsa_signer.dart';
import 'package:pointycastle/ecc/api.dart'; // For ECPublicKey, ECPrivateKey, ECCurve_base
import 'package:pointycastle/ecc/curves/secp256r1.dart'; // Example curve

// --- ASN.1 Core (Simplified from previous turn, integrated for self-containment) ---

/// Represents an ASN.1 TLV (Tag, Length, Value) structure.
class Asn1Token {
  final bool constructed;
  final int tagClass;
  final int tag;
  final int length;
  final Uint8List data; // Raw bytes of the value (or the whole TLV if constructed)
  final List<Asn1Token>? children;

  Asn1Token({
    required this.constructed,
    required this.tagClass,
    required this.tag,
    required this.length,
    required this.data,
    this.children,
  });

  @override
  String toString() {
    String tagName = '';
    if (tagClass == Asn1Constants.ASN1_CLASS_UNIVERSAL) {
      tagName = Asn1Constants.universalTagNames[tag] ?? 'UNKNOWN($tag)';
    } else {
      tagName = 'Context Specific($tag)';
    }
    return '$tagName (T:$tag, L:$length, Constructed: $constructed)';
  }
}

/// Constants for ASN.1 Tags and Classes.
class Asn1Constants {
  // ASN.1 Tag Classes
  static const int ASN1_CLASS_UNIVERSAL = 0;
  static const int ASN1_CLASS_APPLICATION = 1;
  static const int ASN1_CONTEXT_SPECIFIC = 2;
  static const int ASN1_PRIVATE = 3;

  // ASN.1 Universal Tags
  static const int ASN1_BOOLEAN = 1;
  static const int ASN1_INTEGER = 2;
  static const int ASN1_BIT_STRING = 3;
  static const int ASN1_OCTET_STRING = 4;
  static const int ASN1_NULL = 5;
  static const int ASN1_OBJECT_IDENTIFIER = 6;
  static const int ASN1_SEQUENCE = 16;
  static const int ASN1_SET = 17;
  static const int ASN1_PRINTABLE_STRING = 19;
  static const int ASN1_TELETEX_STRING = 20; // T61String
  static const int ASN1_IA5_STRING = 22;
  static const int ASN1_UTC_TIME = 23;
  static const int ASN1_GENERALIZED_TIME = 24;
  static const int ASN1_UTF8_STRING = 12; // Added from C file

  static const Map<int, String> universalTagNames = {
    ASN1_BOOLEAN: "BOOLEAN",
    ASN1_INTEGER: "INTEGER",
    ASN1_BIT_STRING: "BIT STRING",
    ASN1_OCTET_STRING: "OCTET STRING",
    ASN1_NULL: "NULL",
    ASN1_OBJECT_IDENTIFIER: "OBJECT IDENTIFIER",
    ASN1_SEQUENCE: "SEQUENCE",
    ASN1_SET: "SET",
    ASN1_PRINTABLE_STRING: "PrintableString",
    ASN1_TELETEX_STRING: "TeletexString / T61String",
    ASN1_IA5_STRING: "IA5String",
    ASN1_UTC_TIME: "UTCTime",
    ASN1_GENERALIZED_TIME: "GeneralizedTime",
    ASN1_UTF8_STRING: "UTF8String",
    // Add others as needed from asn1.h
  };
}

/// Utility for parsing ASN.1 DER encoded data.
class Asn1Parser {
  /// Parses a DER encoded byte buffer into an Asn1Token tree.
  static Asn1Token parse(Uint8List buffer, [int offset = 0]) {
    int currentOffset = offset;
    if (currentOffset >= buffer.length) {
      throw FormatException("Buffer exhausted while parsing ASN.1 token.");
    }

    int tagByte = buffer[currentOffset++];
    int tag = tagByte & 0x1F; // Lower 5 bits for universal tags
    bool constructed = (tagByte & 0x20) != 0; // Bit 6
    int tagClass = (tagByte & 0xC0) >> 6;    // Bits 7-8

    if (tag == 0x1F) { // High tag number form (tags > 30)
      tag = 0;
      while (currentOffset < buffer.length && (buffer[currentOffset] & 0x80) != 0) {
        tag = (tag << 7) | (buffer[currentOffset++] & 0x7F);
      }
      if (currentOffset >= buffer.length) {
        throw FormatException("Buffer exhausted while parsing high tag number.");
      }
      tag = (tag << 7) | (buffer[currentOffset++] & 0x7F); // Last byte of high tag
    }

    if (currentOffset >= buffer.length) {
      throw FormatException("Buffer exhausted while parsing ASN.1 length.");
    }
    int lengthByte = buffer[currentOffset++];
    int length;

    if ((lengthByte & 0x80) == 0) { // Short form length
      length = lengthByte;
    } else { // Long form length
      int numLengthBytes = lengthByte & 0x7F;
      if (numLengthBytes == 0) {
        throw FormatException("Indefinite length encoding not supported for DER.");
      }
      if (numLengthBytes > 4) { // Prevent excessively large length bytes
        throw FormatException("Length encoding too large: $numLengthBytes bytes.");
      }
      if (currentOffset + numLengthBytes > buffer.length) {
        throw FormatException("Buffer exhausted while parsing long form length.");
      }
      length = 0;
      for (int i = 0; i < numLengthBytes; i++) {
        length = (length << 8) | buffer[currentOffset++];
      }
    }

    if (currentOffset + length > buffer.length) {
      throw FormatException("ASN.1 value extends beyond buffer boundary. Expected $length bytes, but only ${buffer.length - currentOffset} available.");
    }
    Uint8List data = Uint8List.sublistView(buffer, currentOffset, currentOffset + length);

    List<Asn1Token>? children;
    if (constructed) {
      children = [];
      int childrenParsedLength = 0;
      while (childrenParsedLength < length) {
        try {
          Asn1Token childToken = parse(data, childrenParsedLength);
          children.add(childToken);
          childrenParsedLength += (childToken.length + _getHeaderLength(childToken));
        } on FormatException catch (e) {
          print("Warning: Malformed child ASN.1 token at offset $childrenParsedLength within constructed type. Error: $e");
          break; // Stop parsing children for this token if malformed
        } catch (e) {
          print("Warning: Unexpected error parsing child at offset $childrenParsedLength: $e");
          break;
        }
      }
    }

    return Asn1Token(
      constructed: constructed,
      tagClass: tagClass,
      tag: tag,
      length: length,
      data: data,
      children: children,
    );
  }

  /// Helper to calculate the full TLV length (Tag + Length + Value).
  static int _getHeaderLength(Asn1Token token) {
    int headerLen = 1; // For tag byte
    if (token.length < 128) {
      headerLen += 1; // For short form length byte
    } else {
      headerLen += 1 + ((token.length.bitLength + 7) ~/ 8);
    }
    return headerLen;
  }

  /// Decodes an Object Identifier (OID) from its byte representation to a dot-separated string.
  static String decodeOid(Uint8List oidBytes) {
    if (oidBytes.isEmpty) return "";

    List<int> components = [];
    int firstByte = oidBytes[0];
    components.add(firstByte ~/ 40);
    components.add(firstByte % 40);

    int i = 1;
    while (i < oidBytes.length) {
      int value = 0;
      while (i < oidBytes.length && (oidBytes[i] & 0x80) != 0) {
        value = (value << 7) | (oidBytes[i] & 0x7F);
        i++;
      }
      if (i < oidBytes.length) {
        value = (value << 7) | (oidBytes[i] & 0x7F);
        components.add(value);
        i++;
      } else {
        break; // Malformed OID
      }
    }
    return components.join('.');
  }
}

/// Utility for Base64 and Hex encoding/decoding.
class ConverterUtils {
  /// Decodes a PEM-encoded string (e.g., certificate) to raw DER bytes.
  static Uint8List decodePemToDer(Uint8List pemBuffer) {
    String pemString = utf8.decode(pemBuffer);
    List<String> lines = pemString.split('\n');
    StringBuffer base64Content = StringBuffer();
    bool inCertBlock = false;

    for (String line in lines) {
      line = line.trim();
      if (line.startsWith('-----BEGIN CERTIFICATE-----')) {
        inCertBlock = true;
        continue;
      }
      if (line.startsWith('-----END CERTIFICATE-----')) {
        inCertBlock = false;
        break;
      }
      if (inCertBlock) {
        base64Content.write(line.replaceAll('\r', ''));
      }
    }
    if (base64Content.isEmpty) {
      throw FormatException("No certificate block found in PEM data.");
    }
    return base64Decode(base64Content.toString());
  }

  /// Encodes bytes to a hexadecimal string.
  static String bytesToHex(Uint8List bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Decodes a hexadecimal string to bytes.
  static Uint8List hexToBytes(String hexString) {
    if (hexString.length % 2 != 0) {
      throw FormatException("Hex string must have an even length.");
    }
    List<int> bytes = [];
    for (int i = 0; i < hexString.length; i += 2) {
      bytes.add(int.parse(hexString.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }
}

// --- X.509 Data Structures (Dart idiomatic) ---

/// Represents the algorithm used for a public key.
enum PublicKeyAlgorithm { rsaEncryption, dsa, ecPublicKey, unknown }

/// Represents the signature algorithm used in a certificate.
enum SignatureAlgorithm {
  md5WithRSAEncryption,
  sha1WithRSAEncryption,
  sha1WithDSA,
  sha256WithECDSA,
  unknown
}

/// Represents an X.500 Distinguished Name (e.g., Issuer or Subject).
class X500Name {
  String? countryName;
  String? stateOrProvinceName;
  String? localityName;
  String? organizationName;
  String? organizationalUnitName;
  String? commonName;

  X500Name({
    this.countryName,
    this.stateOrProvinceName,
    this.localityName,
    this.organizationName,
    this.organizationalUnitName,
    this.commonName,
  });

  @override
  String toString() {
    List<String> parts = [];
    if (commonName != null) parts.add('CN=$commonName');
    if (organizationalUnitName != null) parts.add('OU=$organizationalUnitName');
    if (organizationName != null) parts.add('O=$organizationName');
    if (localityName != null) parts.add('L=$localityName');
    if (stateOrProvinceName != null) parts.add('ST=$stateOrProvinceName');
    if (countryName != null) parts.add('C=$countryName');
    return parts.join(', ');
  }
}

/// Represents the validity period of a certificate.
class ValidityPeriod {
  final DateTime notBefore;
  final DateTime notAfter;

  ValidityPeriod({required this.notBefore, required this.notAfter});
}

/// Represents RSA public key components.
class RsaPublicKey {
  final BigInt modulus;
  final BigInt exponent;

  RsaPublicKey({required this.modulus, required this.exponent});
}

/// Represents DSA parameters (p, q, g).
class DsaParameters {
  final BigInt p;
  final BigInt q;
  final BigInt g;

  DsaParameters({required this.p, required this.q, required this.g});
}

/// Represents DSA signature components (r, s).
class DsaSignature {
  final BigInt r;
  final BigInt s;

  DsaSignature({required this.r, required this.s});
}

/// Represents an Elliptic Curve (e.g., for ECDSA).
/// This is a simplified representation. A full implementation would use PointyCastle's ECCurve_base.
class EcCurve {
  final String name; // e.g., "secp256r1"
  final BigInt p; // Prime modulus
  final BigInt a; // Curve parameter a
  final BigInt b; // Curve parameter b
  final BigInt n; // Order of the base point
  final ECPoint G; // Base point G

  EcCurve({
    required this.name,
    required this.p,
    required this.a,
    required this.b,
    required this.n,
    required this.G,
  });
}

/// Represents an Elliptic Curve public key point.
class EcPublicKeyPoint {
  final BigInt x;
  final BigInt y;

  EcPublicKeyPoint({required this.x, required this.y});
}

/// Represents public key information, including algorithm and key components.
class SubjectPublicKeyInfo {
  final PublicKeyAlgorithm algorithm;
  final RsaPublicKey? rsaPublicKey;
  final DsaParameters? dsaParameters;
  final BigInt? dsaPublicKeyY; // DSA 'y' component
  final EcCurve? ecCurve;
  final EcPublicKeyPoint? ecPublicKeyPoint;

  SubjectPublicKeyInfo({
    required this.algorithm,
    this.rsaPublicKey,
    this.dsaParameters,
    this.dsaPublicKeyY,
    this.ecCurve,
    this.ecPublicKeyPoint,
  });
}

/// Represents the "To Be Signed" (TBS) portion of an X.509 certificate.
class TbsCertificate {
  final int version;
  final BigInt serialNumber;
  final SignatureAlgorithm signatureAlgorithm;
  final X500Name issuer;
  final ValidityPeriod validity;
  final X500Name subject;
  final SubjectPublicKeyInfo subjectPublicKeyInfo;
  final Uint8List? issuerUniqueId; // Optional
  final Uint8List? subjectUniqueId; // Optional
  final bool isCertificateAuthority; // From KeyUsage extension
  final Uint8List rawBytes; // Raw bytes of the TBS section for hashing

  TbsCertificate({
    required this.version,
    required this.serialNumber,
    required this.signatureAlgorithm,
    required this.issuer,
    required this.validity,
    required this.subject,
    required this.subjectPublicKeyInfo,
    this.issuerUniqueId,
    this.subjectUniqueId,
    this.isCertificateAuthority = false,
    required this.rawBytes,
  });
}

/// Represents a fully parsed X.509 certificate, including its signature.
class X509Certificate {
  final TbsCertificate tbsCertificate;
  final SignatureAlgorithm signatureAlgorithm; // Algorithm used for signing
  final BigInt? rsaSignatureValue; // For RSA signatures
  final DsaSignature? dsaSignatureValue; // For DSA signatures
  final ECSignature? ecSignatureValue; // For ECDSA signatures (PointyCastle type)
  final Uint8List? signatureHash; // Calculated hash of TBS certificate

  X509Certificate({
    required this.tbsCertificate,
    required this.signatureAlgorithm,
    this.rsaSignatureValue,
    this.dsaSignatureValue,
    this.ecSignatureValue,
    this.signatureHash,
  });

  /// Displays the certificate details to the console.
  void display() {
    print("X.509 Certificate Details:");
    print("  Version: ${tbsCertificate.version}");
    print("  Serial Number: ${tbsCertificate.serialNumber.toRadixString(16)}");
    print("  Signature Algorithm (Certificate): ${tbsCertificate.signatureAlgorithm}");
    print("  Issuer: ${tbsCertificate.issuer}");
    print("  Validity:");
    print("    Not Before: ${tbsCertificate.validity.notBefore.toIso8601String()} UTC");
    print("    Not After: ${tbsCertificate.validity.notAfter.toIso8601String()} UTC");
    print("  Subject: ${tbsCertificate.subject}");
    print("  Subject Public Key Info:");
    print("    Algorithm: ${tbsCertificate.subjectPublicKeyInfo.algorithm}");
    if (tbsCertificate.subjectPublicKeyInfo.rsaPublicKey != null) {
      print("      RSA Public Key:");
      print("        Modulus (n): ${tbsCertificate.subjectPublicKeyInfo.rsaPublicKey!.modulus.toRadixString(16)}");
      print("        Exponent (e): ${tbsCertificate.subjectPublicKeyInfo.rsaPublicKey!.exponent.toRadixString(16)}");
    } else if (tbsCertificate.subjectPublicKeyInfo.dsaParameters != null &&
        tbsCertificate.subjectPublicKeyInfo.dsaPublicKeyY != null) {
      print("      DSA Public Key:");
      print("        P: ${tbsCertificate.subjectPublicKeyInfo.dsaParameters!.p.toRadixString(16)}");
      print("        Q: ${tbsCertificate.subjectPublicKeyInfo.dsaParameters!.q.toRadixString(16)}");
      print("        G: ${tbsCertificate.subjectPublicKeyInfo.dsaParameters!.g.toRadixString(16)}");
      print("        Y: ${tbsCertificate.subjectPublicKeyInfo.dsaPublicKeyY!.toRadixString(16)}");
    } else if (tbsCertificate.subjectPublicKeyInfo.ecCurve != null &&
        tbsCertificate.subjectPublicKeyInfo.ecPublicKeyPoint != null) {
      print("      EC Public Key:");
      print("        Curve: ${tbsCertificate.subjectPublicKeyInfo.ecCurve!.name}");
      print("        Point (x): ${tbsCertificate.subjectPublicKeyInfo.ecPublicKeyPoint!.x.toRadixString(16)}");
      print("        Point (y): ${tbsCertificate.subjectPublicKeyInfo.ecPublicKeyPoint!.y.toRadixString(16)}");
    }
    if (tbsCertificate.issuerUniqueId != null) {
      print("  Issuer Unique ID: ${ConverterUtils.bytesToHex(tbsCertificate.issuerUniqueId!)}");
    }
    if (tbsCertificate.subjectUniqueId != null) {
      print("  Subject Unique ID: ${ConverterUtils.bytesToHex(tbsCertificate.subjectUniqueId!)}");
    }
    print("  Is Certificate Authority: ${tbsCertificate.isCertificateAuthority ? "Yes" : "No"}");

    print("  Signature Algorithm (Signed): $signatureAlgorithm");
    if (rsaSignatureValue != null) {
      print("    RSA Signature Value: ${rsaSignatureValue!.toRadixString(16)}");
    } else if (dsaSignatureValue != null) {
      print("    DSA Signature Value (r): ${dsaSignatureValue!.r.toRadixString(16)}");
      print("    DSA Signature Value (s): ${dsaSignatureValue!.s.toRadixString(16)}");
    } else if (ecSignatureValue != null) {
      print("    ECDSA Signature Value (r): ${ecSignatureValue!.r.toRadixString(16)}");
      print("    ECDSA Signature Value (s): ${ecSignatureValue!.s.toRadixString(16)}");
    }
    if (signatureHash != null) {
      print("  Calculated TBS Hash: ${ConverterUtils.bytesToHex(signatureHash!)}");
    }
  }
}

// --- X.509 Parsing and Validation Logic ---

class X509Parser {
  // Common OIDs
  static const String OID_MD5_WITH_RSA_ENCRYPTION = "1.2.840.113549.1.1.4";
  static const String OID_SHA1_WITH_RSA_ENCRYPTION = "1.2.840.113549.1.1.5";
  static const String OID_SHA1_WITH_DSA = "1.2.840.10040.4.3";
  static const String OID_SHA256_WITH_ECDSA = "1.2.840.10045.4.3.2";
  static const String OID_RSA_ENCRYPTION = "1.2.840.113549.1.1.1";
  static const String OID_DSA = "1.2.840.10040.4.1";
  static const String OID_EC_PUBLIC_KEY = "1.2.840.10045.2.1";

  // X.500 Name OIDs
  static const String OID_COUNTRY_NAME = "2.5.4.6";
  static const String OID_STATE_OR_PROVINCE_NAME = "2.5.4.8";
  static const String OID_LOCALITY_NAME = "2.5.4.7";
  static const String OID_ORGANIZATION_NAME = "2.5.4.10";
  static const String OID_ORGANIZATIONAL_UNIT_NAME = "2.5.4.11";
  static const String OID_COMMON_NAME = "2.5.4.3";

  // Extension OIDs
  static const String OID_KEY_USAGE = "2.5.29.15";
  static const int BIT_CERT_SIGNER = 5; // bit 5 (0-indexed) for keyCertSign

  /// Validates an ASN.1 token against expected tag and minimum number of children.
  static bool _validateNode(Asn1Token? source, int expectedTag, int minExpectedChildren, String desc) {
    if (source == null) {
      print("Error: '$desc' missing.");
      return false;
    }
    if (source.tag != expectedTag) {
      print("Error parsing '$desc'; expected tag $expectedTag, got ${source.tag}.");
      return false;
    }
    if (source.children == null || source.children!.length < minExpectedChildren) {
      print("Error parsing '$desc'; expected at least $minExpectedChildren children, got ${source.children?.length ?? 0}.");
      return false;
    }
    return true;
  }

  /// Parses an ASN.1 INTEGER token into a BigInt.
  static BigInt _parseBigInt(Asn1Token token) {
    if (!_validateNode(token, Asn1Constants.ASN1_INTEGER, 0, "Integer")) {
      throw FormatException("Invalid INTEGER token.");
    }
    return BigInt.fromBytes(token.data);
  }

  /// Parses an ASN.1 SEQUENCE representing an algorithm identifier.
  static PublicKeyAlgorithm _parsePublicKeyAlgorithm(Asn1Token algorithmToken) {
    if (!_validateNode(algorithmToken, Asn1Constants.ASN1_SEQUENCE, 1, "Public Key Algorithm Identifier")) {
      return PublicKeyAlgorithm.unknown;
    }
    Asn1Token oidToken = algorithmToken.children![0];
    if (!_validateNode(oidToken, Asn1Constants.ASN1_OBJECT_IDENTIFIER, 0, "Public Key Algorithm OID")) {
      return PublicKeyAlgorithm.unknown;
    }

    String oid = Asn1Parser.decodeOid(oidToken.data);
    switch (oid) {
      case OID_RSA_ENCRYPTION: return PublicKeyAlgorithm.rsaEncryption;
      case OID_DSA: return PublicKeyAlgorithm.dsa;
      case OID_EC_PUBLIC_KEY: return PublicKeyAlgorithm.ecPublicKey;
      default: return PublicKeyAlgorithm.unknown;
    }
  }

  /// Parses an ASN.1 SEQUENCE representing a signature algorithm identifier.
  static SignatureAlgorithm _parseSignatureAlgorithm(Asn1Token algorithmToken) {
    if (!_validateNode(algorithmToken, Asn1Constants.ASN1_SEQUENCE, 1, "Signature Algorithm Identifier")) {
      return SignatureAlgorithm.unknown;
    }
    Asn1Token oidToken = algorithmToken.children![0];
    if (!_validateNode(oidToken, Asn1Constants.ASN1_OBJECT_IDENTIFIER, 0, "Signature Algorithm OID")) {
      return SignatureAlgorithm.unknown;
    }

    String oid = Asn1Parser.decodeOid(oidToken.data);
    switch (oid) {
      case OID_MD5_WITH_RSA_ENCRYPTION: return SignatureAlgorithm.md5WithRSAEncryption;
      case OID_SHA1_WITH_RSA_ENCRYPTION: return SignatureAlgorithm.sha1WithRSAEncryption;
      case OID_SHA1_WITH_DSA: return SignatureAlgorithm.sha1WithDSA;
      case OID_SHA256_WITH_ECDSA: return SignatureAlgorithm.sha256WithECDSA;
      default: return SignatureAlgorithm.unknown;
    }
  }

  /// Parses an X.500 Name (Issuer or Subject).
  static X500Name _parseX500Name(Asn1Token nameToken) {
    X500Name name = X500Name();
    if (!_validateNode(nameToken, Asn1Constants.ASN1_SEQUENCE, 1, "Name")) {
      return name;
    }

    for (var rdnToken in nameToken.children!) {
      if (!_validateNode(rdnToken, Asn1Constants.ASN1_SET, 1, "Relative Distinguished Name (RDN)")) {
        continue;
      }
      for (var attrValueToken in rdnToken.children!) {
        if (!_validateNode(attrValueToken, Asn1Constants.ASN1_SEQUENCE, 2, "Attribute Type And Value")) {
          continue;
        }
        Asn1Token attrOidToken = attrValueToken.children![0];
        Asn1Token attrValueStringToken = attrValueToken.children![1];

        if (!_validateNode(attrOidToken, Asn1Constants.ASN1_OBJECT_IDENTIFIER, 0, "Attribute Type OID")) {
          continue;
        }

        String oid = Asn1Parser.decodeOid(attrOidToken.data);
        String value = utf8.decode(attrValueStringToken.data, allowMalformed: true);

        switch (oid) {
          case OID_COUNTRY_NAME: name.countryName = value; break;
          case OID_STATE_OR_PROVINCE_NAME: name.stateOrProvinceName = value; break;
          case OID_LOCALITY_NAME: name.localityName = value; break;
          case OID_ORGANIZATION_NAME: name.organizationName = value; break;
          case OID_ORGANIZATIONAL_UNIT_NAME: name.organizationalUnitName = value; break;
          case OID_COMMON_NAME: name.commonName = value; break;
          default:
            print("Warning: Unknown OID in X.500 Name: $oid with value '$value'");
            break;
        }
      }
    }
    return name;
  }

  /// Parses the Validity period (notBefore and notAfter dates).
  static ValidityPeriod _parseValidity(Asn1Token validityToken) {
    if (!_validateNode(validityToken, Asn1Constants.ASN1_SEQUENCE, 2, "Validity Period")) {
      throw FormatException("Invalid Validity Period token.");
    }

    Asn1Token notBeforeToken = validityToken.children![0];
    Asn1Token notAfterToken = validityToken.children![1];

    DateTime parseTime(Asn1Token timeToken) {
      String timeString = utf8.decode(timeToken.data);
      if (timeToken.tag == Asn1Constants.ASN1_UTC_TIME) {
        // YYMMDDHHMMSSZ or YYMMDDHHMMSS+-HHMM
        int year = int.parse(timeString.substring(0, 2));
        if (year >= 50) {
          year += 1900;
        } else {
          year += 2000;
        }
        String isoTime = "$year-${timeString.substring(2, 4)}-${timeString.substring(4, 6)}T"
                         "${timeString.substring(6, 8)}:${timeString.substring(8, 10)}:${timeString.substring(10, 12)}Z";
        return DateTime.parse(isoTime);
      } else if (timeToken.tag == Asn1Constants.ASN1_GENERALIZED_TIME) {
        // YYYYMMDDHHMMSSZ or YYYYMMDDHHMMSS.sZ or YYYYMMDDHHMMSS+-HHMM
        return DateTime.parse(timeString.replaceAll('Z', 'T') + 'Z');
      } else {
        throw FormatException("Unsupported time format tag: ${timeToken.tag}");
      }
    }

    return ValidityPeriod(
      notBefore: parseTime(notBeforeToken),
      notAfter: parseTime(notAfterToken),
    );
  }

  /// Parses the SubjectPublicKeyInfo structure.
  static SubjectPublicKeyInfo _parseSubjectPublicKeyInfo(Asn1Token pubKeyInfoToken) {
    if (!_validateNode(pubKeyInfoToken, Asn1Constants.ASN1_SEQUENCE, 2, "Subject Public Key Info")) {
      throw FormatException("Invalid Subject Public Key Info token.");
    }

    Asn1Token algorithmSeqToken = pubKeyInfoToken.children![0];
    Asn1Token publicKeyBitStringToken = pubKeyInfoToken.children![1];

    PublicKeyAlgorithm algorithm = _parsePublicKeyAlgorithm(algorithmSeqToken);

    if (!_validateNode(publicKeyBitStringToken, Asn1Constants.ASN1_BIT_STRING, 0, "Public Key Bit String")) {
      throw FormatException("Invalid Public Key Bit String token.");
    }

    // Extract the actual public key bytes by skipping the first byte (unused bits)
    Uint8List publicKeyBytes = Uint8List.sublistView(publicKeyBitStringToken.data, 1);

    RsaPublicKey? rsaPublicKey;
    DsaParameters? dsaParameters;
    BigInt? dsaPublicKeyY;
    EcCurve? ecCurve;
    EcPublicKeyPoint? ecPublicKeyPoint;

    if (algorithm == PublicKeyAlgorithm.rsaEncryption) {
      Asn1Token parsedPublicKeyToken = Asn1Parser.parse(publicKeyBytes);
      if (!_validateNode(parsedPublicKeyToken, Asn1Constants.ASN1_SEQUENCE, 2, "RSA Public Key")) {
        throw FormatException("Invalid RSA Public Key token.");
      }
      BigInt modulus = _parseBigInt(parsedPublicKeyToken.children![0]);
      BigInt exponent = _parseBigInt(parsedPublicKeyToken.children![1]);
      rsaPublicKey = RsaPublicKey(modulus: modulus, exponent: exponent);
    } else if (algorithm == PublicKeyAlgorithm.dsa) {
      // DSA parameters are often in the AlgorithmIdentifier sequence
      if (!_validateNode(algorithmSeqToken, Asn1Constants.ASN1_SEQUENCE, 2, "DSA Algorithm Sequence with Params")) {
        throw FormatException("DSA algorithm sequence missing parameters.");
      }
      Asn1Token dsaParamsSeq = algorithmSeqToken.children![1];
      if (!_validateNode(dsaParamsSeq, Asn1Constants.ASN1_SEQUENCE, 3, "DSA Parameters")) {
        throw FormatException("Invalid DSA parameters token.");
      }
      dsaParameters = DsaParameters(
        p: _parseBigInt(dsaParamsSeq.children![0]),
        q: _parseBigInt(dsaParamsSeq.children![1]),
        g: _parseBigInt(dsaParamsSeq.children![2]),
      );

      // The DSA public key 'y' is directly an INTEGER in the BIT STRING data
      Asn1Token parsedPublicKeyToken = Asn1Parser.parse(publicKeyBytes);
      if (!_validateNode(parsedPublicKeyToken, Asn1Constants.ASN1_INTEGER, 0, "DSA Public Key Y")) {
        throw FormatException("Invalid DSA Public Key Y token.");
      }
      dsaPublicKeyY = _parseBigInt(parsedPublicKeyToken);
    } else if (algorithm == PublicKeyAlgorithm.ecPublicKey) {
      // --- DUMMY IMPLEMENTATION FOR ECDSA PUBLIC KEY PARSING ---
      print("DUMMY: Parsing ECDSA public key. This needs full implementation.");
      // In a real implementation, you'd parse the curve OID from algorithmSeqToken.children[1]
      // and the ECPoint from publicKeyBytes.
      // For now, return a dummy curve and point.
      ecCurve = EcCurve(
        name: "secp256r1 (dummy)",
        p: BigInt.parse("FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF", radix: 16),
        a: BigInt.parse("FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFC", radix: 16),
        b: BigInt.parse("5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B", radix: 16),
        n: BigInt.parse("FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551", radix: 16),
        G: ECPoint(
          BigInt.parse("6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296", radix: 16),
          BigInt.parse("4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5", radix: 16),
        ),
      );
      ecPublicKeyPoint = EcPublicKeyPoint(
        x: BigInt.parse("1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF", radix: 16), // Dummy X
        y: BigInt.parse("FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210", radix: 16), // Dummy Y
      );
      // --- END DUMMY ---
    } else {
      print("Warning: Unsupported public key algorithm: $algorithm");
    }

    return SubjectPublicKeyInfo(
      algorithm: algorithm,
      rsaPublicKey: rsaPublicKey,
      dsaParameters: dsaParameters,
      dsaPublicKeyY: dsaPublicKeyY,
      ecCurve: ecCurve,
      ecPublicKeyPoint: ecPublicKeyPoint,
    );
  }

  /// Extracts a specific bit from a BIT STRING's data.
  static bool _getAsn1Bit(Uint8List data, int bitIndex) {
    if (data.isEmpty) return false;
    int unusedBits = data[0];
    int actualDataLen = data.length - 1;
    int totalBits = actualDataLen * 8 - unusedBits;

    if (bitIndex < 0 || bitIndex >= totalBits) {
      return false;
    }

    int byteIndex = (bitIndex ~/ 8) + 1; // +1 to skip unused_bits byte
    int bitOffsetInByte = bitIndex % 8;

    if (byteIndex >= data.length) return false;

    return ((data[byteIndex] >> (7 - bitOffsetInByte)) & 0x01) != 0;
  }

  /// Parses certificate extensions, specifically looking for KeyUsage.
  static bool _parseExtensions(Asn1Token extensionsOuterToken) {
    bool isCA = false;
    // Extensions are within a context-specific tag [3] and wrapped in an OCTET STRING
    if (!_validateNode(extensionsOuterToken, Asn1Constants.ASN1_CONTEXT_SPECIFIC, 1, "Extensions Outer (Context-Specific 3)")) {
      return false;
    }
    Asn1Token extensionsOctetString = extensionsOuterToken.children![0];
    if (!_validateNode(extensionsOctetString, Asn1Constants.ASN1_OCTET_STRING, 0, "Extensions Octet String")) {
      return false;
    }

    try {
      Asn1Token actualExtensionsSequence = Asn1Parser.parse(extensionsOctetString.data);
      if (!_validateNode(actualExtensionsSequence, Asn1Constants.ASN1_SEQUENCE, 1, "Actual Extensions Sequence")) {
        return false;
      }

      for (var extensionSeq in actualExtensionsSequence.children!) {
        if (!_validateNode(extensionSeq, Asn1Constants.ASN1_SEQUENCE, 2, "Extension")) {
          continue;
        }
        Asn1Token oidToken = extensionSeq.children![0];
        // Optional critical flag is children[1], actual value is children.last
        Asn1Token extValueOctetString = extensionSeq.children!.last;

        if (!_validateNode(oidToken, Asn1Constants.ASN1_OBJECT_IDENTIFIER, 0, "Extension OID")) {
          continue;
        }
        if (!_validateNode(extValueOctetString, Asn1Constants.ASN1_OCTET_STRING, 0, "Extension Value Octet String")) {
          continue;
        }

        String oid = Asn1Parser.decodeOid(oidToken.data);
        Uint8List extValueData = extValueOctetString.data;

        if (oid == OID_KEY_USAGE) {
          try {
            Asn1Token keyUsageBitString = Asn1Parser.parse(extValueData);
            if (!_validateNode(keyUsageBitString, Asn1Constants.ASN1_BIT_STRING, 0, "Key Usage Bit String")) {
              print("Warning: Invalid Key Usage Bit String format.");
              continue;
            }
            isCA = _getAsn1Bit(keyUsageBitString.data, BIT_CERT_SIGNER);
          } catch (e) {
            print("Warning: Failed to parse Key Usage extension: $e");
          }
        } else {
          print("Warning: Unhandled extension OID: $oid");
        }
      }
    } on FormatException catch (e) {
      print("Warning: Malformed extensions content: $e");
    } catch (e) {
      print("Warning: Unexpected error parsing extensions: $e");
    }
    return isCA;
  }

  /// Parses the "To Be Signed" (TBS) certificate section.
  static TbsCertificate _parseTbsCertificate(Asn1Token tbsCertificateToken) {
    if (!_validateNode(tbsCertificateToken, Asn1Constants.ASN1_SEQUENCE, 6, "TBS Certificate")) {
      throw FormatException("Invalid TBS Certificate token.");
    }

    int currentChildIndex = 0;
    int version = 1; // Default to v1

    // Version (optional, context-specific tag 0)
    if (tbsCertificateToken.children![0].tagClass == Asn1Constants.ASN1_CONTEXT_SPECIFIC &&
        tbsCertificateToken.children![0].tag == 0) {
      Asn1Token versionToken = tbsCertificateToken.children![0];
      if (!_validateNode(versionToken, 0, 1, "Version (Context-Specific 0)")) {
        throw FormatException("Invalid Version token.");
      }
      version = _parseBigInt(versionToken.children![0]).toInt() + 1; // 0 -> v1, 1 -> v2, 2 -> v3
      currentChildIndex++;
    }

    BigInt serialNumber = _parseBigInt(tbsCertificateToken.children![currentChildIndex++]);
    SignatureAlgorithm signatureAlgorithm = _parseSignatureAlgorithm(tbsCertificateToken.children![currentChildIndex++]);
    X500Name issuer = _parseX500Name(tbsCertificateToken.children![currentChildIndex++]);
    ValidityPeriod validity = _parseValidity(tbsCertificateToken.children![currentChildIndex++]);
    X500Name subject = _parseX500Name(tbsCertificateToken.children![currentChildIndex++]);
    SubjectPublicKeyInfo subjectPublicKeyInfo = _parseSubjectPublicKeyInfo(tbsCertificateToken.children![currentChildIndex++]);

    Uint8List? issuerUniqueId;
    Uint8List? subjectUniqueId;
    bool isCA = false;

    // Optional: issuerUniqueId (context-specific tag [1])
    if (tbsCertificateToken.children!.length > currentChildIndex &&
        tbsCertificateToken.children![currentChildIndex].tagClass == Asn1Constants.ASN1_CONTEXT_SPECIFIC &&
        tbsCertificateToken.children![currentChildIndex].tag == 1) {
      // Assuming it's a BIT STRING, data will contain unused bits + actual ID
      issuerUniqueId = tbsCertificateToken.children![currentChildIndex++].data;
    }
    // Optional: subjectUniqueId (context-specific tag [2])
    if (tbsCertificateToken.children!.length > currentChildIndex &&
        tbsCertificateToken.children![currentChildIndex].tagClass == Asn1Constants.ASN1_CONTEXT_SPECIFIC &&
        tbsCertificateToken.children![currentChildIndex].tag == 2) {
      // Assuming it's a BIT STRING, data will contain unused bits + actual ID
      subjectUniqueId = tbsCertificateToken.children![currentChildIndex++].data;
    }

    // Extensions (optional, context-specific tag [3])
    if (version >= 3 &&
        tbsCertificateToken.children!.length > currentChildIndex &&
        tbsCertificateToken.children![currentChildIndex].tagClass == Asn1Constants.ASN1_CONTEXT_SPECIFIC &&
        tbsCertificateToken.children![currentChildIndex].tag == 3) {
      Asn1Token extensionsOuterToken = tbsCertificateToken.children![currentChildIndex++];
      isCA = _parseExtensions(extensionsOuterToken);
    }

    return TbsCertificate(
      version: version,
      serialNumber: serialNumber,
      signatureAlgorithm: signatureAlgorithm,
      issuer: issuer,
      validity: validity,
      subject: subject,
      subjectPublicKeyInfo: subjectPublicKeyInfo,
      issuerUniqueId: issuerUniqueId,
      subjectUniqueId: subjectUniqueId,
      isCertificateAuthority: isCA,
      rawBytes: tbsCertificateToken.data,
    );
  }

  /// Parses the RSA signature value from a BIT STRING.
  static BigInt _parseRsaSignatureValue(Asn1Token signatureToken) {
    if (!_validateNode(signatureToken, Asn1Constants.ASN1_BIT_STRING, 0, "RSA Signature Value")) {
      throw FormatException("Invalid RSA Signature Value token.");
    }
    // Skip the unused bits byte (first byte)
    return BigInt.fromBytes(Uint8List.sublistView(signatureToken.data, 1));
  }

  /// Parses the DSA signature value (r, s) from a BIT STRING.
  static DsaSignature _parseDsaSignatureValue(Asn1Token signatureToken) {
    if (!_validateNode(signatureToken, Asn1Constants.ASN1_BIT_STRING, 0, "DSA Signature Value")) {
      throw FormatException("Invalid DSA Signature Value token.");
    }
    // DSA signature is a SEQUENCE of two INTEGERS (r and s)
    // inside the BIT STRING's data. Skip the unused bits byte.
    Uint8List dsaSigBytes = Uint8List.sublistView(signatureToken.data, 1);
    Asn1Token dsaSigSeq = Asn1Parser.parse(dsaSigBytes);

    if (!_validateNode(dsaSigSeq, Asn1Constants.ASN1_SEQUENCE, 2, "DSA Signature Sequence (r, s)")) {
      throw FormatException("Invalid DSA Signature Sequence.");
    }

    BigInt r = _parseBigInt(dsaSigSeq.children![0]);
    BigInt s = _parseBigInt(dsaSigSeq.children![1]);
    return DsaSignature(r: r, s: s);
  }

  /// Parses a complete X.509 certificate from DER encoded bytes.
  static X509Certificate parseCertificate(Uint8List derBytes) {
    Asn1Token certificateToken = Asn1Parser.parse(derBytes);

    if (!_validateNode(certificateToken, Asn1Constants.ASN1_SEQUENCE, 3, "Signed X.509 Certificate")) {
      throw FormatException("Invalid Signed X.509 Certificate structure.");
    }

    Asn1Token tbsCertificateToken = certificateToken.children![0];
    Asn1Token signatureAlgorithmToken = certificateToken.children![1];
    Asn1Token signatureValueToken = certificateToken.children![2];

    TbsCertificate tbsCertificate = _parseTbsCertificate(tbsCertificateToken);
    SignatureAlgorithm signatureAlgorithm = _parseSignatureAlgorithm(signatureAlgorithmToken);

    BigInt? rsaSignatureValue;
    DsaSignature? dsaSignatureValue;
    ECSignature? ecSignatureValue; // PointyCastle type

    switch (signatureAlgorithm) {
      case SignatureAlgorithm.md5WithRSAEncryption:
      case SignatureAlgorithm.sha1WithRSAEncryption:
        rsaSignatureValue = _parseRsaSignatureValue(signatureValueToken);
        break;
      case SignatureAlgorithm.sha1WithDSA:
        dsaSignatureValue = _parseDsaSignatureValue(signatureValueToken);
        break;
      case SignatureAlgorithm.sha256WithECDSA:
        // --- DUMMY IMPLEMENTATION FOR ECDSA SIGNATURE PARSING ---
        print("DUMMY: Parsing ECDSA signature. This needs full implementation.");
        // In a real implementation, you'd parse the r and s components from the BIT STRING
        // and create an ECSignature object.
        dsaSignatureValue = _parseDsaSignatureValue(signatureValueToken); // Reusing DSA parser for (r,s) sequence
        ecSignatureValue = ECSignature(dsaSignatureValue.r, dsaSignatureValue.s);
        // --- END DUMMY ---
        break;
      default:
        print("Warning: Unsupported signature algorithm for parsing value: $signatureAlgorithm");
    }

    // Calculate hash of TBS Certificate
    Digest digest;
    switch (signatureAlgorithm) {
      case SignatureAlgorithm.md5WithRSAEncryption:
        digest = MD5Digest();
        break;
      case SignatureAlgorithm.sha1WithRSAEncryption:
      case SignatureAlgorithm.sha1WithDSA:
        digest = SHA1Digest();
        break;
      case SignatureAlgorithm.sha256WithECDSA:
        digest = SHA256Digest();
        break;
      default:
        throw UnsupportedError("Hashing not supported for signature algorithm: $signatureAlgorithm");
    }
    Uint8List calculatedHash = digest.process(tbsCertificate.rawBytes);

    return X509Certificate(
      tbsCertificate: tbsCertificate,
      signatureAlgorithm: signatureAlgorithm,
      rsaSignatureValue: rsaSignatureValue,
      dsaSignatureValue: dsaSignatureValue,
      ecSignatureValue: ecSignatureValue,
      signatureHash: calculatedHash,
    );
  }

  /// Validates an RSA signature.
  /// This assumes PKCS#1 v1.5 padding scheme as implied by the C code's `rsa_decrypt`
  /// and typical X.509 certificate signatures.
  static bool validateRsaSignature(X509Certificate certificate) {
    if (certificate.rsaSignatureValue == null || certificate.signatureHash == null) {
      print("RSA validation failed: Missing signature value or hash.");
      return false;
    }
    if (certificate.tbsCertificate.subjectPublicKeyInfo.rsaPublicKey == null) {
      print("RSA validation failed: RSA public key not found in certificate.");
      return false;
    }

    final rsaPublicParams = RSAPublicKey(
      certificate.tbsCertificate.subjectPublicKeyInfo.rsaPublicKey!.modulus,
      certificate.tbsCertificate.subjectPublicKeyInfo.rsaPublicKey!.exponent,
    );

    Digest hashDigest;
    switch (certificate.signatureAlgorithm) {
      case SignatureAlgorithm.md5WithRSAEncryption:
        hashDigest = MD5Digest();
        break;
      case SignatureAlgorithm.sha1WithRSAEncryption:
        hashDigest = SHA1Digest();
        break;
      default:
        print("RSA validation failed: Unsupported hash algorithm for RSA signature.");
        return false;
    }

    final RSASigner signer = RSASigner(hashDigest, RSASignerType.pkcs1);
    signer.init(false, PublicKeyParameter<RSAPublicKey>(rsaPublicParams));

    try {
      // PointyCastle's RSASignature expects a Uint8List, so convert BigInt signature.
      final signatureBytes = _bigIntToPaddedBytes(certificate.rsaSignatureValue!, rsaPublicParams.modulus!.bitLength ~/ 8);
      final RSASignature signature = RSASignature(signatureBytes);
      return signer.verifySignature(certificate.signatureHash!, signature);
    } catch (e) {
      print("Error during RSA signature verification: $e");
      return false;
    }
  }

  /// Validates a DSA signature.
  static bool validateDsaSignature(X509Certificate certificate) {
    if (certificate.dsaSignatureValue == null || certificate.signatureHash == null) {
      print("DSA validation failed: Missing signature value or hash.");
      return false;
    }
    if (certificate.tbsCertificate.subjectPublicKeyInfo.dsaParameters == null ||
        certificate.tbsCertificate.subjectPublicKeyInfo.dsaPublicKeyY == null) {
      print("DSA validation failed: DSA public key or parameters not found in certificate.");
      return false;
    }

    final dsaPublicParams = DSAPublicKey(
      certificate.tbsCertificate.subjectPublicKeyInfo.dsaPublicKeyY!,
      DSAParameters(
        certificate.tbsCertificate.subjectPublicKeyInfo.dsaParameters!.p,
        certificate.tbsCertificate.subjectPublicKeyInfo.dsaParameters!.q,
        certificate.tbsCertificate.subjectPublicKeyInfo.dsaParameters!.g,
      ),
    );

    Digest hashDigest;
    switch (certificate.signatureAlgorithm) {
      case SignatureAlgorithm.sha1WithDSA:
        hashDigest = SHA1Digest();
        break;
      default:
        print("DSA validation failed: Unsupported hash algorithm for DSA signature.");
        return false;
    }

    final DSASigner signer = DSASigner(hashDigest);
    signer.init(false, PublicKeyParameter<DSAPublicKey>(dsaPublicParams));

    try {
      final DSASignature signature = DSASignature(
        certificate.dsaSignatureValue!.r,
        certificate.dsaSignatureValue!.s,
      );
      return signer.verifySignature(certificate.signatureHash!, signature);
    } catch (e) {
      print("Error during DSA signature verification: $e");
      return false;
    }
  }

  /// --- DUMMY IMPLEMENTATION FOR ECDSA SIGNATURE VALIDATION ---
  static bool validateEcdsaSignature(X509Certificate certificate) {
    print("DUMMY: Validating ECDSA signature. This needs full implementation.");
    if (certificate.ecSignatureValue == null || certificate.signatureHash == null) {
      print("ECDSA validation failed: Missing signature value or hash.");
      return false;
    }
    if (certificate.tbsCertificate.subjectPublicKeyInfo.ecCurve == null ||
        certificate.tbsCertificate.subjectPublicKeyInfo.ecPublicKeyPoint == null) {
      print("ECDSA validation failed: EC public key or curve not found in certificate.");
      return false;
    }

    // In a real implementation:
    // 1. Get the correct ECCurve_base from PointyCastle based on certificate.tbsCertificate.subjectPublicKeyInfo.ecCurve.name
    // 2. Create ECPublicKey from the curve and public key point (x, y)
    // 3. Get the correct Digest (e.g., SHA256Digest)
    // 4. Create ECSigner
    // 5. Call signer.init(false, PublicKeyParameter<ECPublicKey>(ecPublicKey))
    // 6. Call signer.verifySignature(certificate.signatureHash!, certificate.ecSignatureValue!)

    // For now, always return true for dummy purposes.
    return true;
  }
  /// --- END DUMMY ---

  /// Converts a BigInt to a Uint8List of a specific padded length (for RSA signature).
  static Uint8List _bigIntToPaddedBytes(BigInt value, int length) {
    final bytes = value.toByteArray();
    if (bytes.length == length) {
      return bytes;
    } else if (bytes.length < length) {
      return Uint8List(length)..setAll(length - bytes.length, bytes);
    } else {
      print("Warning: BigInt value is larger than target length ($length) for padding. Truncating.");
      return Uint8List.sublistView(bytes, bytes.length - length, bytes.length);
    }
  }
}

/// --- DUMMY CERTIFICATE GENERATION FUNCTIONS ---
class CertificateGenerator {
  /// DUMMY: Generates a self-signed ECDSA certificate.
  /// This function is a placeholder. A real implementation would involve:
  /// 1. DER encoding the TBSCertificate structure.
  /// 2. Hashing the DER-encoded TBSCertificate.
  /// 3. Signing the hash with the provided private key.
  /// 4. DER encoding the signature value.
  /// 5. Assembling the final X.509 certificate.
  static X509Certificate generateSelfSignedEcCertificate({
    required X500Name subject,
    required ValidityPeriod validity,
    required ECPrivateKey privateKey, // PointyCastle ECPrivateKey
    required ECPublicKey publicKey,   // PointyCastle ECPublicKey
    required String curveName,        // e.g., "secp256r1"
    required BigInt serialNumber,
    bool isCA = false,
  }) {
    print("DUMMY: Generating a self-signed ECDSA certificate.");
    print("This function is a placeholder and does not produce a valid DER certificate.");

    // Dummy raw TBS bytes (in a real scenario, this would be DER encoded)
    final dummyRawTbsBytes = Uint8List.fromList(utf8.encode(
        "Dummy TBS Certificate content for ${subject.commonName} "
        "valid from ${validity.notBefore} to ${validity.notAfter}"));

    // Dummy hash (in a real scenario, this would be `SHA256Digest().process(dummyRawTbsBytes)`)
    final dummyHash = SHA256Digest().process(Uint8List.fromList(utf8.encode("dummy hash seed")));

    // Dummy EC Public Key Point and Curve for the TbsCertificate
    final dummyEcPublicKeyPoint = EcPublicKeyPoint(x: publicKey.Q!.x!.toBigInt(), y: publicKey.Q!.y!.toBigInt());
    final dummyEcCurve = EcCurve(
      name: curveName,
      p: (publicKey.parameters as ECCurve_base).curve.p,
      a: (publicKey.parameters as ECCurve_base).curve.a,
      b: (publicKey.parameters as ECCurve_base).curve.b,
      n: (publicKey.parameters as ECCurve_base).n,
      G: (publicKey.parameters as ECCurve_base).G,
    );

    final tbsCert = TbsCertificate(
      version: 3, // X.509 v3
      serialNumber: serialNumber,
      signatureAlgorithm: SignatureAlgorithm.sha256WithECDSA,
      issuer: subject, // Self-signed: issuer is subject
      validity: validity,
      subject: subject,
      subjectPublicKeyInfo: SubjectPublicKeyInfo(
        algorithm: PublicKeyAlgorithm.ecPublicKey,
        ecCurve: dummyEcCurve,
        ecPublicKeyPoint: dummyEcPublicKeyPoint,
      ),
      isCertificateAuthority: isCA,
      rawBytes: dummyRawTbsBytes,
    );

    // Dummy signature (in a real scenario, this would be generated by signing dummyHash with privateKey)
    final dummySignature = ECSignature(BigInt.parse("12345"), BigInt.parse("67890"));

    return X509Certificate(
      tbsCertificate: tbsCert,
      signatureAlgorithm: SignatureAlgorithm.sha256WithECDSA,
      ecSignatureValue: dummySignature,
      signatureHash: dummyHash,
    );
  }
}

// Extension to BigInt for toByteArray (required by PointyCastle's RSASignature)
extension BigIntToBytes on BigInt {
  /// Converts a BigInt to its two's complement byte representation.
  /// Handles positive and negative numbers, and ensures minimum byte length.
  Uint8List toByteArray([int? minLength]) {
    if (this == BigInt.zero) {
      return Uint8List.fromList(minLength != null ? List.filled(minLength, 0) : [0]);
    }

    // Determine the number of bytes needed for the absolute value
    int bitLen = toUnsigned(bitLength).bitLength;
    int byteLen = (bitLen + 7) ~/ 8;

    // Handle negative numbers (two's complement)
    BigInt valueToConvert = this;
    if (isNegative) {
      // For negative numbers, we need to convert to positive and then apply two's complement
      // The two's complement representation of -N is ~N + 1
      // We need to ensure enough bits for the representation, so add 1 to bitLength for sign bit.
      valueToConvert = (this + (BigInt.one << (bitLen + 8))); // Add a byte for safety
      byteLen = (valueToConvert.bitLength + 7) ~/ 8;
    }

    final bytes = Uint8List(byteLen);
    for (int i = 0; i < byteLen; i++) {
      bytes[byteLen - 1 - i] = (valueToConvert & BigInt.from(0xFF)).toInt();
      valueToConvert = valueToConvert >> 8;
    }

    // Ensure the output matches minLength if specified, padding with zeros or truncating
    if (minLength != null && bytes.length != minLength) {
      if (bytes.length < minLength) {
        final paddedBytes = Uint8List(minLength);
        paddedBytes.setAll(minLength - bytes.length, bytes);
        return paddedBytes;
      } else {
        // If the number of bytes is greater than minLength, it implies a truncation
        // or an issue with the expected length. For cryptographic purposes, this
        // should ideally not happen if lengths are correctly derived.
        // For now, return the last 'minLength' bytes.
        return Uint8List.sublistView(bytes, bytes.length - minLength, bytes.length);
      }
    }

    return bytes;
  }
}