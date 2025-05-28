import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart'; // For hex encoding if needed for debugging
import 'dart:math';

// Constants from the Go code
const int stunMagicCookie = 0x2112A442;
const int stunMessageHeaderSize = 20;
const int stunTransactionIdSize = 12;
const int stunAttributeHeaderSize = 4;
const int stunHmacSignatureSize = 20;
const int stunFingerprintSize = 4;
const int stunFingerprintXorMask = 0x5354554e;

// --- Enums and Classes for STUN Message Structure ---

// Based on messagetype.go
class StunMessageType {
  final StunMessageMethod method;
  final StunMessageClass messageClass;

  const StunMessageType(this.method, this.messageClass);

  static const int methodABits = 0xf; // 0b0000000000001111
  static const int methodBBits = 0x70; // 0b0000000001110000
  static const int methodDBits = 0xf80; // 0b0000111110000000

  static const int methodBShift = 1;
  static const int methodDShift = 2;

  static const int firstBit = 0x1;
  static const int secondBit = 0x2;

  static const int c0Bit = firstBit;
  static const int c1Bit = secondBit;

  static const int classC0Shift = 4;
  static const int classC1Shift = 7;

  factory StunMessageType.decode(int mt) {
    // Decoding class.
    int c0 = (mt >> classC0Shift) & c0Bit;
    int c1 = (mt >> classC1Shift) & c1Bit;
    int classVal = c0 + c1;

    // Decoding method.
    int a = mt & methodABits; // A(M0-M3)
    int b = (mt >> methodBShift) & methodBBits; // B(M4-M6)
    int d = (mt >> methodDShift) & methodDBits; // D(M7-M11)
    int m = a + b + d;

    return StunMessageType(
        StunMessageMethod.fromVal(m), StunMessageClass.fromVal(classVal));
  }

  int encode() {
    int m = method.value;
    int a = m & methodABits;
    int b = m & methodBBits;
    int d = m & methodDBits;

    m = a + (b << methodBShift) + (d << methodDShift);

    int c = messageClass.value;
    int c0 = (c & c0Bit) << classC0Shift;
    int c1 = (c & c1Bit) << classC1Shift;
    int classVal = c0 + c1;

    return m + classVal;
  }

  @override
  String toString() {
    return '${method.name} ${messageClass.name}';
  }

  static const StunMessageType bindingRequest =
      StunMessageType(StunMessageMethod.binding, StunMessageClass.request);
  static const StunMessageType bindingSuccessResponse = StunMessageType(
      StunMessageMethod.binding, StunMessageClass.successResponse);
  static const StunMessageType bindingErrorResponse = StunMessageType(
      StunMessageMethod.binding, StunMessageClass.errorResponse);
}

// Based on messageclass.go
enum StunMessageClass {
  request(0x00, "Request"),
  indication(0x01, "Indication"),
  successResponse(0x02, "Success Response"),
  errorResponse(0x03, "Error Response");

  const StunMessageClass(this.value, this.name);
  final int value;
  final String name;

  static StunMessageClass fromVal(int val) {
    return StunMessageClass.values.firstWhere((e) => e.value == val,
        orElse: () => throw ArgumentError("Unknown message class value: $val"));
  }
}

// Based on messagemethod.go
enum StunMessageMethod {
  binding(0x0001, "Binding"),
  // Add other methods if needed
  allocate(0x0003, "Allocate"),
  refresh(0x0004, "Refresh");

  const StunMessageMethod(this.value, this.name);
  final int value;
  final String name;

  static StunMessageMethod fromVal(int val) {
    return StunMessageMethod.values.firstWhere((e) => e.value == val,
        orElse: () =>
            throw ArgumentError("Unknown message method value: $val"));
  }
}

