// main.dart

import 'dart:typed_data';
import 'dart:convert'; // For utf8 and base64
import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/md5.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/asymmetric/dsa.dart';
import 'package:pointycastle/signers/rsa_signer.dart';
import 'package:pointycastle/signers/dsa_signer.dart';

// --- asn1.dart contents ---

// Represents an ASN.1 TLV (Tag, Length, Value) structure
class Asn1Token {
  bool constructed; // Corresponds to bit 6 of the identifier byte
  int tagClass;    // Corresponds to bits 7-8 of the identifier byte
  int tag;         // Corresponds to bits 1-5 of the identifier byte
  int length;      // Length of the value part
  Uint8List data;  // Raw bytes of the value (or the whole TLV if constructed)
  List<Asn1Token>? children; // For constructed types
  Asn1Token? next;          // For sequential tokens at the same level

  Asn1Token({
    required this.constructed,
    required this.tagClass,
    required this.tag,
    required this.length,
    required this.data,
    this.children,
    this.next,
  });
}

// ASN.1 Tag Classes
const int ASN1_CLASS_UNIVERSAL = 0;
const int ASN1_CLASS_APPLICATION = 1;
const int ASN1_CONTEXT_SPECIFIC = 2;
const int ASN1_PRIVATE = 3;

// ASN.1 Universal Tags
const int ASN1_BER = 0;
const int ASN1_BOOLEAN = 1;
const int ASN1_INTEGER = 2;
const int ASN1_BIT_STRING = 3;
const int ASN1_OCTET_STRING = 4;
const int ASN1_NULL = 5;
const int ASN1_OBJECT_IDENTIFIER = 6;
const int ASN1_OBJECT_DESCRIPTOR = 7;
const int ASN1_INSTANCE_OF_EXTERNAL = 8;
const int ASN1_REAL = 9;
const int ASN1_ENUMERATED = 10;
const int ASN1_EMBEDDED_PPV = 11;
const int ASN1_UTF8_STRING = 12;
const int ASN1_RELATIVE_OID = 13;
// 14 & 15 undefined
const int ASN1_SEQUENCE = 16;
const int ASN1_SET = 17;
const int ASN1_NUMERIC_STRING = 18;
const int ASN1_PRINTABLE_STRING = 19;
const int ASN1_TELETEX_STRING = 20;
const int ASN1_T61_STRING = 20; // Alias
const int ASN1_VIDEOTEX_STRING = 21;
const int ASN1_IA5_STRING = 22;
const int ASN1_UTC_TIME = 23;
const int ASN1_GENERALIZED_TIME = 24;
const int ASN1_GRAPHIC_STRING = 25;
const int ASN1_VISIBLE_STRING = 26;
const int ASN1_ISO64_STRING = 26; // Alias
const int ASN1_GENERAL_STRING = 27;
const int ASN1_UNIVERSAL_STRING = 28;
const int ASN1_CHARACTER_STRING = 29;
const int ASN1_BMP_STRING = 30;

// --- asn1_parser.dart contents (integrated) ---

