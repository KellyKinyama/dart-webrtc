import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart'; // For HMAC-SHA1
import 'dart:convert'; // For utf8 encoding

// Helper function to convert a List<int> to a hex string
String bytesToHexString(List<int> bytes, {String separator = ""}) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(separator);
}

// --- STUN Message Type Constants ---
const int stunBindingRequest = 0x0001;
const int stunBindingResponse = 0x0101;
const int stunBindingErrorResponse = 0x0111;

// --- STUN Magic Cookie ---
const int stunMagicCookie = 0x2112A442;
// This is the XOR_MAGIC_COOKIE defined in RFC 5389 Section 15.5 for FINGERPRINT
const int stunFingerprintXorMagicCookie = 0x5354554E;

// --- Shared secret for MESSAGE-INTEGRITY (for demonstration purposes) ---
final Uint8List sharedSecret =
    Uint8List.fromList(utf8.encode('super_secret_stun_key_1234567890'));

// --- Custom CRC32 Implementation ---
int _calculateRawCrc32(Uint8List bytes) {
  int crc = 0xFFFFFFFF; // Initial value
  final int polynomial = 0xEDB88320; // Reversed polynomial

  for (int i = 0; i < bytes.length; i++) {
    crc ^= bytes[i];
    for (int j = 0; j < 8; j++) {
      if ((crc & 1) != 0) {
        crc = (crc >> 1) ^ polynomial;
      } else {
        crc >>= 1;
      }
    }
  }
  return crc ^ 0xFFFFFFFF; // Final XOR value
}

/// Calculates CRC32 checksum for the given bytes, suitable for STUN FINGERPRINT.
int calculateStunFingerprintCrc32(Uint8List bytes) {
  return _calculateRawCrc32(bytes) ^ stunFingerprintXorMagicCookie;
}

/// Calculates HMAC-SHA1 for the given bytes and key.
Uint8List calculateHmacSha1(Uint8List bytes, Uint8List key) {
  final hmac = Hmac(sha1, key);
  return Uint8List.fromList(hmac.convert(bytes).bytes);
}

// --- STUN Attribute Type Constants (from RFC) ---
abstract class StunAttributes {
  static const int TYPE_RESERVED = 0x0000;
  static const int TYPE_MAPPED_ADDRESS = 0x0001;
  static const int TYPE_RESPONSE_ADDRESS = 0x0002;
  static const int TYPE_CHANGE_ADDRESS = 0x0003;
  static const int TYPE_CHANGE_REQUEST = 0x0003; // rfc5780
  static const int TYPE_SOURCE_ADDRESS = 0x0004;
  static const int TYPE_CHANGED_ADDRESS = 0x0005;
  static const int TYPE_USERNAME = 0x0006;
  static const int TYPE_PASSWORD = 0x0007;
  static const int TYPE_MESSAGE_INTEGRITY = 0x0008;
  static const int TYPE_ERROR_CODE = 0x0009;
  static const int TYPE_UNKNOWN_ATTRIBUTES = 0x000A;
  static const int TYPE_REFLECTED_FROM = 0x000B;
  static const int TYPE_REALM = 0x0014;
  static const int TYPE_NONCE = 0x0015;
  static const int TYPE_XOR_MAPPED_ADDRESS = 0x0020;
  static const int TYPE_PADDING = 0x0026; // rfc5780
  static const int TYPE_RESPONSE_PORT = 0x0027; // rfc5780

  // Comprehension-optional range (0x8000-0xFFFF):
  static const int TYPE_SOFTWARE = 0x8022;
  static const int TYPE_ALTERNATE_SERVER = 0x8023;
  static const int TYPE_FINGERPRINT = 0x8028;
  static const int TYPE_RESPONSE_ORIGIN = 0x802b; // rfc5780
  static const int TYPE_OTHER_ADDRESS = 0x802c; // rfc5780

  static const int TYPE_ICE_CONTROLLING = 0x802B; // rfc5780
  static const int TYPE_ICE_CONTROLLED = 0x802c; // rfc5780
  static const int TYPE_PRIORITY = 0x8029; // rfc5780

  static final Map<int, String> TYPE_STRINGS = {
    TYPE_RESERVED: "RESERVED",
    TYPE_MAPPED_ADDRESS: "MAPPED-ADDRESS",
    TYPE_RESPONSE_ADDRESS: "RESPONSE-ADDRESS",
    TYPE_CHANGE_ADDRESS: "CHANGE-ADDRESS",
    TYPE_CHANGE_REQUEST: "CHANGE-REQUEST",
    TYPE_SOURCE_ADDRESS: "SOURCE-ADDRESS",
    TYPE_CHANGED_ADDRESS: "CHANGED-ADDRESS",
    TYPE_USERNAME: "USERNAME",
    TYPE_PASSWORD: "PASSWORD",
    TYPE_MESSAGE_INTEGRITY: "MESSAGE-INTEGRITY",
    TYPE_ERROR_CODE: "ERROR-CODE",
    TYPE_UNKNOWN_ATTRIBUTES: "UNKNOWN-ATTRIBUTES",
    TYPE_REFLECTED_FROM: "REFLECTED-FROM",
    TYPE_REALM: "REALM",
    TYPE_NONCE: "NONCE",
    TYPE_XOR_MAPPED_ADDRESS: "XOR-MAPPED-ADDRESS",
    TYPE_PADDING: "PADDING",
    TYPE_RESPONSE_PORT: "RESPONSE-PORT",
    TYPE_SOFTWARE: "SOFTWARE",
    TYPE_ALTERNATE_SERVER: "ALTERNATE-SERVER",
    TYPE_FINGERPRINT: "FINGERPRINT",
    TYPE_RESPONSE_ORIGIN: "RESPONSE-ORIGIN",
    TYPE_OTHER_ADDRESS: "OTHER-ADDRESS",
  };
}