// Based on atttributetype.go (renamed to avoid typo)
enum StunAttributeType {
  // STUN attributes
  mappedAddress(0x0001, "MAPPED-ADDRESS"),
  responseAddress(0x0002, "RESPONSE-ADDRESS"),
  changeRequest(0x0003, "CHANGE-REQUEST"),
  sourceAddress(0x0004, "SOURCE-ADDRESS"),
  changedAddress(0x0005, "CHANGED-ADDRESS"),
  username(0x0006, "USERNAME"),
  password(0x0007, "PASSWORD"),
  messageIntegrity(0x0008, "MESSAGE-INTEGRITY"),
  errorCode(0x0009, "ERROR-CODE"),
  unknownAttributes(0x000A, "UNKNOWN-ATTRIBUTES"),
  reflectedFrom(0x000B, "REFLECTED-FROM"),
  realm(0x0014, "REALM"),
  nonce(0x0015, "NONCE"),
  xorMappedAddress(0x0020, "XOR-MAPPED-ADDRESS"),
  software(0x8022, "SOFTWARE"),
  alternateServer(0x8023, "ALTERNATE-SERVER"),
  fingerprint(0x8028, "FINGERPRINT"),

  // ICE attributes
  priority(0x0024, "PRIORITY"),
  useCandidate(0x0025, "USE-CANDIDATE"),
  iceControlled(0x8029, "ICE-CONTROLLED"),
  iceControlling(0x802A, "ICE-CONTROLLING");

  const StunAttributeType(this.value, this.name);
  final int value;
  final String name;

  static StunAttributeType fromVal(int val) {
    return StunAttributeType.values.firstWhere((e) => e.value == val,
        orElse: () =>
            throw ArgumentError("Unknown attribute type value: $val"));
  }

  bool get isComprehensionRequired => (value & 0x8000) == 0;
}

// Based on attribute.go
class StunAttribute {
  final StunAttributeType type;
  Uint8List value; // Make it non-final to allow modification for padding
  final int offsetInMessage; // For validation, if needed

  StunAttribute(this.type, this.value, {this.offsetInMessage = 0});

  int get rawDataLength => value.length;
  int get paddedLength {
    int len = value.length;
    return len + (4 - (len % 4)) % 4;
  }

  int get fullLength => stunAttributeHeaderSize + paddedLength;

  factory StunAttribute.decode(Uint8List buffer, int offset) {
    if (buffer.length - offset < stunAttributeHeaderSize) {
      throw ArgumentError("Buffer too short for STUN attribute header");
    }
    var bd = ByteData.sublistView(buffer, offset);
    int typeVal = bd.getUint16(0, Endian.big);
    int length = bd.getUint16(2, Endian.big);

    if (buffer.length - offset - stunAttributeHeaderSize < length) {
      throw ArgumentError("Buffer too short for STUN attribute value");
    }

    Uint8List valueBytes = buffer.sublist(offset + stunAttributeHeaderSize,
        offset + stunAttributeHeaderSize + length);

    return StunAttribute(StunAttributeType.fromVal(typeVal), valueBytes,
        offsetInMessage: offset);
  }

  Uint8List encode() {
    int currentPaddedLength = value.length + (4 - (value.length % 4)) % 4;
    Uint8List paddedValue = Uint8List(currentPaddedLength);
    paddedValue.setRange(0, value.length, value);

    var builder = BytesBuilder();
    var headerData = ByteData(stunAttributeHeaderSize);
    headerData.setUint16(0, type.value, Endian.big);
    headerData.setUint16(
        2, value.length, Endian.big); // Original length, not padded
    builder.add(headerData.buffer.asUint8List());
    builder.add(paddedValue);
    return builder.toBytes();
  }

  @override
  String toString() {
    String valStr;
    if (type == StunAttributeType.username ||
        type == StunAttributeType.software ||
        type == StunAttributeType.realm) {
      try {
        valStr = utf8.decode(value);
      } catch (e) {
        valStr = hex.encode(value);
      }
    } else if (type == StunAttributeType.xorMappedAddress) {
      valStr = decodeXorMappedAddressAttribute(this, Uint8List(12))
          .toString(); // Dummy TX ID for string
    } else {
      valStr = hex.encode(value);
    }
    return '${type.name}: $valStr (len=${value.length})';
  }
}

// Based on message.go
class StunMessage {
  StunMessageType messageType;
  Uint8List transactionId; // 12 bytes
  Map<StunAttributeType, StunAttribute> attributes;
  Uint8List? rawMessage; // For validation

  StunMessage({
    required this.messageType,
    required this.transactionId,
    Map<StunAttributeType, StunAttribute>? attributes,
    this.rawMessage,
  }) : attributes = attributes ?? {};

