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

  // Override equality and hashCode for proper comparison
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StunMessageType &&
          runtimeType == other.runtimeType &&
          method == other.method &&
          messageClass == other.messageClass;

  @override
  int get hashCode => method.hashCode ^ messageClass.hashCode;

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

// Based on atttributetype.go
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
  iceControlling(0x802A, "ICE-CONTROLLING"),
  iceControlling2(0xC057, "ICE-CONTROLLING");

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
  Uint8List value;
  final int offsetInMessage;

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
    headerData.setUint16(2, value.length, Endian.big);
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
      // Need a dummy transaction ID for decoding this attribute in isolation
      valStr = decodeXorMappedAddressAttribute(this, Uint8List(12)).toString();
    } else if (type == StunAttributeType.priority) {
      if (value.length >= 4) {
        valStr =
            ByteData.sublistView(value).getUint32(0, Endian.big).toString();
      } else {
        valStr = hex.encode(value);
      }
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
    int messageLength = bd.getUint16(2, Endian.big);

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
    Map<StunAttributeType, StunAttribute> attrsToEncode = Map.from(attributes);
    attrsToEncode.remove(StunAttributeType.messageIntegrity);
    attrsToEncode.remove(StunAttributeType.fingerprint);
    attrsToEncode[StunAttributeType.software] = StunAttribute(
        StunAttributeType.software, utf8.encode("Dart STUN Client v1.1"));

    var attrBuilder = BytesBuilder();
    attrsToEncode.values.forEach((attr) {
      attrBuilder.add(attr.encode());
    });
    Uint8List encodedAttributes = attrBuilder.toBytes();

    var messageBuilder = BytesBuilder();
    var headerData = ByteData(stunMessageHeaderSize);
    headerData.setUint16(0, messageType.encode(), Endian.big);
    headerData.setUint16(2, encodedAttributes.length, Endian.big);
    headerData.setUint32(4, stunMagicCookie, Endian.big);
    messageBuilder.add(headerData.buffer.asUint8List().sublist(0, 8));
    messageBuilder.add(transactionId);
    messageBuilder.add(encodedAttributes);

    Uint8List messageBeforeIntegrityAndFingerprint = messageBuilder.toBytes();
    Uint8List finalMessage = messageBeforeIntegrityAndFingerprint;

    if (password != null) {
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

    ByteData finalBd = ByteData.sublistView(finalMessage);
    finalBd.setUint16(
        2, finalMessage.length - stunMessageHeaderSize, Endian.big);

    return finalMessage;
  }

  /// Validates the STUN message.
  /// [expectedServerUfrag] is the ufrag of this STUN server.
  /// [expectedClientUfrag] is the ufrag of the client this server expects for this session.
  /// [passwordForIntegrity] is the password associated with [expectedServerUfrag], used for MESSAGE-INTEGRITY.
  bool validate({
    String? expectedServerUfrag, // Made optional for client-side validation
    String? expectedClientUfrag, // Made optional for client-side validation
    String? passwordForIntegrity, // Made optional for client-side validation
  }) {
    // Client-side validation might be simpler, mainly checking message type and basic integrity.
    // For a client, validating the USERNAME might not be necessary, or it might validate
    // that its *own* ufrag is present if it's sent.
    // The server would validate the combined username and password.

    // Validate MESSAGE-INTEGRITY if present and password is provided
    final integrityAttr = attributes[StunAttributeType.messageIntegrity];
    if (integrityAttr != null && passwordForIntegrity != null) {
      if (rawMessage == null) {
        print(
            "Validation Error: Raw message not available for MESSAGE-INTEGRITY check.");
        return false;
      }

      // The length calculation needs to be precise for validation
      // It's the length of the message *before* the MESSAGE-INTEGRITY attribute
      // but with the length field in the header updated as if MESSAGE-INTEGRITY
      // was already included.
      int lengthOfMessageBeforeIntegrity = integrityAttr.offsetInMessage;
      Uint8List messageToHash = Uint8List.fromList(
          rawMessage!.sublist(0, lengthOfMessageBeforeIntegrity));

      ByteData bd = ByteData.sublistView(messageToHash);
      // Temporarily set the length field in the header to include the size
      // of the MESSAGE-INTEGRITY attribute and its header
      bd.setUint16(
          2,
          (lengthOfMessageBeforeIntegrity - stunMessageHeaderSize) +
              stunAttributeHeaderSize +
              stunHmacSignatureSize,
          Endian.big);

      Uint8List calculatedHmac =
          calculateHmacSha1(messageToHash, passwordForIntegrity);
      if (!_compareBytes(calculatedHmac, integrityAttr.value)) {
        print("Validation Error: MESSAGE-INTEGRITY mismatch.");
        print("  Expected: ${hex.encode(calculatedHmac)}");
        print("  Received: ${hex.encode(integrityAttr.value)}");
        return false;
      }
    } else if (integrityAttr != null && passwordForIntegrity == null) {
      print(
          "Warning: MESSAGE-INTEGRITY attribute present but no password provided for validation.");
    }

    // Validate FINGERPRINT if present
    final fingerprintAttr = attributes[StunAttributeType.fingerprint];
    if (fingerprintAttr != null) {
      if (rawMessage == null) {
        print(
            "Validation Error: Raw message not available for FINGERPRINT check.");
        return false;
      }
      // The length calculation needs to be precise for validation
      // It's the length of the message *before* the FINGERPRINT attribute
      // but with the length field in the header updated as if FINGERPRINT
      // was already included.
      int lengthBeforeFingerprint = fingerprintAttr.offsetInMessage;
      Uint8List messageForCrc =
          Uint8List.fromList(rawMessage!.sublist(0, lengthBeforeFingerprint));

      ByteData bd = ByteData.sublistView(messageForCrc);
      // Temporarily set the length field in the header to include the size
      // of the FINGERPRINT attribute and its header
      bd.setUint16(
          2,
          (lengthBeforeFingerprint - stunMessageHeaderSize) +
              stunAttributeHeaderSize +
              stunFingerprintSize,
          Endian.big);

      Uint8List calculatedCrc = calculateFingerprint(messageForCrc);
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
  int crc = crc32Ieee(message);
  int fingerprintValue = crc ^ stunFingerprintXorMask;

  var bd = ByteData(4);
  bd.setInt32(0, fingerprintValue, Endian.big);
  return bd.buffer.asUint8List();
}

// --- Attribute Specific Encoders/Decoders ---

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
  valueBuilder.addByte(0);

  if (address.type == InternetAddressType.IPv4) {
    valueBuilder.addByte(StunIpFamily.ipv4.value);
  } else {
    valueBuilder.addByte(StunIpFamily.ipv6.value);
  }

  var portBytes = ByteData(2);
  portBytes.setUint16(0, port, Endian.big);
  int xorPort = port ^ (stunMagicCookie >> 16);
  var xorPortBytes = ByteData(2);
  xorPortBytes.setUint16(0, xorPort, Endian.big);
  valueBuilder.add(xorPortBytes.buffer.asUint8List());

  Uint8List ipBytes = address.rawAddress;
  Uint8List xorIpBytes = Uint8List(ipBytes.length);
  var magicCookieBytes = ByteData(4)..setUint32(0, stunMagicCookie, Endian.big);

  if (address.type == InternetAddressType.IPv4) {
    for (int i = 0; i < 4; i++) {
      xorIpBytes[i] = ipBytes[i] ^ magicCookieBytes.getUint8(i);
    }
  } else {
    var fullTransactionIdForXor = Uint8List.fromList(
        [...magicCookieBytes.buffer.asUint8List(), ...transactionId]);
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

// --- STUN Client ---
class StunClient {
  final InternetAddress _serverHost;
  final int _serverPort;
  final String clientUfrag;
  final String serverUfrag;
  final String serverPassword; // Password for integrity check

  final _random = Random.secure();

  StunClient(this._serverHost, this._serverPort,
      {required this.clientUfrag,
      required this.serverUfrag,
      required this.serverPassword});

  Uint8List _generateTransactionId() {
    return Uint8List.fromList(
        List<int>.generate(stunTransactionIdSize, (i) => _random.nextInt(256)));
  }

  Future<void> sendBindingRequest({
    required int localPort,
    int? priority,
    bool useCandidate = false,
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, localPort);
      print(
          '\nSTUN Client bound to local address for candidate: ${socket.address.host}:${socket.port}');

      Uint8List transactionId = _generateTransactionId();

      StunAttribute? usernameAttr;
      if (clientUfrag.isNotEmpty && serverUfrag.isNotEmpty) {
        String usernameString = '$serverUfrag:$clientUfrag';
        usernameAttr = StunAttribute(
            StunAttributeType.username, utf8.encode(usernameString));
      }

      final Map<StunAttributeType, StunAttribute> attributes = {
        if (usernameAttr != null) StunAttributeType.username: usernameAttr,
      };

      if (priority != null) {
        final priorityBytes = ByteData(4)..setUint32(0, priority, Endian.big);
        attributes[StunAttributeType.priority] = StunAttribute(
            StunAttributeType.priority, priorityBytes.buffer.asUint8List());
      }

      if (useCandidate) {
        attributes[StunAttributeType.useCandidate] = StunAttribute(
            StunAttributeType.useCandidate,
            Uint8List(0)); // Zero-length attribute
      }

      StunMessage request = StunMessage(
        messageType: StunMessageType.bindingRequest,
        transactionId: transactionId,
        attributes: attributes,
      );

      Uint8List encodedRequest = request.encode(
          password: serverPassword.isNotEmpty ? serverPassword : null);

      print('Sending STUN Binding Request for candidate '
          'from local port $localPort to '
          '${_serverHost.host}:${_serverPort} with Transaction ID: '
          '${hex.encode(transactionId)}');

      try {
        StunMessage decodedSentRequest = StunMessage.decode(encodedRequest);
        print(
            'Encoded STUN Request (for verification, local port $localPort):');
        print(decodedSentRequest);
      } catch (e) {
        print(
            "Could not decode the sent request for logging (local port $localPort): $e");
      }

      socket.send(encodedRequest, _serverHost, _serverPort);

      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? datagram = socket!.receive();
          if (datagram != null) {
            _handleResponse(datagram, transactionId, localPort);
            socket.close(); // Close socket after receiving response
          }
        }
      });

      // Future.delayed(Duration(seconds: 5), () {
      //   if (socket != null && socket.isActive) {
      //     print('STUN response timed out for local port $localPort.');
      //     socket.close();
      //   }
      // });
    } catch (e) {
      print('Error sending binding request from local port $localPort: $e');
      socket?.close();
    }
  }

  void _handleResponse(
      Datagram datagram, Uint8List sentTransactionId, int localPort) {
    print(
        '\nReceived ${datagram.data.length} bytes from ${datagram.address.host}:${datagram.port} for local port $localPort');

    if (!StunMessage.isStunMessage(datagram.data)) {
      print('Not a STUN message. Ignoring for local port $localPort.');
      return;
    }

    try {
      StunMessage response = StunMessage.decode(datagram.data);
      print('Decoded STUN Response for local port $localPort:');
      print(response);

      if (!const ListEquality()
          .equals(response.transactionId, sentTransactionId)) {
        print('Error: Transaction ID mismatch for local port $localPort.');
        return;
      }

      bool isValid = response.validate(
          passwordForIntegrity:
              serverPassword.isNotEmpty ? serverPassword : null);
      if (!isValid) {
        print("STUN Response validation failed for local port $localPort.");
      }

      if (response.messageType == StunMessageType.bindingSuccessResponse) {
        print(
            'STUN Binding Success Response received for local port $localPort!');
        final xorMappedAddressAttr =
            response.attributes[StunAttributeType.xorMappedAddress];
        if (xorMappedAddressAttr != null) {
          final mappedAddress = decodeXorMappedAddressAttribute(
              xorMappedAddressAttr, response.transactionId);
          print('Candidate from local port $localPort:');
          print('  External IP: ${mappedAddress.ip.address}');
          print('  External Port: ${mappedAddress.port}');
        } else {
          print(
              'XOR-MAPPED-ADDRESS attribute not found in response for local port $localPort.');
        }
      } else if (response.messageType == StunMessageType.bindingErrorResponse) {
        print(
            'STUN Binding Error Response received for local port $localPort!');
        final errorCodeAttr = response.attributes[StunAttributeType.errorCode];
        if (errorCodeAttr != null && errorCodeAttr.value.length >= 4) {
          var bd = ByteData.sublistView(errorCodeAttr.value);
          int errorClass = bd.getUint8(2);
          int errorNumber = bd.getUint8(3);
          String reasonPhrase = '';
          if (errorCodeAttr.value.length > 4) {
            reasonPhrase = utf8.decode(errorCodeAttr.value.sublist(4));
          }
          print('Error Code: $errorClass$errorNumber - $reasonPhrase');
        }
      } else {
        print(
            'Received unexpected STUN message type: ${response.messageType} for local port $localPort.');
      }
    } catch (e, s) {
      print('Error processing STUN response for local port $localPort: $e');
      print('Stack trace: $s');
    }
  }

  // Method to send multiple binding requests for different candidates
  Future<void> sendMultipleBindingRequests(List<int> localPorts,
      {List<int>? priorities}) async {
    if (priorities != null && priorities.length != localPorts.length) {
      print(
          "Warning: Number of priorities does not match number of local ports. Priorities will be ignored.");
      priorities = null; // Ignore if lengths don't match
    }

    for (int i = 0; i < localPorts.length; i++) {
      final int currentPort = localPorts[i];
      final int? currentPriority = priorities != null ? priorities[i] : null;
      final bool useCandidate =
          i == 0; // Just an example: mark first candidate as 'Use-Candidate'

      print(
          '\n--- Sending Request for Candidate ${i + 1} (Local Port: $currentPort) ---');
      await sendBindingRequest(
        localPort: currentPort,
        priority: currentPriority,
        useCandidate: useCandidate,
      );
      // Add a small delay to avoid overwhelming the server, especially when testing locally
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  // No longer needed as sockets are closed individually
  // void stop() {
  //   _socket?.close();
  //   print('STUN Client stopped.');
  // }
}

// A simple ListEquality to compare Uint8List
class ListEquality<E> {
  const ListEquality();

  bool equals(List<E>? a, List<E>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// --- Main Function to Run the Client ---
Future<void> main(List<String> arguments) async {
  // Google's public STUN server address and port
  final serverHost =
      InternetAddress.lookup('stun.l.google.com').then((list) => list.first);
  final serverPort = 19302; // Standard STUN port

  String clientUfrag = "";
  String serverUfrag = "";
  String serverPassword = "";

  // Example local ports to simulate different ICE candidates
  // You can choose any available ports. Avoid well-known ports (<1024)
  // and ports already in use by other applications.
  List<int> candidateLocalPorts = [
    50000, // Candidate 1
    50001, // Candidate 2
    50002, // Candidate 3
  ];

  // Example priorities for the candidates (higher value means higher priority)
  List<int> candidatePriorities = [
    2130706431, // Typically highest for host candidates over UDP
    2130706430, // Slightly lower
    2130706429, // Even lower
  ];

  // Override server details if command-line arguments are provided
  // if (arguments.length > 0) {
  //   serverHost = InternetAddress.lookup(arguments[0]).then((list) => list.first);
  // }
  // if (arguments.length > 1) serverPort = int.tryParse(arguments[1]) ?? 19302;
  // // Further arguments can override ufrag/password if connecting to a private STUN server
  // if (arguments.length > 2) clientUfrag = arguments[2];
  // if (arguments.length > 3) serverUfrag = arguments[3];
  // if (arguments.length > 4) serverPassword = arguments[4];

  print('STUN Client configuration:');
  print('  Server: ${(await serverHost).host}:${serverPort}');
  print('  Client Ufrag: ${clientUfrag.isEmpty ? "N/A" : clientUfrag}');
  print('  Server Ufrag: ${serverUfrag.isEmpty ? "N/A" : serverUfrag}');
  print(
      '  Server Password: ${serverPassword.isEmpty ? "N/A" : "Provided (for integrity check)"}');

  final client = StunClient(
    await serverHost,
    serverPort,
    clientUfrag: clientUfrag,
    serverUfrag: serverUfrag,
    serverPassword: serverPassword,
  );

  // Send multiple requests simulating different ICE candidates
  await client.sendMultipleBindingRequests(
    candidateLocalPorts,
    priorities: candidatePriorities,
  );

  print(
      '\nAll candidate requests sent. Responses will appear as they are received or timed out.');
}