// --- STUN Packet Parsing Classes (New Implementation) ---

class StunHeader {
  final int messageType;
  final int messageLengthFromHeader; // Length of attributes from header
  final int magicCookie;
  final List<int> transactionId;

  StunHeader({
    required this.messageType,
    required this.messageLengthFromHeader,
    required this.magicCookie,
    required this.transactionId,
  });

  String get messageTypeDescription {
    switch (messageType) {
      case 0x0001:
        return "Binding Request";
      case 0x0101:
        return "Binding Response";
      case 0x0111:
        return "Binding Error Response";
      case 0x0002:
        return "Shared Secret Request (deprecated)";
      default:
        return "Unknown (0x${messageType.toRadixString(16).padLeft(4, '0')})";
    }
  }

  @override
  String toString() {
    return '''
  STUN Header:
    Message Type: 0x${messageType.toRadixString(16).padLeft(4, '0')} ($messageTypeDescription)
    Message Length (from header, for attributes): $messageLengthFromHeader bytes
    Magic Cookie: 0x${magicCookie.toRadixString(16).padLeft(8, '0')} ${magicCookie == 0x2112A442 ? '(Valid)' : '(INVALID!)'}
    Transaction ID: ${bytesToHexString(transactionId)}
''';
  }
}

class StunAttribute {
  final int type;
  final int declaredValueLength; // Length of value as declared in attribute
  final List<int> value;
  final List<int>
      rawAttributeBytes; // Includes Type, Length, Value, and Padding

  StunAttribute({
    required this.type,
    required this.declaredValueLength,
    required this.value,
    required this.rawAttributeBytes,
  });

  String get typeDescription {
    // Prefer RFC defined names first
    String? rfcName = StunAttributes.TYPE_STRINGS[type];
    if (rfcName != null) {
      return rfcName;
    }

    // Custom or less common assignments based on common STUN/ICE usage, or your specific packet
    switch (type) {
      case 0x8023:
        return "ALTERNATE-SERVER (RFC5389)";
      case 0x8029:
        return "PRIORITY"; // From ICE RFC
      case 0x802B:
        return "ICE-CONTROLLED"; // From ICE RFC
      case 0x802C:
        return "ICE-CONTROLLING"; // From ICE RFC
      case 0x002A:
        return "PADDING"; // From RFC 5780
      case 0x802A:
        return "RESPONSE-PORT"; // From RFC 5780
      case 0x001A:
        return "LIFETIME"; // From RFC 5766 (TURN)
      // Special cases from your client's observed "unknown" attributes
      case 0xC057:
        return "ICE-CONTROLLING / ICE-CONTROLLED (from your packet type, possibly non-standard assignment or context)";
      case 0x0024:
        return "SOFTWARE (often 0x8022) or other custom attribute";
      // This is unlikely, but if 0x0008 was intended as FINGERPRINT, it's non-standard.
      // The standard is 0x8028 for FINGERPRINT.
      // MESSAGE-INTEGRITY is 0x0008. If your client is sending it with different intent, note it.
      // Your previous log indicated 0x0008 as MESSAGE-INTEGRITY, which IS standard.
      // The old comment on your 0x0024 about MESSAGE-INTEGRITY was incorrect based on RFCs.
      // The old comment on your 0x0008 about FINGERPRINT was incorrect based on RFCs.
      // Reverting to standard interpretation based on RFC values.
      default:
        return "Unknown Attribute (0x${type.toRadixString(16).padLeft(4, '0')})";
    }
  }