  static bool isStunMessage(Uint8List buffer, {int offset = 0}) {
    if (buffer.length - offset < stunMessageHeaderSize) {
      return false;
    }
    // First two bits of a STUN message must be 00
    if ((buffer[offset] & 0xC0) != 0) {
      return false;
    }
    var bd = ByteData.sublistView(buffer, offset);
    return bd.getUint32(4, Endian.big) == stunMagicCookie;
  }

  factory StunMessage.decode(Uint8List buffer, {int offset = 0}) {
    if (!isStunMessage(buffer, offset: offset)) {
      throw ArgumentError(
          "Not a valid STUN message (magic cookie or first bits mismatch)");
    }
    if (buffer.length - offset < stunMessageHeaderSize) {
      throw ArgumentError("Buffer too short for STUN message header");
    }

    var bd = ByteData.sublistView(buffer, offset);
    int typeVal = bd.getUint16(0, Endian.big);
    int messageLength = bd.getUint16(2, Endian.big); // Length of attributes

    if (buffer.length - offset - stunMessageHeaderSize < messageLength) {
      throw ArgumentError(
          "Buffer too short for STUN message attributes. Expected $messageLength, got ${buffer.length - offset - stunMessageHeaderSize}");
    }

    Uint8List transactionId = buffer.sublist(
        offset + stunMessageHeaderSize - stunTransactionIdSize,
        offset + stunMessageHeaderSize);

    Map<StunAttributeType, StunAttribute> attributes = {};
    int currentOffset = offset + stunMessageHeaderSize;
    int attributesEndOffset = currentOffset + messageLength;

    while (currentOffset < attributesEndOffset) {
      if (attributesEndOffset - currentOffset < stunAttributeHeaderSize) {
        // Not enough bytes for an attribute header, possibly padding or malformed
        break;
      }
      StunAttribute attr = StunAttribute.decode(buffer, currentOffset);
      attributes[attr.type] = attr;
      currentOffset += attr.fullLength;
    }

    return StunMessage(
      messageType: StunMessageType.decode(typeVal),
      transactionId: transactionId,
      attributes: attributes,
      rawMessage: buffer.sublist(
          offset, offset + stunMessageHeaderSize + messageLength),
    );
  }

  Uint8List encode({String? password}) {
    // Prepare attributes for encoding (remove integrity/fingerprint, add software)
    // This order is important for integrity calculation
    Map<StunAttributeType, StunAttribute> attrsToEncode = Map.from(attributes);
    attrsToEncode.remove(StunAttributeType.messageIntegrity);
    attrsToEncode.remove(StunAttributeType.fingerprint);
    attrsToEncode[StunAttributeType.software] = StunAttribute(
        StunAttributeType.software, utf8.encode("Dart STUN Server v1.0"));

    var attrBuilder = BytesBuilder();
    // Sort attributes for consistent encoding, though not strictly required by RFC 5389 for all cases
    // However, some implementations might expect a certain order or it helps in debugging.
    // For simplicity here, we'll iterate as is, but for production, consider sorting if issues arise.
    attrsToEncode.values.forEach((attr) {
      attrBuilder.add(attr.encode());
    });
    Uint8List encodedAttributes = attrBuilder.toBytes();

    // Initial message construction (without integrity and fingerprint)
    var messageBuilder = BytesBuilder();
    var headerData = ByteData(stunMessageHeaderSize);
    headerData.setUint16(0, messageType.encode(), Endian.big);
    // Length here is attributes length, will be updated later if integrity/fingerprint added
    headerData.setUint16(2, encodedAttributes.length, Endian.big);
    headerData.setUint32(4, stunMagicCookie, Endian.big);
    messageBuilder.add(
        headerData.buffer.asUint8List().sublist(0, 8)); // Type, Length, Cookie
    messageBuilder.add(transactionId); // Transaction ID
    messageBuilder.add(encodedAttributes);

    Uint8List messageBeforeIntegrityAndFingerprint = messageBuilder.toBytes();
    Uint8List finalMessage = messageBeforeIntegrityAndFingerprint;

    if (password != null) {
      // Calculate and add MESSAGE-INTEGRITY
      // The length in the header needs to be temporarily adjusted for HMAC calculation
      ByteData tempBd = ByteData.sublistView(finalMessage);
      tempBd.setUint16(
          2,
          (finalMessage.length - stunMessageHeaderSize) +
              stunAttributeHeaderSize +
              stunHmacSignatureSize,
          Endian.big);

      Uint8List hmac = calculateHmacSha1(finalMessage, password);
      StunAttribute integrityAttr =
          StunAttribute(StunAttributeType.messageIntegrity, hmac);
      finalMessage =
          Uint8List.fromList([...finalMessage, ...integrityAttr.encode()]);
    }

    // Calculate and add FINGERPRINT
    // The length in the header needs to be temporarily adjusted for CRC32 calculation
    ByteData tempBdFp = ByteData.sublistView(finalMessage);
    tempBdFp.setUint16(
        2,
        (finalMessage.length - stunMessageHeaderSize) +
            stunAttributeHeaderSize +
            stunFingerprintSize,
        Endian.big);

    Uint8List fingerprint = calculateFingerprint(finalMessage);
    StunAttribute fingerprintAttr =
        StunAttribute(StunAttributeType.fingerprint, fingerprint);
    finalMessage =
        Uint8List.fromList([...finalMessage, ...fingerprintAttr.encode()]);

    // Final update of the message length in the header
    ByteData finalBd = ByteData.sublistView(finalMessage);
    finalBd.setUint16(
        2, finalMessage.length - stunMessageHeaderSize, Endian.big);

    return finalMessage;
  }