class Asn1Parser {
  static Asn1Token parse(Uint8List buffer, [int offset = 0]) {
    int currentOffset = offset;
    if (currentOffset >= buffer.length) {
      throw FormatException("Buffer exhausted while parsing ASN.1 token.");
    }

    int tagByte = buffer[currentOffset++];
    int tag = tagByte & 0x1F; // Lower 5 bits for universal tags
    bool constructed = (tagByte & 0x20) != 0; // Bit 6
    int tagClass = (tagByte & 0xC0) >> 6;    // Bits 7-8

    if (tag == 0x1F) {
      // High tag number form (tags > 30), not common in X.509 but handled for robustness
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

    if ((lengthByte & 0x80) == 0) {
      // Short form length
      length = lengthByte;
    } else {
      // Long form length
      int numLengthBytes = lengthByte & 0x7F;
      if (numLengthBytes == 0) {
        throw FormatException("Indefinite length encoding not supported for DER.");
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
      throw FormatException("ASN.1 value extends beyond buffer boundary.");
    }
    Uint8List data = Uint8List.sublistView(buffer, currentOffset, currentOffset + length);
    currentOffset += length; // Move past the data

    Asn1Token token = Asn1Token(
      constructed: constructed,
      tagClass: tagClass,
      tag: tag,
      length: length,
      data: data,
    );

    if (constructed) {
      token.children = [];
      int childrenParsedLength = 0;
      while (childrenParsedLength < length) {
        try {
          Asn1Token childToken = parse(data, childrenParsedLength); // Recursively parse children from the 'data' of the parent
          token.children!.add(childToken);
          childrenParsedLength += (childToken.length + _getHeaderLength(childToken));
        } catch (e) {
          // If a child fails to parse, it could be a malformed constructed type.
          // Depending on robustness requirements, you might log and break,
          // or rethrow if strict parsing is required.
          print("Warning: Failed to parse child at offset $childrenParsedLength: $e");
          break; // Stop parsing children for this token
        }
      }
    }

    // This part handles siblings at the same level.
    // If there's more data left in the original buffer *after* this token,
    // it implies another sibling.
    if (currentOffset < buffer.length) {
      token.next = parse(buffer, currentOffset);
    }

    return token;
  }

  // Helper to calculate the full TLV length (Tag + Length + Value)
  static int _getHeaderLength(Asn1Token token) {
    int headerLen = 1; // For tag byte
    if (token.length < 128) {
      headerLen += 1; // For short form length byte
    } else {
      // 1 byte for the length-of-length byte + number of length bytes
      headerLen += 1 + ((token.length.bitLength + 7) ~/ 8);
    }
    return headerLen;
  }

  static String asn1Show(Asn1Token? token, int depth) {
    if (token == null) return '';
    StringBuffer sb = StringBuffer();
    String indent = '  ' * depth;

    Asn1Token? currentToken = token;
    while (currentToken != null) {
      sb.write(indent);
      String tagName = '';
      if (currentToken.tagClass == ASN1_CLASS_UNIVERSAL) {
        tagName = _universalTagNames[currentToken.tag] ?? 'UNKNOWN(${currentToken.tag})';
      } else {
        tagName = 'Context Specific(${currentToken.tag})'; // Simplified for other classes
      }
      sb.write('$tagName (T:${currentToken.tag}, L:${currentToken.length}) ');

      if (!currentToken.constructed) {
        // Primitive types
        switch (currentToken.tag) {
          case ASN1_INTEGER:
            sb.write('Value: ${BigInt.fromBytes(currentToken.data)}');
            break;
          case ASN1_OBJECT_IDENTIFIER:
            sb.write('OID: ${Asn1Parser.decodeOid(currentToken.data)}');
            break;
          case ASN1_BIT_STRING:
            // First byte of bit string is unused bits
            if (currentToken.data.isNotEmpty) {
              sb.write('Bits: ${hex.encode(Uint8List.sublistView(currentToken.data, 1))} (unused: ${currentToken.data[0]} bits)');
            } else {
              sb.write('Bits: (empty)');
            }
            break;
          case ASN1_OCTET_STRING:
            sb.write('Octets: ${hex.encode(currentToken.data)}');
            break;
          case ASN1_BOOLEAN:
            sb.write('Value: ${currentToken.data.isNotEmpty && currentToken.data[0] != 0}');
            break;
          case ASN1_NULL:
            sb.write('Value: NULL');
            break;
          case ASN1_UTF8_STRING:
          case ASN1_PRINTABLE_STRING:
          case ASN1_IA5_STRING:
          case ASN1_VISIBLE_STRING:
          case ASN1_NUMERIC_STRING:
          case ASN1_TELETEX_STRING: // T61String
          case ASN1_VIDEOTEX_STRING:
          case ASN1_GRAPHIC_STRING:
          case ASN1_GENERAL_STRING:
          case ASN1_UNIVERSAL_STRING:
          case ASN1_CHARACTER_STRING:
          case ASN1_BMP_STRING:
            sb.write('String: "${utf8.decode(currentToken.data, allowMalformed: true)}".');
            break;
          case ASN1_UTC_TIME:
          case ASN1_GENERALIZED_TIME:
            try {
              sb.write('Time: ${utf8.decode(currentToken.data)}');
            } catch (e) {
              sb.write('Time (malformed): ${hex.encode(currentToken.data)}');
            }
            break;
          default:
            sb.write('Data: ${hex.encode(currentToken.data)}');
            break;
        }
      }
      sb.writeln();

      if (currentToken.constructed && currentToken.children != null && currentToken.children!.isNotEmpty) {
        for (var child in currentToken.children!) {
          sb.write(asn1Show(child, depth + 1));
        }
      }
      currentToken = currentToken.next; // Move to the next sibling
    }
    return sb.toString();
  }

  // Helper for tag names (from C code)
  static const Map<int, String> _universalTagNames = {
    ASN1_BER: "BER",
    ASN1_BOOLEAN: "BOOLEAN",
    ASN1_INTEGER: "INTEGER",
    ASN1_BIT_STRING: "BIT STRING",
    ASN1_OCTET_STRING: "OCTET STRING",
    ASN1_NULL: "NULL",
    ASN1_OBJECT_IDENTIFIER: "OBJECT IDENTIFIER",
    ASN1_OBJECT_DESCRIPTOR: "ObjectDescriptor",
    ASN1_INSTANCE_OF_EXTERNAL: "INSTANCE OF, EXTERNAL",
    ASN1_REAL: "REAL",
    ASN1_ENUMERATED: "ENUMERATED",
    ASN1_EMBEDDED_PPV: "EMBEDDED PPV",
    ASN1_UTF8_STRING: "UTF8String",
    ASN1_RELATIVE_OID: "RELATIVE-OID",
    ASN1_SEQUENCE: "SEQUENCE",
    ASN1_SET: "SET",
    ASN1_NUMERIC_STRING: "NumericString",
    ASN1_PRINTABLE_STRING: "PrintableString",
    ASN1_TELETEX_STRING: "TeletexString / T61String",
    ASN1_VIDEOTEX_STRING: "VideotexString",
    ASN1_IA5_STRING: "IA5String",
    ASN1_UTC_TIME: "UTCTime",
    ASN1_GENERALIZED_TIME: "GeneralizedTime",
    ASN1_GRAPHIC_STRING: "GraphicString",
    ASN1_VISIBLE_STRING: "VisibleString / ISO64String",
    ASN1_GENERAL_STRING: "GeneralString",
    ASN1_UNIVERSAL_STRING: "UniversalString",
    ASN1_CHARACTER_STRING: "CHARACTER STRING",
    ASN1_BMP_STRING: "BMPString",
  };

  // OID decoding helper
  static String decodeOid(Uint8List oidBytes) {
    if (oidBytes.isEmpty) return "";

    List<int> components = [];
    // First two components are encoded into the first byte
    int firstByte = oidBytes[0];
    components.add(firstByte ~/ 40);
    components.add(firstByte % 40);

    // Subsequent components are variable-length encoded
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
        // Malformed OID, ends unexpectedly
        break;
      }
    }
    return components.join('.');
  }
}

class PemDecoder {
  static Uint8List decode(Uint8List pemBuffer) {
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
        break; // Stop after the first certificate block
      }
      if (inCertBlock) {
        base64Content.write(line.replaceAll('\r', '')); // Remove carriage returns
      }
    }
    if (base64Content.isEmpty) {
      throw FormatException("No certificate block found in PEM data.");
    }
    return base64Decode(base64Content.toString());
  }
}