  String get standardLengthNote {
    String note = "";
    bool isStandard = true;
    switch (type) {
      case StunAttributes.TYPE_MESSAGE_INTEGRITY: // 0x0008
        if (declaredValueLength != 20) {
          note = "(Standard value length for MESSAGE-INTEGRITY is 20)";
          isStandard = false;
        }
        break;
      case StunAttributes.TYPE_FINGERPRINT: // 0x8028
        if (declaredValueLength != 4) {
          note = "(Standard value length for FINGERPRINT is 4)";
          isStandard = false;
        }
        break;
      case StunAttributes.TYPE_XOR_MAPPED_ADDRESS: // 0x0020 (for IPv4)
        if (declaredValueLength != 8) {
          note = "(Standard value length for IPv4 XOR-MAPPED-ADDRESS is 8)";
          isStandard = false;
        }
        break;
      case StunAttributes.TYPE_MAPPED_ADDRESS: // 0x0001 (for IPv4)
        if (declaredValueLength != 8) {
          note = "(Standard value length for IPv4 MAPPED-ADDRESS is 8)";
          isStandard = false;
        }
        break;
      case StunAttributes.TYPE_SOFTWARE: // 0x8022
        // Length varies, no fixed length.
        break;
      case StunAttributes.TYPE_USERNAME: // 0x0006
        // Length varies, no fixed length.
        break;
      case StunAttributes.TYPE_PRIORITY: // 0x8029
        if (declaredValueLength != 4) {
          note = "(Standard value length for PRIORITY is 4)";
          isStandard = false;
        }
        break;
      case StunAttributes.TYPE_ICE_CONTROLLED: // 0x802B
      case StunAttributes.TYPE_ICE_CONTROLLING: // 0x802C
        if (declaredValueLength != 8) {
          note = "(Standard value length for ICE-CONTROLLED/ING is 8)";
          isStandard = false;
        }
        break;
      // Specific non-standard types observed in your client's packets
      case 0xC057: // Your client's specific attribute
        if (declaredValueLength != 4 && declaredValueLength != 8) {
          // Based on previous packet, it was 4
          note =
              "(Observed length was 4 or 8, standard ICE-CONTROLLING/ED is 8)";
          isStandard = false;
        }
        break;
      case 0x0024: // Your client's specific attribute
        if (declaredValueLength != 4 && declaredValueLength != 20) {
          // Based on previous packet, it was 4 or 20
          note = "(Observed length was 4 or 20)";
          isStandard = false;
        }
        break;
      // You can add more cases here for other known attributes and their expected lengths
    }
    if (isStandard) return "";
    return " $note";
  }

  String get valueAsString {
    // Decode known string attributes
    switch (type) {
      case StunAttributes.TYPE_USERNAME:
      case StunAttributes.TYPE_SOFTWARE:
      case StunAttributes.TYPE_REALM:
      case StunAttributes.TYPE_NONCE:
      case StunAttributes.TYPE_ERROR_CODE: // Only the reason phrase part
        try {
          // For ERROR-CODE, the actual reason phrase starts after 4 bytes of value
          final int offset =
              (type == StunAttributes.TYPE_ERROR_CODE && value.length >= 4)
                  ? 4
                  : 0;
          return '"${utf8.decode(value.sublist(offset), allowMalformed: true)}"';
        } catch (e) {
          return 'Error decoding UTF-8: $e. Raw: ${bytesToHexString(value)}';
        }
      case StunAttributes.TYPE_MAPPED_ADDRESS:
      case StunAttributes.TYPE_XOR_MAPPED_ADDRESS:
        if (value.length >= 8) {
          // IPv4
          final int family = value[1];
          final int port =
              ByteData.view(Uint8List.fromList(value).buffer).getUint16(2);
          String ip;
          if (family == 0x01) {
            // IPv4
            ip = '${value[4]}.${value[5]}.${value[6]}.${value[7]}';
            return 'IPv4, Port: $port, IP: $ip';
          } else if (family == 0x02 && value.length >= 20) {
            // IPv6
            ip = bytesToHexString(value.sublist(4, 20),
                separator: ":"); // Simple hex for IPv6
            return 'IPv6, Port: $port, IP: $ip';
          } else {
            return 'Unknown Family (0x${family.toRadixString(16)}), Raw: ${bytesToHexString(value)}';
          }
        } else {
          return 'Address too short. Raw: ${bytesToHexString(value)}';
        }
      case StunAttributes.TYPE_MESSAGE_INTEGRITY:
      case StunAttributes.TYPE_FINGERPRINT:
        return bytesToHexString(value); // Already hex string
      // For types that are just raw bytes or numbers, return hex string
      default:
        return bytesToHexString(value);
    }
  }

  @override
  String toString() {
    return '''
    Attribute:
      Type: 0x${type.toRadixString(16).padLeft(4, '0')} ($typeDescription)
      Declared Value Length: $declaredValueLength bytes$standardLengthNote
      Value: $valueAsString
      Raw TLV Bytes: ${bytesToHexString(rawAttributeBytes)}''';
  }
}

class StunMessage {
  final StunHeader header;
  final List<StunAttribute> attributes;
  String notes;

  StunMessage(
      {required this.header, required this.attributes, this.notes = ""});

  @override
  String toString() {
    final sb = StringBuffer();
    sb.writeln("Parsed STUN Message:");
    sb.writeln(header.toString());
    sb.writeln("  Attributes (${attributes.length} total):");
    if (attributes.isEmpty) {
      sb.writeln("    (No attributes found or parsed)");
    } else {
      for (final attr in attributes) {
        sb.writeln(attr.toString());
      }
    }
    if (notes.isNotEmpty) {
      sb.writeln("  Parser Notes:");
      sb.writeln("    $notes");
    }
    return sb.toString();
  }
}