  bool validate({String? ufrag, String? password}) {
    // Validate USERNAME if ufrag is provided
    if (ufrag != null) {
      final usernameAttr = attributes[StunAttributeType.username];
      if (usernameAttr == null) {
        print(
            "Validation Error: MESSAGE-INTEGRITY present but USERNAME attribute is missing.");
        return false;
      }
      final parts = utf8.decode(usernameAttr.value).split(':');
      if (parts.isEmpty || parts[0] != ufrag) {
        print(
            "Validation Error: USERNAME mismatch. Expected ufrag '$ufrag', got '${parts[0]}'");
        return false;
      }
    }

    // Validate MESSAGE-INTEGRITY if present
    final integrityAttr = attributes[StunAttributeType.messageIntegrity];
    if (integrityAttr != null) {
      if (password == null) {
        print(
            "Validation Error: MESSAGE-INTEGRITY present but no password provided for validation.");
        return false;
      }
      if (rawMessage == null) {
        print(
            "Validation Error: Raw message not available for MESSAGE-INTEGRITY check.");
        return false;
      }

      // Message up to (but not including) MESSAGE-INTEGRITY attribute
      int lengthBeforeIntegrity = integrityAttr.offsetInMessage;
      Uint8List messageToHash = rawMessage!.sublist(0, lengthBeforeIntegrity);

      // Temporarily adjust message length in the header for HMAC calculation
      // The length should be of the message as if MESSAGE-INTEGRITY was the *last* attribute
      // and its value was not yet known.
      Uint8List tempMessageToHash =
          Uint8List.fromList(messageToHash); // Create a mutable copy
      ByteData bd = ByteData.sublistView(tempMessageToHash);
      bd.setUint16(
          2,
          (lengthBeforeIntegrity - stunMessageHeaderSize) +
              stunAttributeHeaderSize +
              stunHmacSignatureSize,
          Endian.big);

      Uint8List calculatedHmac = calculateHmacSha1(tempMessageToHash, password);
      if (!_compareBytes(calculatedHmac, integrityAttr.value)) {
        print("Validation Error: MESSAGE-INTEGRITY mismatch.");
        print("  Expected: ${hex.encode(calculatedHmac)}");
        print("  Received: ${hex.encode(integrityAttr.value)}");
        print("  Password used: $password");
        return false;
      }
    }

    // Validate FINGERPRINT if present
    final fingerprintAttr = attributes[StunAttributeType.fingerprint];
    if (fingerprintAttr != null) {
      if (rawMessage == null) {
        print(
            "Validation Error: Raw message not available for FINGERPRINT check.");
        return false;
      }
      // Message up to (but not including) FINGERPRINT attribute
      int lengthBeforeFingerprint = fingerprintAttr.offsetInMessage;
      Uint8List messageForCrc = rawMessage!.sublist(0, lengthBeforeFingerprint);

      // Temporarily adjust message length in the header for CRC calculation
      Uint8List tempMessageForCrc =
          Uint8List.fromList(messageForCrc); // Create a mutable copy
      ByteData bd = ByteData.sublistView(tempMessageForCrc);
      bd.setUint16(
          2,
          (lengthBeforeFingerprint - stunMessageHeaderSize) +
              stunAttributeHeaderSize +
              stunFingerprintSize,
          Endian.big);

      Uint8List calculatedCrc = calculateFingerprint(tempMessageForCrc);
      if (!_compareBytes(calculatedCrc, fingerprintAttr.value)) {
        print("Validation Error: FINGERPRINT mismatch.");
        print("  Expected: ${hex.encode(calculatedCrc)}");
        print("  Received: ${hex.encode(fingerprintAttr.value)}");
        return false;
      }
    }
    return true;
  }