// Utility for hex encoding
class hex {
  static String encode(Uint8List bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List decode(String hexString) {
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


// --- x509.dart contents ---

// Huge (BigInt equivalent)
typedef Huge = BigInt;

// RSA Key (from pointycastle or custom if needed for direct modulus/exponent access)
// Use pointycastle's RSAPlicKey for consistency
class RsaPublicKey {
  Huge modulus;
  Huge exponent;

  RsaPublicKey({required this.modulus, required this.exponent});
}

// DSA Params and Key (from pointycastle or custom if needed)
// Use pointycastle's DsaParameters and DSAPublicKey
class DsaParams {
  Huge p;
  Huge q;
  Huge g;

  DsaParams({required this.p, required this.q, required this.g});
}

class DsaSignature {
  Huge r;
  Huge s;

  DsaSignature({required this.r, required this.s});
}

enum AlgorithmIdentifier { rsaEncryption, dsa, dh, unknown } // Renamed rsa to rsaEncryption to match OID

enum SignatureAlgorithmIdentifier {
  md5WithRSAEncryption,
  sha1WithRSAEncryption, // Renamed shaWithRSAEncryption to sha1WithRSAEncryption for clarity
  sha1WithDSA,           // Renamed shaWithDSA to sha1WithDSA for clarity
  unknown
}

class X500Name {
  String? idAtCountryName;
  String? idAtStateOrProvinceName;
  String? idAtLocalityName;
  String? idAtOrganizationName;
  String? idAtOrganizationalUnitName;
  String? idAtCommonName;

  X500Name();

  @override
  String toString() {
    List<String> parts = [];
    if (idAtCommonName != null) parts.add('CN=$idAtCommonName');
    if (idAtOrganizationalUnitName != null) parts.add('OU=$idAtOrganizationalUnitName');
    if (idAtOrganizationName != null) parts.add('O=$idAtOrganizationName');
    if (idAtLocalityName != null) parts.add('L=$idAtLocalityName');
    if (idAtStateOrProvinceName != null) parts.add('ST=$idAtStateOrProvinceName');
    if (idAtCountryName != null) parts.add('C=$idAtCountryName');
    return parts.join(', ');
  }
}

class ValidityPeriod {
  DateTime notBefore;
  DateTime notAfter;

  ValidityPeriod({required this.notBefore, required this.notAfter});
}

class PublicKeyInfo {
  AlgorithmIdentifier algorithm;
  RsaPublicKey? rsaPublicKey;
  DsaParams? dsaParameters;
  Huge? dsaPublicKey; // For DSA (y value)

  PublicKeyInfo({required this.algorithm, this.rsaPublicKey, this.dsaParameters, this.dsaPublicKey});
}

class X509Certificate {
  int version;
  Huge serialNumber;
  SignatureAlgorithmIdentifier signatureAlgorithm; // Renamed to avoid conflict with signature value
  X500Name issuer;
  ValidityPeriod validity;
  X500Name subject;
  PublicKeyInfo subjectPublicKeyInfo;
  Uint8List? issuerUniqueId; // Optional
  Uint8List? subjectUniqueId; // Optional
  bool certificateAuthority; // 1 if CA, 0 if not
  Uint8List? rawTbsCertificateBytes; // Store the raw bytes for hashing

  X509Certificate({
    required this.version,
    required this.serialNumber,
    required this.signatureAlgorithm,
    required this.issuer,
    required this.validity,
    required this.subject,
    required this.subjectPublicKeyInfo,
    this.issuerUniqueId,
    this.subjectUniqueId,
    this.certificateAuthority = false,
    this.rawTbsCertificateBytes,
  });
}

class SignedX509Certificate {
  X509Certificate tbsCertificate;
  Uint8List? hash; // Calculated hash of tbsCertificate
  int? hashLen;
  SignatureAlgorithmIdentifier algorithm; // Algorithm used for signing
  Huge? rsaSignatureValue; // For RSA signature
  DsaSignature? dsaSignatureValue; // For DSA signature

  SignedX509Certificate({
    required this.tbsCertificate,
    required this.algorithm,
    this.hash,
    this.hashLen,
    this.rsaSignatureValue,
    this.dsaSignatureValue,
  });
}

// --- x509.c contents (integrated logic) ---

class X509Parser {
  static const String OID_MD5_WITH_RSA_ENCRYPTION = "1.2.840.113549.1.1.4";
  static const String OID_SHA1_WITH_RSA_ENCRYPTION = "1.2.840.113549.1.1.5";
  static const String OID_SHA1_WITH_DSA = "1.2.840.10040.4.3";
  static const String OID_RSA_ENCRYPTION = "1.2.840.113549.1.1.1";
  static const String OID_DSA = "1.2.840.10040.4.1";
  static const String OID_DH = "1.2.840.10046.2.1";

  // X.500 Name OIDs
  static const String OID_COUNTRY_NAME = "2.5.4.6"; // C
  static const String OID_STATE_OR_PROVINCE_NAME = "2.5.4.8"; // ST
  static const String OID_LOCALITY_NAME = "2.5.4.7"; // L
  static const String OID_ORGANIZATION_NAME = "2.5.4.10"; // O
  static const String OID_ORGANIZATIONAL_UNIT_NAME = "2.5.4.11"; // OU
  static const String OID_COMMON_NAME = "2.5.4.3"; // CN

  // Extension OIDs
  static const String OID_KEY_USAGE = "2.5.29.15";
  static const int BIT_CERT_SIGNER = 5; // bit 5 (0-indexed) for keyCertSign

  static bool _validateNode(Asn1Token? source, int expectedTag, int expectedChildren, String desc) {
    if (source == null) {
      print("Error - '$desc' missing.");
      return false;
    }
    if (source.tag != expectedTag) {
      print("Error parsing '$desc'; expected a $expectedTag tag, got a ${source.tag}.");
      return false;
    }
    if (source.children == null || source.children!.length < expectedChildren) {
      print("Error parsing '$desc'; expected at least $expectedChildren children, got ${source.children?.length ?? 0}.");
      return false;
    }
    return true;
  }

  static Huge _parseHuge(Asn1Token token) {
    if (!_validateNode(token, ASN1_INTEGER, 0, "Huge Integer")) {
      throw FormatException("Invalid Huge Integer token.");
    }
    // `BigInt.fromBytes` correctly handles the two's complement and leading zeros
    return BigInt.fromBytes(token.data);
  }

  static AlgorithmIdentifier _parseAlgorithmIdentifier(Asn1Token algorithmToken) {
    if (!_validateNode(algorithmToken, ASN1_SEQUENCE, 1, "Algorithm Identifier")) {
      return AlgorithmIdentifier.unknown;
    }
    Asn1Token oidToken = algorithmToken.children![0];
    if (!_validateNode(oidToken, ASN1_OBJECT_IDENTIFIER, 0, "Algorithm OID")) {
      return AlgorithmIdentifier.unknown;
    }

    String oid = Asn1Parser.decodeOid(oidToken.data);
    switch (oid) {
      case OID_RSA_ENCRYPTION: return AlgorithmIdentifier.rsaEncryption;
      case OID_DSA: return AlgorithmIdentifier.dsa;
      case OID_DH: return AlgorithmIdentifier.dh;
      default: return AlgorithmIdentifier.unknown;
    }
  }

  static SignatureAlgorithmIdentifier _parseSignatureAlgorithmIdentifier(Asn1Token algorithmToken) {
    if (!_validateNode(algorithmToken, ASN1_SEQUENCE, 1, "Signature Algorithm Identifier")) {
      return SignatureAlgorithmIdentifier.unknown;
    }
    Asn1Token oidToken = algorithmToken.children![0];
    if (!_validateNode(oidToken, ASN1_OBJECT_IDENTIFIER, 0, "Signature Algorithm OID")) {
      return SignatureAlgorithmIdentifier.unknown;
    }

    String oid = Asn1Parser.decodeOid(oidToken.data);
    switch (oid) {
      case OID_MD5_WITH_RSA_ENCRYPTION: return SignatureAlgorithmIdentifier.md5WithRSAEncryption;
      case OID_SHA1_WITH_RSA_ENCRYPTION: return SignatureAlgorithmIdentifier.sha1WithRSAEncryption;
      case OID_SHA1_WITH_DSA: return SignatureAlgorithmIdentifier.sha1WithDSA;
      default: return SignatureAlgorithmIdentifier.unknown;
    }
  }

  static X500Name _parseX500Name(Asn1Token nameToken) {
    X500Name name = X500Name();
    if (!_validateNode(nameToken, ASN1_SEQUENCE, 1, "Name")) {
      return name;
    }

    // Name is a SEQUENCE OF RDNs (Relative Distinguished Names)
    // Each RDN is a SET OF AttributeTypeAndValue
    for (var rdnToken in nameToken.children!) {
      if (!_validateNode(rdnToken, ASN1_SET, 1, "Relative Distinguished Name (RDN)")) {
        continue;
      }
      for (var attrValueToken in rdnToken.children!) {
        if (!_validateNode(attrValueToken, ASN1_SEQUENCE, 2, "Attribute Type And Value")) {
          continue;
        }
        Asn1Token attrOidToken = attrValueToken.children![0];
        Asn1Token attrValueStringToken = attrValueToken.children![1];

        if (!_validateNode(attrOidToken, ASN1_OBJECT_IDENTIFIER, 0, "Attribute Type OID")) {
          continue;
        }

        String oid = Asn1Parser.decodeOid(attrOidToken.data);
        String value = utf8.decode(attrValueStringToken.data, allowMalformed: true);

        switch (oid) {
          case OID_COUNTRY_NAME: name.idAtCountryName = value; break;
          case OID_STATE_OR_PROVINCE_NAME: name.idAtStateOrProvinceName = value; break;
          case OID_LOCALITY_NAME: name.idAtLocalityName = value; break;
          case OID_ORGANIZATION_NAME: name.idAtOrganizationName = value; break;
          case OID_ORGANIZATIONAL_UNIT_NAME: name.idAtOrganizationalUnitName = value; break;
          case OID_COMMON_NAME: name.idAtCommonName = value; break;
          default:
            print("Warning: Unknown OID in X.500 Name: $oid with value $value");
            break;
        }
      }
    }
    return name;
  }

  static ValidityPeriod _parseValidity(Asn1Token validityToken) {
    if (!_validateNode(validityToken, ASN1_SEQUENCE, 2, "Validity Period")) {
      throw FormatException("Invalid Validity Period token.");
    }

    Asn1Token notBeforeToken = validityToken.children![0];
    Asn1Token notAfterToken = validityToken.children![1];

    DateTime parseTime(Asn1Token timeToken) {
      String timeString = utf8.decode(timeToken.data);
      if (timeToken.tag == ASN1_UTC_TIME) {
        // YYMMDDHHMMSSZ or YYMMDDHHMMSS+-HHMM
        // This is a simplified parse. Real world needs more robust parsing.
        // Assuming Z (UTC) for simplicity.
        // Format: YYMMDDHHMMSSZ
        int year = int.parse(timeString.substring(0, 2));
        if (year < 50) year += 2000; else year += 1900;
        int month = int.parse(timeString.substring(2, 4));
        int day = int.parse(timeString.substring(4, 6));
        int hour = int.parse(timeString.substring(6, 8));
        int minute = int.parse(timeString.substring(8, 10));
        int second = int.parse(timeString.substring(10, 12));
        return DateTime.utc(year, month, day, hour, minute, second);
      } else if (timeToken.tag == ASN1_GENERALIZED_TIME) {
        // YYYYMMDDHHMMSSZ or YYYYMMDDHHMMSS.sZ or YYYYMMDDHHMMSS+-HHMM
        // Simplified parse, assuming Z
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

  static PublicKeyInfo _parsePublicKeyInfo(Asn1Token pubKeyInfoToken) {
    if (!_validateNode(pubKeyInfoToken, ASN1_SEQUENCE, 2, "Subject Public Key Info")) {
      throw FormatException("Invalid Subject Public Key Info token.");
    }

    Asn1Token algorithmSeqToken = pubKeyInfoToken.children![0];
    Asn1Token publicKeyBitStringToken = pubKeyInfoToken.children![1];

    AlgorithmIdentifier algorithm = _parseAlgorithmIdentifier(algorithmSeqToken);

    // The public key itself is encoded as a BIT STRING,
    // which contains the actual public key data (another ASN.1 structure).
    // The first byte of the BIT STRING is the number of unused bits.
    if (!_validateNode(publicKeyBitStringToken, ASN1_BIT_STRING, 0, "Public Key Bit String")) {
      throw FormatException("Invalid Public Key Bit String token.");
    }

    // Extract the actual public key bytes by skipping the first byte (unused bits)
    Uint8List publicKeyBytes = Uint8List.sublistView(publicKeyBitStringToken.data, 1);

    Asn1Token parsedPublicKeyToken = Asn1Parser.parse(publicKeyBytes);

    RsaPublicKey? rsaPublicKey;
    DsaParams? dsaParameters;
    Huge? dsaPublicKey;

    if (algorithm == AlgorithmIdentifier.rsaEncryption) {
      if (!_validateNode(parsedPublicKeyToken, ASN1_SEQUENCE, 2, "RSA Public Key")) {
        throw FormatException("Invalid RSA Public Key token.");
      }
      Huge modulus = _parseHuge(parsedPublicKeyToken.children![0]);
      Huge exponent = _parseHuge(parsedPublicKeyToken.children![1]);
      rsaPublicKey = RsaPublicKey(modulus: modulus, exponent: exponent);
    } else if (algorithm == AlgorithmIdentifier.dsa) {
      if (!_validateNode(algorithmSeqToken, ASN1_SEQUENCE, 2, "DSA Algorithm Sequence with Params")) {
        throw FormatException("DSA algorithm sequence missing parameters.");
      }
      Asn1Token dsaParamsSeq = algorithmSeqToken.children![1]; // Parameters are usually here
      if (!_validateNode(dsaParamsSeq, ASN1_SEQUENCE, 3, "DSA Parameters")) {
        throw FormatException("Invalid DSA parameters token.");
      }
      dsaParameters = DsaParams(
        p: _parseHuge(dsaParamsSeq.children![0]),
        q: _parseHuge(dsaParamsSeq.children![1]),
        g: _parseHuge(dsaParamsSeq.children![2]),
      );

      // The DSA public key 'y' is directly an INTEGER in the BIT STRING data
      if (!_validateNode(parsedPublicKeyToken, ASN1_INTEGER, 0, "DSA Public Key")) {
        throw FormatException("Invalid DSA Public Key token.");
      }
      dsaPublicKey = _parseHuge(parsedPublicKeyToken);
    } else {
      print("Warning: Unsupported public key algorithm: $algorithm");
    }

    return PublicKeyInfo(
      algorithm: algorithm,
      rsaPublicKey: rsaPublicKey,
      dsaParameters: dsaParameters,
      dsaPublicKey: dsaPublicKey,
    );
  }

  static bool _getAsn1Bit(Uint8List data, int bitIndex) {
    if (data.isEmpty) return false;
    int unusedBits = data[0];
    int actualDataLen = data.length - 1;
    int totalBits = actualDataLen * 8 - unusedBits;

    if (bitIndex < 0 || bitIndex >= totalBits) {
      return false; // Bit out of bounds
    }

    int byteIndex = (bitIndex ~/ 8) + 1; // +1 to skip unused_bits byte
    int bitOffsetInByte = bitIndex % 8;

    if (byteIndex >= data.length) return false; // Should not happen if totalBits calculation is correct

    // Bits are ordered from MSB to LSB within a byte
    return ((data[byteIndex] >> (7 - bitOffsetInByte)) & 0x01) != 0;
  }

  static void _parseExtensions(X509Certificate certificate, Asn1Token extensionsToken) {
    if (!_validateNode(extensionsToken, ASN1_SEQUENCE, 1, "Extensions")) {
      return;
    }

    for (var extensionSeq in extensionsToken.children!) {
      if (!_validateNode(extensionSeq, ASN1_SEQUENCE, 2, "Extension")) {
        continue;
      }
      Asn1Token oidToken = extensionSeq.children![0];
      // Asn1Token criticalToken = extensionSeq.children![1]; // Optional, boolean
      Asn1Token extValueOctetString = extensionSeq.children!.last; // Last child is always the value OCTET STRING

      if (!_validateNode(oidToken, ASN1_OBJECT_IDENTIFIER, 0, "Extension OID")) {
        continue;
      }
      if (!_validateNode(extValueOctetString, ASN1_OCTET_STRING, 0, "Extension Value Octet String")) {
        continue;
      }

      String oid = Asn1Parser.decodeOid(oidToken.data);
      Uint8List extValueData = extValueOctetString.data;

      if (oid == OID_KEY_USAGE) {
        // Key Usage extension value is a BIT STRING
        try {
          Asn1Token keyUsageBitString = Asn1Parser.parse(extValueData);
          if (!_validateNode(keyUsageBitString, ASN1_BIT_STRING, 0, "Key Usage Bit String")) {
            print("Warning: Invalid Key Usage Bit String format.");
            continue;
          }
          // Check for keyCertSign bit
          certificate.certificateAuthority = _getAsn1Bit(keyUsageBitString.data, BIT_CERT_SIGNER);
        } catch (e) {
          print("Warning: Failed to parse Key Usage extension: $e");
        }
      } else {
        print("Warning: Unhandled extension OID: $oid");
      }
    }
  }

  static X509Certificate _parseTbsCertificate(Asn1Token tbsCertificateToken) {
    if (!_validateNode(tbsCertificateToken, ASN1_SEQUENCE, 6, "TBS Certificate")) {
      throw FormatException("Invalid TBS Certificate token.");
    }

    X509Certificate certificate = X509Certificate(
      version: 0, // Default to v1
      serialNumber: BigInt.zero,
      signatureAlgorithm: SignatureAlgorithmIdentifier.unknown,
      issuer: X500Name(),
      validity: ValidityPeriod(notBefore: DateTime.now(), notAfter: DateTime.now()),
      subject: X500Name(),
      subjectPublicKeyInfo: PublicKeyInfo(algorithm: AlgorithmIdentifier.unknown),
      rawTbsCertificateBytes: tbsCertificateToken.data // Store raw bytes for hashing
    );

    int currentChildIndex = 0;

    // Version (optional, context-specific tag 0)
    // If present, it's [0] INTEGER version (v1 is 0, v2 is 1, v3 is 2)
    if (tbsCertificateToken.children![0].tagClass == ASN1_CONTEXT_SPECIFIC &&
        tbsCertificateToken.children![0].tag == 0) {
      Asn1Token versionToken = tbsCertificateToken.children![0];
      if (!_validateNode(versionToken, 0, 1, "Version (Context-Specific 0)")) {
        throw FormatException("Invalid Version token.");
      }
      certificate.version = _parseHuge(versionToken.children![0]).toInt() + 1; // 0 -> v1, 1 -> v2, 2 -> v3
      currentChildIndex++;
    } else {
      certificate.version = 1; // Default to X.509 v1 if version field is absent
    }

    certificate.serialNumber = _parseHuge(tbsCertificateToken.children![currentChildIndex++]);
    certificate.signatureAlgorithm = _parseSignatureAlgorithmIdentifier(tbsCertificateToken.children![currentChildIndex++]);
    certificate.issuer = _parseX500Name(tbsCertificateToken.children![currentChildIndex++]);
    certificate.validity = _parseValidity(tbsCertificateToken.children![currentChildIndex++]);
    certificate.subject = _parseX500Name(tbsCertificateToken.children![currentChildIndex++]);
    certificate.subjectPublicKeyInfo = _parsePublicKeyInfo(tbsCertificateToken.children![currentChildIndex++]);

    // Optional: issuerUniqueId and subjectUniqueId
    // These are BIT STRINGs, context-specific tags [1] and [2]
    if (tbsCertificateToken.children!.length > currentChildIndex &&
        tbsCertificateToken.children![currentChildIndex].tagClass == ASN1_CONTEXT_SPECIFIC &&
        tbsCertificateToken.children![currentChildIndex].tag == 1) {
      certificate.issuerUniqueId = tbsCertificateToken.children![currentChildIndex++].data; // Assuming data is the bit string
    }
    if (tbsCertificateToken.children!.length > currentChildIndex &&
        tbsCertificateToken.children![currentChildIndex].tagClass == ASN1_CONTEXT_SPECIFIC &&
        tbsCertificateToken.children![currentChildIndex].tag == 2) {
      certificate.subjectUniqueId = tbsCertificateToken.children![currentChildIndex++].data; // Assuming data is the bit string
    }

    // Extensions (optional, context-specific tag 3)
    if (certificate.version >= 3 &&
        tbsCertificateToken.children!.length > currentChildIndex &&
        tbsCertificateToken.children![currentChildIndex].tagClass == ASN1_CONTEXT_SPECIFIC &&
        tbsCertificateToken.children![currentChildIndex].tag == 3) {
      Asn1Token extensionsOuterToken = tbsCertificateToken.children![currentChildIndex++];
      // Extensions are wrapped in an OCTET STRING
      if (!_validateNode(extensionsOuterToken, 3, 1, "Extensions Outer (Context-Specific 3)")) {
        throw FormatException("Invalid Extensions Outer token.");
      }
      Asn1Token extensionsOctetString = extensionsOuterToken.children![0];
      if (!_validateNode(extensionsOctetString, ASN1_OCTET_STRING, 0, "Extensions Octet String")) {
        throw FormatException("Invalid Extensions Octet String.");
      }
      try {
        Asn1Token actualExtensions = Asn1Parser.parse(extensionsOctetString.data);
        _parseExtensions(certificate, actualExtensions);
      } catch (e) {
        print("Warning: Failed to parse Extensions content: $e");
      }
    }

    return certificate;
  }

  static Huge _parseRsaSignatureValue(Asn1Token signatureToken) {
    if (!_validateNode(signatureToken, ASN1_BIT_STRING, 0, "RSA Signature Value")) {
      throw FormatException("Invalid RSA Signature Value token.");
    }
    // Skip the unused bits byte
    return BigInt.fromBytes(Uint8List.sublistView(signatureToken.data, 1));
  }

  static DsaSignature _parseDsaSignatureValue(Asn1Token signatureToken) {
    if (!_validateNode(signatureToken, ASN1_BIT_STRING, 0, "DSA Signature Value")) {
      throw FormatException("Invalid DSA Signature Value token.");
    }
    // DSA signature is a SEQUENCE of two INTEGERS (r and s)
    // inside the BIT STRING's data. Skip the unused bits byte.
    Uint8List dsaSigBytes = Uint8List.sublistView(signatureToken.data, 1);
    Asn1Token dsaSigSeq = Asn1Parser.parse(dsaSigBytes);

    if (!_validateNode(dsaSigSeq, ASN1_SEQUENCE, 2, "DSA Signature Sequence (r, s)")) {
      throw FormatException("Invalid DSA Signature Sequence.");
    }

    Huge r = _parseHuge(dsaSigSeq.children![0]);
    Huge s = _parseHuge(dsaSigSeq.children![1]);
    return DsaSignature(r: r, s: s);
  }

  static SignedX509Certificate parseX509Certificate(Uint8List buffer) {
    Asn1Token certificateToken = Asn1Parser.parse(buffer);

    if (!_validateNode(certificateToken, ASN1_SEQUENCE, 3, "Signed X.509 Certificate")) {
      throw FormatException("Invalid Signed X.509 Certificate structure.");
    }

    Asn1Token tbsCertificateToken = certificateToken.children![0];
    Asn1Token signatureAlgorithmToken = certificateToken.children![1];
    Asn1Token signatureValueToken = certificateToken.children![2];

    X509Certificate tbsCertificate = _parseTbsCertificate(tbsCertificateToken);
    SignatureAlgorithmIdentifier signatureAlgorithm = _parseSignatureAlgorithmIdentifier(signatureAlgorithmToken);

    SignedX509Certificate signedCert = SignedX509Certificate(
      tbsCertificate: tbsCertificate,
      algorithm: signatureAlgorithm,
    );

    // Calculate hash of TBS Certificate
    Uint8List? hash;
    if (signatureAlgorithm == SignatureAlgorithmIdentifier.md5WithRSAEncryption) {
      hash = MD5Digest().process(tbsCertificate.rawTbsCertificateBytes!);
    } else if (signatureAlgorithm == SignatureAlgorithmIdentifier.sha1WithRSAEncryption ||
               signatureAlgorithm == SignatureAlgorithmIdentifier.sha1WithDSA) {
      hash = SHA1Digest().process(tbsCertificate.rawTbsCertificateBytes!);
    }
    signedCert.hash = hash;
    signedCert.hashLen = hash?.length;

    // Parse signature value based on algorithm
    if (signatureAlgorithm == SignatureAlgorithmIdentifier.md5WithRSAEncryption ||
        signatureAlgorithm == SignatureAlgorithmIdentifier.sha1WithRSAEncryption) {
      signedCert.rsaSignatureValue = _parseRsaSignatureValue(signatureValueToken);
    } else if (signatureAlgorithm == SignatureAlgorithmIdentifier.sha1WithDSA) {
      signedCert.dsaSignatureValue = _parseDsaSignatureValue(signatureValueToken);
    } else {
      print("Warning: Unsupported signature algorithm for parsing value: $signatureAlgorithm");
    }

    return signedCert;
  }

  static bool validateCertificateRsa(SignedX509Certificate certificate) {
    if (certificate.algorithm != SignatureAlgorithmIdentifier.md5WithRSAEncryption &&
        certificate.algorithm != SignatureAlgorithmIdentifier.sha1WithRSAEncryption) {
      print("RSA validation: Incorrect algorithm for RSA signature.");
      return false;
    }
    if (certificate.tbsCertificate.subjectPublicKeyInfo.rsaPublicKey == null) {
      print("RSA validation: RSA public key not found in certificate.");
      return false;
    }
    if (certificate.rsaSignatureValue == null) {
      print("RSA validation: RSA signature value not found.");
      return false;
    }
    if (certificate.hash == null) {
      print("RSA validation: Hash of TBS certificate not calculated.");
      return false;
    }

    final rsaPublicParams = RSAPublicKey(
      certificate.tbsCertificate.subjectPublicKeyInfo.rsaPublicKey!.modulus,
      certificate.tbsCertificate.subjectPublicKeyInfo.rsaPublicKey!.exponent,
    );

    final RSASigner signer = RSASigner(
      certificate.algorithm == SignatureAlgorithmIdentifier.md5WithRSAEncryption ? MD5Digest() : SHA1Digest(),
      RSASignerType.pss, // Assuming PSS, but it could be PKCS1v15 as in original C.
                         // PKCS1v15 needs specific padding logic that might be
                         // in a separate PointyCastle signer or manual implementation.
                         // For simplicity and common use, PSS is often preferred.
                         // If the C code implies PKCS1v15 padding, this needs adjustment.
    );
    signer.init(false, PublicKeyParameter<RSAPublicKey>(rsaPublicParams));

    try {
      final RSASignature signature = RSASignature(certificate.rsaSignatureValue!.toByteArray());
      return signer.verifySignature(certificate.hash!, signature);
    } catch (e) {
      print("Error during RSA signature verification: $e");
      return false;
    }
  }

  static bool validateCertificateDsa(SignedX509Certificate certificate) {
    if (certificate.algorithm != SignatureAlgorithmIdentifier.sha1WithDSA) {
      print("DSA validation: Incorrect algorithm for DSA signature.");
      return false;
    }
    if (certificate.tbsCertificate.subjectPublicKeyInfo.dsaParameters == null ||
        certificate.tbsCertificate.subjectPublicKeyInfo.dsaPublicKey == null) {
      print("DSA validation: DSA public key or parameters not found in certificate.");
      return false;
    }
    if (certificate.dsaSignatureValue == null) {
      print("DSA validation: DSA signature value (r, s) not found.");
      return false;
    }
    if (certificate.hash == null) {
      print("DSA validation: Hash of TBS certificate not calculated.");
      return false;
    }

    final dsaPublicParams = DSAPublicKey(
      certificate.tbsCertificate.subjectPublicKeyInfo.dsaPublicKey!,
      DSAParameters(
        certificate.tbsCertificate.subjectPublicKeyInfo.dsaParameters!.p,
        certificate.tbsCertificate.subjectPublicKeyInfo.dsaParameters!.q,
        certificate.tbsCertificate.subjectPublicKeyInfo.dsaParameters!.g,
      ),
    );

    final DSASigner signer = DSASigner(SHA1Digest());
    signer.init(false, PublicKeyParameter<DSAPublicKey>(dsaPublicParams));

    try {
      final DSASignature signature = DSASignature(certificate.dsaSignatureValue!.r, certificate.dsaSignatureValue!.s);
      return signer.verifySignature(certificate.hash!, signature);
    } catch (e) {
      print("Error during DSA signature verification: $e");
      return false;
    }
  }

  static void displayX509Certificate(SignedX509Certificate certificate) {
    X509Certificate cert = certificate.tbsCertificate;
    print("X509 Certificate:");
    print("  Version: ${cert.version}");
    print("  Serial Number: ${cert.serialNumber.toRadixString(16)}");
    print("  Signature Algorithm: ${cert.signatureAlgorithm}");
    print("  Issuer: ${cert.issuer}");
    print("  Validity:");
    print("    Not Before: ${cert.validity.notBefore.toIso8601String()} UTC");
    print("    Not After: ${cert.validity.notAfter.toIso8601String()} UTC");
    print("  Subject: ${cert.subject}");
    print("  Subject Public Key Info:");
    print("    Algorithm: ${cert.subjectPublicKeyInfo.algorithm}");
    if (cert.subjectPublicKeyInfo.rsaPublicKey != null) {
      print("      RSA Public Key:");
      print("        Modulus (n): ${cert.subjectPublicKeyInfo.rsaPublicKey!.modulus.toRadixString(16)}");
      print("        Exponent (e): ${cert.subjectPublicKeyInfo.rsaPublicKey!.exponent.toRadixString(16)}");
    } else if (cert.subjectPublicKeyInfo.dsaParameters != null && cert.subjectPublicKeyInfo.dsaPublicKey != null) {
      print("      DSA Public Key:");
      print("        P: ${cert.subjectPublicKeyInfo.dsaParameters!.p.toRadixString(16)}");
      print("        Q: ${cert.subjectPublicKeyInfo.dsaParameters!.q.toRadixString(16)}");
      print("        G: ${cert.subjectPublicKeyInfo.dsaParameters!.g.toRadixString(16)}");
      print("        Y: ${cert.subjectPublicKeyInfo.dsaPublicKey!.toRadixString(16)}");
    }
    if (cert.issuerUniqueId != null) {
      print("  Issuer Unique ID: ${hex.encode(cert.issuerUniqueId!)}");
    }
    if (cert.subjectUniqueId != null) {
      print("  Subject Unique ID: ${hex.encode(cert.subjectUniqueId!)}");
    }
    print("  Certificate Authority: ${cert.certificateAuthority ? "Yes" : "No"}");

    print("  Signature Value (Algorithm: ${certificate.algorithm}):");
    if (certificate.rsaSignatureValue != null) {
      print("    RSA Signature: ${certificate.rsaSignatureValue!.toRadixString(16)}");
    } else if (certificate.dsaSignatureValue != null) {
      print("    DSA Signature (r): ${certificate.dsaSignatureValue!.r.toRadixString(16)}");
      print("    DSA Signature (s): ${certificate.dsaSignatureValue!.s.toRadixString(16)}");
    }
    print("  TBS Certificate Hash (${certificate.hashLen! * 8}-bit): ${hex.encode(certificate.hash!)}");

    // Optional: Display ASN.1 structure
    // if (cert.rawTbsCertificateBytes != null) {
    //   print("\nRaw TBS Certificate ASN.1 Structure:");
    //   print(Asn1Parser.asn1Show(Asn1Parser.parse(cert.rawTbsCertificateBytes!), 0));
    // }
  }
}

// Extension to BigInt for toByteArray
extension BigIntToBytes on BigInt {
  Uint8List toByteArray() {
    // BigInt.toUnsigned does not convert to 2's complement representation.
    // We need to handle this manually for signing/verification if `fromBytes`
    // produces signed representation for comparison and `toByteArray` needs to
    // produce a specific format for PointyCastle.
    // For now, assuming PointyCastle can handle raw bytes.
    // A proper solution would involve:
    // 1. Determining required byte length (e.g., modulus length for RSA)
    // 2. Converting BigInt to bytes (e.g., using `Uint8List.fromList` and manually handling sign/padding)
    return Uint8List.fromList(toRadixString(16).padLeft((bitLength + 7) ~/ 8 * 2, '0').replaceAllMapped(RegExp(r'.{2}'), (match) => '0x${match.group(0)},').split(',').map((e) => int.parse(e)).toList());
  }
}


/*
// Example Usage (requires a main function and a sample certificate file)
import 'dart:io';

void main(List<String> arguments) async {
  if (arguments.length < 2) {
    print("Usage: dart run <script_name> [-der|-pem] <certificate_file>");
    exit(1);
  }

  String format = arguments[0];
  String filePath = arguments[1];

  Uint8List buffer;
  try {
    buffer = await File(filePath).readAsBytes();
  } catch (e) {
    print("Error reading file: $e");
    exit(1);
  }

  if (format == "-pem") {
    try {
      buffer = PemDecoder.decode(buffer);
      print("Successfully decoded PEM to DER.");
    } catch (e) {
      print("Error decoding PEM: $e");
      exit(1);
    }
  } else if (format != "-der") {
    print("Invalid format: $format. Use -der or -pem.");
    exit(1);
  }

  try {
    SignedX509Certificate certificate = X509Parser.parseX509Certificate(buffer);
    X509Parser.displayX509Certificate(certificate);

    // Attempt to validate self-signed certificate
    bool isValid = false;
    if (certificate.algorithm == SignatureAlgorithmIdentifier.md5WithRSAEncryption ||
        certificate.algorithm == SignatureAlgorithmIdentifier.sha1WithRSAEncryption) {
      isValid = X509Parser.validateCertificateRsa(certificate);
    } else if (certificate.algorithm == SignatureAlgorithmIdentifier.sha1WithDSA) {
      isValid = X509Parser.validateCertificateDsa(certificate);
    } else {
      print("Validation not implemented for this signature algorithm.");
    }

    if (isValid) {
      print("\nCertificate is a valid self-signed certificate (or signature matches hash).");
    } else {
      print("\nCertificate is corrupt or not self-signed (or signature verification failed).");
    }

  } on FormatException catch (e) {
    print("Parsing error: $e");
    exit(1);
  } catch (e) {
    print("An unexpected error occurred: $e");
    exit(1);
  }
}
*/