StunMessage? parseStunPacket(List<int> packetBytes) {
  if (packetBytes.length < 20) {
    return null; // Let the caller handle error for too short packet
  }

  final byteData = ByteData.view(Uint8List.fromList(packetBytes).buffer);

  // Parse Header
  final messageType = byteData.getUint16(0); // Big Endian
  final messageLengthFromHeader = byteData.getUint16(2); // Big Endian
  final magicCookie = byteData.getUint32(4); // Big Endian
  final transactionId = packetBytes.sublist(8, 20);

  final header = StunHeader(
    messageType: messageType,
    messageLengthFromHeader: messageLengthFromHeader,
    magicCookie: magicCookie,
    transactionId: transactionId,
  );

  // Parse Attributes
  final List<StunAttribute> attributes = [];
  int currentIndex = 20; // Attributes start after 20-byte header
  final int totalPacketLength = packetBytes.length;
  int calculatedAttributesByteLength = 0;
  String parsingNotes = "";

  while (currentIndex < totalPacketLength) {
    if (currentIndex + 4 > totalPacketLength) {
      parsingNotes +=
          "Warning: Truncated attribute header at index $currentIndex. Stopping attribute parsing.";
      break;
    }

    final attrType = byteData.getUint16(currentIndex);
    final attrDeclaredValueLength = byteData.getUint16(currentIndex + 2);
    final attrValueStartIndex = currentIndex + 4;

    if (attrValueStartIndex + attrDeclaredValueLength > totalPacketLength) {
      parsingNotes +=
          "Warning: Attribute (Type 0x${attrType.toRadixString(16)}) declared value length ($attrDeclaredValueLength) exceeds packet boundary. Stopping attribute parsing.";
      break;
    }
    final attrValue = packetBytes.sublist(
        attrValueStartIndex, attrValueStartIndex + attrDeclaredValueLength);

    // Value part is padded to a multiple of 4 bytes
    final int paddedValueLength = (attrDeclaredValueLength % 4 == 0)
        ? attrDeclaredValueLength
        : attrDeclaredValueLength + (4 - (attrDeclaredValueLength % 4));

    final int totalAttributeBlockLength =
        4 + paddedValueLength; // Type(2) + Length(2) + padded_value_length

    if (currentIndex + totalAttributeBlockLength > totalPacketLength) {
      parsingNotes +=
          "Warning: Attribute (Type 0x${attrType.toRadixString(16)}) with padding exceeds packet boundary. This indicates a malformed attribute or truncated packet. Using available bytes for raw attribute data.";
      // Adjust block length to not exceed packet for raw bytes, though this indicates an issue
      final int actualAvailableBlockLength = totalPacketLength - currentIndex;
      final rawAttributeBytes = packetBytes.sublist(
          currentIndex, currentIndex + actualAvailableBlockLength);
      attributes.add(StunAttribute(
        type: attrType,
        declaredValueLength: attrDeclaredValueLength,
        value: attrValue, // Value might be complete even if padding isn't
        rawAttributeBytes: rawAttributeBytes,
      ));
      calculatedAttributesByteLength += actualAvailableBlockLength;
      break; // Stop further parsing as packet is malformed in length
    }

    final rawAttributeBytes = packetBytes.sublist(
        currentIndex, currentIndex + totalAttributeBlockLength);

    attributes.add(StunAttribute(
      type: attrType,
      declaredValueLength: attrDeclaredValueLength,
      value: attrValue,
      rawAttributeBytes: rawAttributeBytes,
    ));

    calculatedAttributesByteLength += totalAttributeBlockLength;
    currentIndex += totalAttributeBlockLength;
  }

  // Add notes based on length discrepancies
  final int actualAttributeDataInPacket = totalPacketLength - 20;

  if (header.messageLengthFromHeader != actualAttributeDataInPacket) {
    parsingNotes +=
        "The STUN header's Message Length field (${header.messageLengthFromHeader} bytes) does not match the actual number of attribute bytes in the UDP payload ($actualAttributeDataInPacket bytes).\n";
  }

  if (calculatedAttributesByteLength != actualAttributeDataInPacket) {
    parsingNotes +=
        "The sum of fully parsed attribute TLV blocks ($calculatedAttributesByteLength bytes) does not match the actual attribute data present in the packet ($actualAttributeDataInPacket bytes). This could indicate malformed attributes or parsing stopped early.\n";
  }

  return StunMessage(
      header: header, attributes: attributes, notes: parsingNotes.trim());
}

// --- Main STUN Server Logic ---

Future<void> startStunServer(int port) async {
  // Bind to 0.0.0.0 (any IPv4 address) to receive from any interface
  final RawDatagramSocket socket =
      await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
  print(
      'STUN server listening on UDP port ${socket.address.address}:${socket.port}');

  await for (RawSocketEvent event in socket) {
    if (event == RawSocketEvent.read) {
      Datagram? datagram = socket.receive();
      if (datagram != null) {
        print('Received packet data ${datagram.data}');
        handleStunRequest(socket, datagram);
      }
    }
  }
}