  bool _compareBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() {
    var sb = StringBuffer();
    sb.writeln('STUN Message:');
    sb.writeln('  Type: $messageType');
    sb.writeln('  Transaction ID: ${hex.encode(transactionId)}');
    sb.writeln('  Attributes:');
    attributes.forEach((key, value) {
      sb.writeln('    $value');
    });
    return sb.toString();
  }
}

// --- Cryptographic Functions ---
Uint8List calculateHmacSha1(Uint8List message, String keyString) {
  var key = utf8.encode(keyString);
  var hmacSha1 = Hmac(sha1, key);
  var digest = hmacSha1.convert(message);
  return Uint8List.fromList(digest.bytes);
}

// Dart's CRC32 implementation might differ from Go's hash/crc32.ChecksumIEEE.
// For STUN, it's CRC-32-IEEE which is often standard.
// The `archive` package has a CRC32 implementation. For simplicity,
// we'll use a basic one. If issues arise, a more robust library might be needed.
// Or, more directly, implement the polynomial 0xEDB88320 (reversed 0x04C11DB7)
int _crc32IeeePolynomial = 0xEDB88320;
List<int>? _crc32Table;

void _ensureCrc32Table() {
  if (_crc32Table != null) return;
  _crc32Table = List<int>.filled(256, 0);
  for (int i = 0; i < 256; i++) {
    int crc = i;
    for (int j = 0; j < 8; j++) {
      if ((crc & 1) == 1) {
        crc = (crc >> 1) ^ _crc32IeeePolynomial;
      } else {
        crc >>= 1;
      }
    }
    _crc32Table![i] = crc;
  }
}

int crc32Ieee(Uint8List data) {
  _ensureCrc32Table();
  int crc = 0xFFFFFFFF;
  for (int byte in data) {
    crc = (crc >> 8) ^ _crc32Table![(crc & 0xFF) ^ byte];
  }
  return crc ^ 0xFFFFFFFF;
}

Uint8List calculateFingerprint(Uint8List message) {
  // The length in the header is already adjusted before this call in encode/validate
  int crc = crc32Ieee(message);
  int fingerprintValue = crc ^ stunFingerprintXorMask;

  var bd = ByteData(4);
  bd.setInt32(0, fingerprintValue, Endian.big); // STUN uses big-endian
  return bd.buffer.asUint8List();
}

// --- Attribute Specific Encoders/Decoders ---

// Based on attributes.go
enum StunIpFamily {
  ipv4(0x01),
  ipv6(0x02);

  const StunIpFamily(this.value);
  final int value;
}

class MappedAddress {
  final StunIpFamily ipFamily;
  final InternetAddress ip;
  final int port;

  MappedAddress(this.ipFamily, this.ip, this.port);

  @override
  String toString() {
    return 'Family: ${ipFamily.name}, IP: ${ip.address}, Port: $port';
  }
}

StunAttribute createXorMappedAddressAttribute(
    InternetAddress address, int port, Uint8List transactionId) {
  var valueBuilder = BytesBuilder();
  valueBuilder.addByte(0); // Reserved, must be 0

  if (address.type == InternetAddressType.IPv4) {
    valueBuilder.addByte(StunIpFamily.ipv4.value);
  } else {
    valueBuilder.addByte(StunIpFamily.ipv6.value);
  }

  // XOR Port
  var portBytes = ByteData(2);
  portBytes.setUint16(0, port, Endian.big);
  int xorPort = port ^
      (stunMagicCookie >> 16); // Use upper 16 bits of magic cookie for port XOR
  var xorPortBytes = ByteData(2);
  xorPortBytes.setUint16(0, xorPort, Endian.big);
  valueBuilder.add(xorPortBytes.buffer.asUint8List());

  // XOR IP Address
  Uint8List ipBytes = address.rawAddress;
  Uint8List xorIpBytes = Uint8List(ipBytes.length);
  var magicCookieBytes = ByteData(4)..setUint32(0, stunMagicCookie, Endian.big);

  if (address.type == InternetAddressType.IPv4) {
    for (int i = 0; i < 4; i++) {
      xorIpBytes[i] = ipBytes[i] ^ magicCookieBytes.getUint8(i);
    }
  } else {
    // IPv6
    var fullTransactionIdForXor = Uint8List.fromList([
      ...magicCookieBytes.buffer.asUint8List(),
      ...transactionId
    ]); // 4 + 12 = 16 bytes
    for (int i = 0; i < 16; i++) {
      xorIpBytes[i] = ipBytes[i] ^ fullTransactionIdForXor[i];
    }
  }
  valueBuilder.add(xorIpBytes);

  return StunAttribute(
      StunAttributeType.xorMappedAddress, valueBuilder.toBytes());
}

MappedAddress decodeXorMappedAddressAttribute(
    StunAttribute attribute, Uint8List transactionId) {
  if (attribute.type != StunAttributeType.xorMappedAddress) {
    throw ArgumentError("Attribute is not XOR-MAPPED-ADDRESS");
  }
  ByteData valueBd = ByteData.sublistView(attribute.value);
  // int reserved = valueBd.getUint8(0); // Should be 0
  StunIpFamily family = (valueBd.getUint8(1) == StunIpFamily.ipv4.value)
      ? StunIpFamily.ipv4
      : StunIpFamily.ipv6;

  int xorPort = valueBd.getUint16(2, Endian.big);
  int port = xorPort ^ (stunMagicCookie >> 16);

  Uint8List xorIp;
  InternetAddress ipAddress;
  var magicCookieBytes = ByteData(4)..setUint32(0, stunMagicCookie, Endian.big);

  if (family == StunIpFamily.ipv4) {
    if (attribute.value.length < 8)
      throw ArgumentError("XOR-MAPPED-ADDRESS IPv4 value too short");
    xorIp = attribute.value.sublist(4, 8);
    Uint8List originalIpBytes = Uint8List(4);
    for (int i = 0; i < 4; i++) {
      originalIpBytes[i] = xorIp[i] ^ magicCookieBytes.getUint8(i);
    }
    ipAddress = InternetAddress.fromRawAddress(originalIpBytes);
  } else {
    // IPv6
    if (attribute.value.length < 20)
      throw ArgumentError("XOR-MAPPED-ADDRESS IPv6 value too short");
    xorIp = attribute.value.sublist(4, 20);
    Uint8List originalIpBytes = Uint8List(16);
    var fullTransactionIdForXor = Uint8List.fromList(
        [...magicCookieBytes.buffer.asUint8List(), ...transactionId]);
    for (int i = 0; i < 16; i++) {
      originalIpBytes[i] = xorIp[i] ^ fullTransactionIdForXor[i];
    }
    ipAddress = InternetAddress.fromRawAddress(originalIpBytes);
  }
  return MappedAddress(family, ipAddress, port);
}

// --- STUN Server ---
class StunServer {
  final InternetAddress _host;
  final int _port;
  RawDatagramSocket? _socket;
  final String serverUfrag; // For validating incoming requests if needed
  final String serverPassword; // For MESSAGE-INTEGRITY

  StunServer(this._host, this._port,
      {this.serverUfrag = "default-ufrag",
      this.serverPassword = "default-password"});