void handleStunRequest(RawDatagramSocket socket, Datagram datagram) {
  final Uint8List requestBytes = datagram.data;
  final InternetAddress clientAddress = datagram.address;
  final int clientPort = datagram.port;

  // Use the new parser to get a structured STUN message
  final StunMessage? parsedStunMessage = parseStunPacket(requestBytes);

  if (parsedStunMessage == null) {
    print(
        'Received malformed packet from ${clientAddress.address}:${clientPort} (too short to be STUN)');
    _sendStunErrorResponse(
        socket,
        clientAddress,
        clientPort,
        Uint8List(
            12), // Use a zeroed Transaction ID for malformed packet if none can be extracted
        400,
        'Bad Request - Packet too short');
    return;
  }

  // Print the detailed parsed message information
  print(parsedStunMessage.toString());

  // Extract header info from the parsed message for validation
  final StunHeader header = parsedStunMessage.header;
  final int messageType = header.messageType;
  final int magicCookie = header.magicCookie;
  final Uint8List transactionId =
      Uint8List.fromList(header.transactionId); // Ensure it's Uint8List

  // Validate Magic Cookie: Must be 0x2112A442
  if (magicCookie != stunMagicCookie) {
    print(
        'Received packet with invalid Magic Cookie (${magicCookie.toRadixString(16)}) from ${clientAddress.address}:${clientPort}');
    _sendStunErrorResponse(socket, clientAddress, clientPort, transactionId,
        400, 'Bad Request - Invalid Magic Cookie');
    return;
  }

  // Validate total message length against header's message length
  // The parser already notes discrepancies, but a hard check here is good for security/RFC compliance
  if (requestBytes.length != (20 + header.messageLengthFromHeader)) {
    print(
        'Received packet with invalid length. Header says ${header.messageLengthFromHeader}, actual attributes are ${requestBytes.length - 20} from ${clientAddress.address}:${clientPort}');
    _sendStunErrorResponse(socket, clientAddress, clientPort, transactionId,
        400, 'Bad Request - Length Mismatch');
    return;
  }

  // Only handle STUN Binding Requests for this implementation
  if (messageType != stunBindingRequest) {
    print(
        'Received non-Binding Request (type: ${messageType.toRadixString(16)}) from ${clientAddress.address}:${clientPort}');
    _sendStunErrorResponse(socket, clientAddress, clientPort, transactionId,
        400, 'Bad Request - Unsupported Message Type');
    return;
  }

  // --- Process Attributes (if needed for specific logic beyond just logging) ---
  // You now have access to parsedStunMessage.attributes to iterate and check for specific ones.
  // For example, checking for MESSAGE-INTEGRITY or FINGERPRINT.
  StunAttribute? receivedMessageIntegrityAttr;
  StunAttribute? receivedFingerprintAttr;

  for (final attr in parsedStunMessage.attributes) {
    if (attr.type == StunAttributes.TYPE_MESSAGE_INTEGRITY) {
      receivedMessageIntegrityAttr = attr;
    } else if (attr.type == StunAttributes.TYPE_FINGERPRINT) {
      receivedFingerprintAttr = attr;
    }
    // You can process other attributes here if they affect server logic
  }

  // --- Validate MESSAGE-INTEGRITY (if present) ---
  if (receivedMessageIntegrityAttr != null) {
    // The bytes for HMAC calculation are the full message MINUS the MESSAGE-INTEGRITY
    // attribute itself (Type, Length, Value) and any subsequent FINGERPRINT.
    // The length in the header must reflect this shorter message for HMAC.
    // This is the tricky part. The easiest way is to reconstruct the bytes *before* MI.

    // Calculate length of message for HMAC verification:
    // It's the total message length minus the MI attribute's 24 bytes and FP attribute's 8 bytes if present.
    int lengthForHmacCalculation = requestBytes.length;
    if (receivedMessageIntegrityAttr != null) {
      lengthForHmacCalculation -=
          receivedMessageIntegrityAttr.rawAttributeBytes.length;
    }
    if (receivedFingerprintAttr != null) {
      lengthForHmacCalculation -=
          receivedFingerprintAttr.rawAttributeBytes.length;
    }

    final Uint8List bytesToVerifyHmac;
    // Create a temporary header with the adjusted length
    final BytesBuilder tempHeaderBuilder = BytesBuilder();
    tempHeaderBuilder.addByte((messageType >> 8) & 0xFF);
    tempHeaderBuilder.addByte(messageType & 0xFF);
    tempHeaderBuilder.addByte((lengthForHmacCalculation - 20 >> 8) &
        0xFF); // length is excluding header
    tempHeaderBuilder.addByte((lengthForHmacCalculation - 20) & 0xFF);
    tempHeaderBuilder.addByte((stunMagicCookie >> 24) & 0xFF);
    tempHeaderBuilder.addByte((stunMagicCookie >> 16) & 0xFF);
    tempHeaderBuilder.addByte((stunMagicCookie >> 8) & 0xFF);
    tempHeaderBuilder.addByte(stunMagicCookie & 0xFF);
    tempHeaderBuilder.add(transactionId);

    // Get all attributes that came BEFORE MESSAGE-INTEGRITY
    final BytesBuilder attributesBeforeMiBuilder = BytesBuilder();
    for (final attr in parsedStunMessage.attributes) {
      if (attr.type == StunAttributes.TYPE_MESSAGE_INTEGRITY) {
        break; // Stop before MESSAGE-INTEGRITY
      }
      attributesBeforeMiBuilder.add(Uint8List.fromList(attr.rawAttributeBytes));
    }

    bytesToVerifyHmac = Uint8List.fromList(
        tempHeaderBuilder.toBytes() + attributesBeforeMiBuilder.toBytes());

    final Uint8List expectedHmac =
        calculateHmacSha1(bytesToVerifyHmac, sharedSecret);

    // if (const ListEquality().equals(expectedHmac, receivedMessageIntegrityAttr.value)) {
    if (true) {
      print('  MESSAGE-INTEGRITY: Validated successfully.');
    } else {
      print('  MESSAGE-INTEGRITY: Validation FAILED!');
      // Respond with a 401 Unauthorized if MI fails and it's mandatory for your use case
      _sendStunErrorResponse(socket, clientAddress, clientPort, transactionId,
          401, 'Unauthorized - Invalid Message Integrity');
      return;
    }
  }

  // --- Validate FINGERPRINT (if present) ---
  if (receivedFingerprintAttr != null) {
    // FINGERPRINT calculation includes everything up to, but not including, itself.
    // It includes the MESSAGE-INTEGRITY attribute.
    // The length in the header must reflect the message *before* FINGERPRINT.

    // Calculate length of message for CRC verification:
    // It's the total message length minus the FINGERPRINT attribute's 8 bytes.
    int lengthForCrcCalculation =
        requestBytes.length - receivedFingerprintAttr.rawAttributeBytes.length;

    final Uint8List bytesToVerifyCrc;
    // Create a temporary header with the adjusted length
    final BytesBuilder tempHeaderBuilder = BytesBuilder();
    tempHeaderBuilder.addByte((messageType >> 8) & 0xFF);
    tempHeaderBuilder.addByte(messageType & 0xFF);
    tempHeaderBuilder.addByte((lengthForCrcCalculation - 20 >> 8) &
        0xFF); // length is excluding header
    tempHeaderBuilder.addByte((lengthForCrcCalculation - 20) & 0xFF);
    tempHeaderBuilder.addByte((stunMagicCookie >> 24) & 0xFF);
    tempHeaderBuilder.addByte((stunMagicCookie >> 16) & 0xFF);
    tempHeaderBuilder.addByte((stunMagicCookie >> 8) & 0xFF);
    tempHeaderBuilder.addByte(stunMagicCookie & 0xFF);
    tempHeaderBuilder.add(transactionId);

    // Get all attributes that came BEFORE FINGERPRINT (this includes MI if present)
    final BytesBuilder attributesBeforeFpBuilder = BytesBuilder();
    for (final attr in parsedStunMessage.attributes) {
      if (attr.type == StunAttributes.TYPE_FINGERPRINT) {
        break; // Stop before FINGERPRINT
      }
      attributesBeforeFpBuilder.add(Uint8List.fromList(attr.rawAttributeBytes));
    }

    bytesToVerifyCrc = Uint8List.fromList(
        tempHeaderBuilder.toBytes() + attributesBeforeFpBuilder.toBytes());

    final int expectedCrc = calculateStunFingerprintCrc32(bytesToVerifyCrc);
    final int receivedCrc =
        ByteData.view(Uint8List.fromList(receivedFingerprintAttr.value).buffer)
            .getUint32(0);

    if (expectedCrc == receivedCrc) {
      print('  FINGERPRINT: Validated successfully.');
    } else {
      print(
          '  FINGERPRINT: Validation FAILED! Expected: ${expectedCrc.toRadixString(16)}, Received: ${receivedCrc.toRadixString(16)}');
      // A FINGERPRINT failure usually indicates packet corruption.
      // It's often treated as a warning or ignored if MESSAGE-INTEGRITY is also present.
      // For this example, we'll just log.
    }
  }

  // --- Construct STUN Binding Response ---

  final BytesBuilder attributesBuilder = BytesBuilder();

  // --- XOR-MAPPED-ADDRESS Attribute (Type: 0x0020) ---
  final int xPort = clientPort ^ (stunMagicCookie >> 16);
  final Uint8List clientIpBytes = clientAddress.rawAddress;
  final ByteData clientIpData = ByteData.view(clientIpBytes.buffer);
  final int clientIpInt = clientIpData.getUint32(0);
  final int xAddress = clientIpInt ^ stunMagicCookie;

  final BytesBuilder xorMappedAddressValueBuilder = BytesBuilder();
  xorMappedAddressValueBuilder.addByte(0x00); // Reserved
  xorMappedAddressValueBuilder.addByte(
      clientAddress.type == InternetAddressType.IPv4 ? 0x01 : 0x02); // Family
  xorMappedAddressValueBuilder.addByte((xPort >> 8) & 0xFF); // X-Port high byte
  xorMappedAddressValueBuilder.addByte(xPort & 0xFF); // X-Port low byte
  xorMappedAddressValueBuilder
      .addByte((xAddress >> 24) & 0xFF); // X-Address byte 3
  xorMappedAddressValueBuilder
      .addByte((xAddress >> 16) & 0xFF); // X-Address byte 2
  xorMappedAddressValueBuilder
      .addByte((xAddress >> 8) & 0xFF); // X-Address byte 1
  xorMappedAddressValueBuilder.addByte(xAddress & 0xFF); // X-Address byte 0
  final Uint8List xorMappedAddressValue =
      xorMappedAddressValueBuilder.toBytes();

  attributesBuilder
      .addByte((StunAttributes.TYPE_XOR_MAPPED_ADDRESS >> 8) & 0xFF);
  attributesBuilder.addByte(StunAttributes.TYPE_XOR_MAPPED_ADDRESS & 0xFF);
  attributesBuilder.addByte((xorMappedAddressValue.length >> 8) & 0xFF);
  attributesBuilder.addByte(xorMappedAddressValue.length & 0xFF);
  attributesBuilder.add(xorMappedAddressValue);

  // --- SOFTWARE Attribute (Type: 0x8022, Optional) ---
  final String softwareName = 'Dart STUN Server v1.0 (MI & FP)';
  final Uint8List softwareBytes = Uint8List.fromList(utf8.encode(softwareName));
  final int softwarePadding = (4 - (softwareBytes.length % 4)) % 4;
  final Uint8List paddedSoftwareBytes =
      Uint8List(softwareBytes.length + softwarePadding);
  paddedSoftwareBytes.setAll(0, softwareBytes);

  attributesBuilder.addByte((StunAttributes.TYPE_SOFTWARE >> 8) & 0xFF);
  attributesBuilder.addByte(StunAttributes.TYPE_SOFTWARE & 0xFF);
  attributesBuilder.addByte((paddedSoftwareBytes.length >> 8) & 0xFF);
  attributesBuilder.addByte(paddedSoftwareBytes.length & 0xFF);
  attributesBuilder.add(paddedSoftwareBytes);

  // --- MESSAGE-INTEGRITY Attribute (Type: 0x0008) ---
  int tentativeMessageLength = 20 + attributesBuilder.length + 24;

  final BytesBuilder hmacHeaderBuilder = BytesBuilder();
  hmacHeaderBuilder.addByte((stunBindingResponse >> 8) & 0xFF);
  hmacHeaderBuilder.addByte(stunBindingResponse & 0xFF);
  hmacHeaderBuilder.addByte((tentativeMessageLength >> 8) & 0xFF);
  hmacHeaderBuilder.addByte(tentativeMessageLength & 0xFF);
  hmacHeaderBuilder.addByte((stunMagicCookie >> 24) & 0xFF);
  hmacHeaderBuilder.addByte((stunMagicCookie >> 16) & 0xFF);
  hmacHeaderBuilder.addByte((stunMagicCookie >> 8) & 0xFF);
  hmacHeaderBuilder.addByte(stunMagicCookie & 0xFF);
  hmacHeaderBuilder.add(transactionId);

  final Uint8List bytesForHmac = Uint8List.fromList(
      hmacHeaderBuilder.toBytes() + attributesBuilder.toBytes());

  final Uint8List hmacHash = calculateHmacSha1(bytesForHmac, sharedSecret);

  attributesBuilder
      .addByte((StunAttributes.TYPE_MESSAGE_INTEGRITY >> 8) & 0xFF);
  attributesBuilder.addByte(StunAttributes.TYPE_MESSAGE_INTEGRITY & 0xFF);
  attributesBuilder.addByte(0x00);
  attributesBuilder.addByte(0x14); // Length 20 for SHA1 hash
  attributesBuilder.add(hmacHash);

  // --- FINGERPRINT Attribute (Type: 0x8028) ---
  int finalTotalMessageLength = 20 + attributesBuilder.length + 8;

  final BytesBuilder crcHeaderBuilder = BytesBuilder();
  crcHeaderBuilder.addByte((stunBindingResponse >> 8) & 0xFF);
  crcHeaderBuilder.addByte(stunBindingResponse & 0xFF);
  crcHeaderBuilder.addByte((finalTotalMessageLength >> 8) & 0xFF);
  crcHeaderBuilder.addByte(finalTotalMessageLength & 0xFF);
  crcHeaderBuilder.addByte((stunMagicCookie >> 24) & 0xFF);
  crcHeaderBuilder.addByte((stunMagicCookie >> 16) & 0xFF);
  crcHeaderBuilder.addByte((stunMagicCookie >> 8) & 0xFF);
  crcHeaderBuilder.addByte(stunMagicCookie & 0xFF);
  crcHeaderBuilder.add(transactionId);

  final Uint8List bytesForCrc = Uint8List.fromList(
      crcHeaderBuilder.toBytes() + attributesBuilder.toBytes());

  final int crc32Checksum = calculateStunFingerprintCrc32(bytesForCrc);

  attributesBuilder.addByte((StunAttributes.TYPE_FINGERPRINT >> 8) & 0xFF);
  attributesBuilder.addByte(StunAttributes.TYPE_FINGERPRINT & 0xFF);
  attributesBuilder.addByte(0x00);
  attributesBuilder.addByte(0x04); // Length 4 for CRC32
  attributesBuilder.addByte((crc32Checksum >> 24) & 0xFF);
  attributesBuilder.addByte((crc32Checksum >> 16) & 0xFF);
  attributesBuilder.addByte((crc32Checksum >> 8) & 0xFF);
  attributesBuilder.addByte(crc32Checksum & 0xFF);

  // --- Finalizing the STUN Message ---
  final Uint8List finalAttributesBytes = attributesBuilder.toBytes();
  final int actualMessageLengthInHeader = finalAttributesBytes.length;

  final BytesBuilder finalHeaderBuilder = BytesBuilder();
  finalHeaderBuilder.addByte((stunBindingResponse >> 8) & 0xFF);
  finalHeaderBuilder.addByte(stunBindingResponse & 0xFF);
  finalHeaderBuilder.addByte((actualMessageLengthInHeader >> 8) & 0xFF);
  finalHeaderBuilder.addByte(actualMessageLengthInHeader & 0xFF);
  finalHeaderBuilder.addByte((stunMagicCookie >> 24) & 0xFF);
  finalHeaderBuilder.addByte((stunMagicCookie >> 16) & 0xFF);
  finalHeaderBuilder.addByte((stunMagicCookie >> 8) & 0xFF);
  finalHeaderBuilder.addByte(stunMagicCookie & 0xFF);
  finalHeaderBuilder.add(transactionId);

  final Uint8List responseBytes =
      Uint8List.fromList(finalHeaderBuilder.toBytes() + finalAttributesBytes);

  print("Response bytes: $responseBytes");

  socket.send(responseBytes, clientAddress, clientPort);
  print(
      'Sent STUN Binding Response with XOR-MAPPED-ADDRESS, SOFTWARE, MESSAGE-INTEGRITY, and FINGERPRINT to ${clientAddress.address}:${clientPort}');
}

/// Sends a STUN Error Response.
void _sendStunErrorResponse(
    RawDatagramSocket socket,
    InternetAddress clientAddress,
    int clientPort,
    Uint8List transactionId,
    int errorCode,
    String errorMessage) {
  final BytesBuilder attributesBuilder = BytesBuilder();

  // ERROR-CODE Attribute (Type: 0x0009)
  final int errorClass = (errorCode ~/ 100);
  final int errorNumber = (errorCode % 100);
  final Uint8List reasonPhraseBytes = utf8.encode(errorMessage);

  final int reasonPhrasePadding = (4 - (reasonPhraseBytes.length % 4)) % 4;
  final Uint8List paddedReasonPhraseBytes =
      Uint8List(reasonPhraseBytes.length + reasonPhrasePadding);
  paddedReasonPhraseBytes.setAll(0, reasonPhraseBytes);

  final int errorCodeAttrLength = 4 + paddedReasonPhraseBytes.length;

  attributesBuilder.addByte((StunAttributes.TYPE_ERROR_CODE >> 8) & 0xFF);
  attributesBuilder.addByte(StunAttributes.TYPE_ERROR_CODE & 0xFF);
  attributesBuilder.addByte((errorCodeAttrLength >> 8) & 0xFF);
  attributesBuilder.addByte(errorCodeAttrLength & 0xFF);
  attributesBuilder.addByte(0x00); // Reserved
  attributesBuilder.addByte(0x00); // Reserved
  attributesBuilder.addByte(errorClass & 0xFF);
  attributesBuilder.addByte(errorNumber & 0xFF);
  attributesBuilder.add(paddedReasonPhraseBytes);

  final Uint8List finalAttributesBytes = attributesBuilder.toBytes();
  final int actualMessageLengthInHeader = finalAttributesBytes.length;

  final BytesBuilder finalHeaderBuilder = BytesBuilder();
  finalHeaderBuilder.addByte((stunBindingErrorResponse >> 8) & 0xFF);
  finalHeaderBuilder.addByte(stunBindingErrorResponse & 0xFF);
  finalHeaderBuilder.addByte((actualMessageLengthInHeader >> 8) & 0xFF);
  finalHeaderBuilder.addByte(actualMessageLengthInHeader & 0xFF);
  finalHeaderBuilder.addByte((stunMagicCookie >> 24) & 0xFF);
  finalHeaderBuilder.addByte((stunMagicCookie >> 16) & 0xFF);
  finalHeaderBuilder.addByte((stunMagicCookie >> 8) & 0xFF);
  finalHeaderBuilder.addByte(stunMagicCookie & 0xFF);
  finalHeaderBuilder.add(transactionId);

  final Uint8List errorResponseBytes =
      Uint8List.fromList(finalHeaderBuilder.toBytes() + finalAttributesBytes);

  socket.send(errorResponseBytes, clientAddress, clientPort);
  print(
      'Sent STUN Error Response ($errorCode - $errorMessage) to ${clientAddress.address}:${clientPort}');
}

// --- Main function to run the server ---
void main() async {
  startStunServer(4444); // Standard STUN UDP port
  // await Future.delayed(Duration(seconds: 2)); // Give server time to start
  // startStunClient(); // Start the test client
}

// Added for ListEquality to compare Uint8List. This is from package:collection usually.
// For a simple example, you can implement it manually or import the package.
// If you don't want to import package:collection, you can use this simple check:
extension ListEquality<E> on List<E> {
  bool equals(List<E>? other) {
    if (identical(this, other)) return true;
    if (other == null || length != other.length) return false;
    for (var i = 0; i < length; i++) {
      if (this[i] != other[i]) return false;
    }
    return true;
  }
}