  Future<void> start() async {
    try {
      _socket = await RawDatagramSocket.bind(_host, _port);
      print(
          'STUN server listening on ${_socket!.address.host}:${_socket!.port}');
      print('Server Ufrag: $serverUfrag, Server Password: $serverPassword');

      _socket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? datagram = _socket!.receive();
          if (datagram != null) {
            _handleDatagram(datagram);
          }
        }
      });
    } catch (e) {
      print('Error starting STUN server: $e');
    }
  }

  void _handleDatagram(Datagram datagram) {
    print(
        '\nReceived ${datagram.data.length} bytes from ${datagram.address.host}:${datagram.port}');
    // print('Raw data (hex): ${hex.encode(datagram.data)}');

    if (!StunMessage.isStunMessage(datagram.data)) {
      print('Not a STUN message. Ignoring.');
      return;
    }

    try {
      StunMessage request = StunMessage.decode(datagram.data);
      print('Decoded STUN Request:');
      print(request);

      // Validate the request (optional, but good practice)
      // For binding requests, password might be derived from USERNAME if ICE is fully implemented.
      // Here, we use the serverPassword.
      bool isValid =
          request.validate(ufrag: serverUfrag, password: serverPassword);
      if (!isValid) {
        print("STUN Request validation failed. Ignoring.");
        // Optionally send an error response
        return;
      }

      if (request.messageType.method == StunMessageMethod.binding &&
          request.messageType.messageClass == StunMessageClass.request) {
        print('Handling STUN Binding Request...');
        _handleBindingRequest(request, datagram.address, datagram.port);
      } else {
        print(
            'Received unsupported STUN message type: ${request.messageType}. Ignoring.');
        // Optionally send an ErrorResponse with 400 Bad Request or 500 Server Error
      }
    } catch (e, s) {
      print('Error decoding STUN message: $e');
      print('Stack trace: $s');
      // print('Problematic raw data (hex): ${hex.encode(datagram.data)}');
    }
  }

  void _handleBindingRequest(
      StunMessage request, InternetAddress clientAddress, int clientPort) {
    // Create Binding Success Response
    StunMessage response = StunMessage(
      messageType: StunMessageType.bindingSuccessResponse,
      transactionId: request.transactionId, // Must be the same transaction ID
      attributes: {},
    );

    // Add XOR-MAPPED-ADDRESS attribute
    response.attributes[StunAttributeType.xorMappedAddress] =
        createXorMappedAddressAttribute(
            clientAddress, clientPort, request.transactionId);

    // Add USERNAME attribute (if present in request, reflect it)
    // This is important for ICE. The password for MESSAGE-INTEGRITY is often
    // the ICE password associated with this username.
    String? requestUsername;
    if (request.attributes.containsKey(StunAttributeType.username)) {
      response.attributes[StunAttributeType.username] =
          request.attributes[StunAttributeType.username]!;
      try {
        requestUsername =
            utf8.decode(request.attributes[StunAttributeType.username]!.value);
      } catch (_) {}
    }

    // Add SOFTWARE attribute (already handled in encode)
    // Add MESSAGE-INTEGRITY and FINGERPRINT (handled in encode)

    // The password for encoding the response's MESSAGE-INTEGRITY.
    // In a full ICE implementation, this password would be tied to the ufrag.
    // For simplicity, we use the server's global password.
    String passwordForResponse = serverPassword;

    Uint8List encodedResponse = response.encode(password: passwordForResponse);

    print(
        'Sending STUN Binding Success Response to ${clientAddress.host}:$clientPort');
    print('Response Message:');
    // Re-decode for printing (optional, good for debugging)
    try {
      StunMessage decodedSentResponse = StunMessage.decode(encodedResponse);
      print(decodedSentResponse);
    } catch (e) {
      print("Could not decode the sent response for logging: $e");
    }
    // print('Encoded response (hex): ${hex.encode(encodedResponse)}');

    _socket?.send(encodedResponse, clientAddress, clientPort);
  }

  void stop() {
    print('Stopping STUN server...');
    _socket?.close();
  }
}

// --- Main Function to Run the Server ---
Future<void> main(List<String> arguments) async {
  // Use 0.0.0.0 to listen on all available network interfaces
  final host = InternetAddress.anyIPv4;
  // Standard STUN port is 3478, but can be changed
  final port =
      arguments.isNotEmpty ? (int.tryParse(arguments[0]) ?? 4444) : 4444;
  final ufrag = arguments.length > 1 ? arguments[1] : "testufrag";
  final password = arguments.length > 2 ? arguments[2] : "testpassword";

  final server =
      StunServer(host, port, serverUfrag: ufrag, serverPassword: password);
  await server.start();

  // // Keep the server running until interrupted
  // ProcessSignal.sigint.watch().listen((signal) {
  //   print('Received SIGINT. Shutting down...');
  //   server.stop();
  //   exit(0);
  // });

  // ProcessSignal.sigterm.watch().listen((signal) {
  //   print('Received SIGTERM. Shutting down...');
  //   server.stop();
  //   exit(0);
  // });
}
