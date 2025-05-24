import 'dart:typed_data';
import 'dart:convert';

// Helper function to convert a List<int> to a hex string
String bytesToHexString(List<int> bytes, {String separator = ""}) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(separator);
}

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
      // Add more STUN message types if needed
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
    switch (type) {
      case 0x0001:
        return "MAPPED-ADDRESS";
      case 0x0002:
        return "RESPONSE-ADDRESS";
      case 0x0003:
        return "CHANGE-REQUEST";
      case 0x0004:
        return "SOURCE-ADDRESS";
      case 0x0005:
        return "CHANGED-ADDRESS";
      case 0x0006:
        return "USERNAME";
      case 0x0007:
        return "PASSWORD (deprecated)";
      case 0x0008:
        return "MESSAGE-INTEGRITY";
      case 0x0009:
        return "ERROR-CODE";
      case 0x000A:
        return "UNKNOWN-ATTRIBUTES";
      case 0x000B:
        return "REFLECTED-FROM";
      case 0x0014:
        return "REALM";
      case 0x0015:
        return "NONCE";
      case 0x0020:
        return "XOR-MAPPED-ADDRESS";
      case 0x0024:
        return "SOFTWARE"; // Note: In your packet, 0x0024 was MESSAGE-INTEGRITY
      case 0x0025:
        return "ALTERNATE-SERVER";
      case 0x8022:
        return "SOFTWARE (another common assignment, check context)";
      case 0x8023:
        return "ALTERNATE-SERVER (RFC5389)";
      case 0x8028:
        return "FINGERPRINT"; // Standard FINGERPRINT is 0x8028
      case 0x8029:
        return "PRIORITY";
      case 0x802B:
        return "ICE-CONTROLLED";
      case 0x802C:
        return "ICE-CONTROLLING"; // Standard ICE-CONTROLLING is 0x802C
      case 0xC057:
        return "ICE-CONTROLLING / ICE-CONTROLLED (from your packet type, possibly non-standard assignment or context)";
      // WebRTC specific (some overlap or are preferred over older ones)
      case 0x002A:
        return "PADDING";
      case 0x802A:
        return "RESPONSE-PORT";
      case 0x001A:
        return "LIFETIME";

      default:
        // For your specific packet:
        if (type == 0x0024) {
          return "MESSAGE-INTEGRITY (from your packet, usually 0x0008 or 0x8020)";
        }
        if (type == 0x0008) {
          return "FINGERPRINT (from your packet, usually 0x8028)";
        }
        if (type == 0xC057) {
          return "ICE-CONTROLLING (from your packet, standard is 0x802C)";
        }
        return "Unknown Attribute (0x${type.toRadixString(16).padLeft(4, '0')})";
    }
  }

  String get standardLengthNote {
    String note = "";
    bool isStandard = true;
    switch (type) {
      case 0xC057: // Your packet's ICE-CONTROLLING
        if (declaredValueLength != 8) {
          note = "(Standard value length for ICE-CONTROLLING (0x802C) is 8)";
          isStandard = false;
        }
        break;
      case 0x8029: // PRIORITY
        if (declaredValueLength != 4) {
          note = "(Standard value length for PRIORITY is 4)";
          isStandard = false;
        }
        break;
      case 0x0024: // Your packet's MESSAGE-INTEGRITY
        if (declaredValueLength != 20) {
          note = "(Standard value length for MESSAGE-INTEGRITY (0x0008) is 20)";
          isStandard = false;
        }
        break;
      case 0x0008: // Your packet's FINGERPRINT
        if (declaredValueLength != 4) {
          note = "(Standard value length for FINGERPRINT (0x8028) is 4)";
          isStandard = false;
        }
        break;
    }
    if (isStandard) return "";
    return " $note";
  }

  String get valueAsString {
    if (type == 0x0006) {
      // USERNAME
      try {
        return '"${utf8.decode(value)}"';
      } catch (e) {
        return 'Error decoding UTF-8: $e. Raw: ${bytesToHexString(value)}';
      }
    }
    return bytesToHexString(value);
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
    print("Error: Packet too short to be a STUN message (less than 20 bytes).");
    return null;
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

  if (magicCookie != 0x2112A442) {
    print("Warning: Invalid STUN Magic Cookie.");
    // Proceeding with parsing anyway for informational purposes.
  }

  // Parse Attributes
  final List<StunAttribute> attributes = [];
  int currentIndex = 20; // Attributes start after 20-byte header
  final int totalPacketLength = packetBytes.length;
  int calculatedAttributesByteLength = 0;

  while (currentIndex < totalPacketLength) {
    if (currentIndex + 4 > totalPacketLength) {
      // Not enough bytes for Type and Length fields
      print(
          "Warning: Truncated attribute header at index $currentIndex. Stopping attribute parsing.");
      break;
    }

    final attrType = byteData.getUint16(currentIndex);
    final attrDeclaredValueLength = byteData.getUint16(currentIndex + 2);
    final attrValueStartIndex = currentIndex + 4;

    if (attrValueStartIndex + attrDeclaredValueLength > totalPacketLength) {
      print(
          "Warning: Attribute (Type 0x${attrType.toRadixString(16)}) declared value length ($attrDeclaredValueLength) exceeds packet boundary. Stopping attribute parsing.");
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
      print(
          "Warning: Attribute (Type 0x${attrType.toRadixString(16)}) with padding exceeds packet boundary. This attribute might be malformed or the packet truncated. Using available bytes.");
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
      break; // Stop further parsing
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

  String notes = "";
  if (header.messageLengthFromHeader != calculatedAttributesByteLength &&
      header.messageLengthFromHeader == (totalPacketLength - 20)) {
    // This covers the case where the header length matches the actual data length, but our sum of TLV blocks doesn't (e.g. last block malformed)
    notes +=
        "Header Message Length (${header.messageLengthFromHeader} bytes for attributes) matches actual attribute data length (${totalPacketLength - 20} bytes).\n";
    if (calculatedAttributesByteLength != (totalPacketLength - 20)) {
      notes +=
          "However, the sum of parsed attribute TLV blocks ($calculatedAttributesByteLength bytes) does not match this, possibly due to an issue parsing the last attribute.\n";
    }
  } else if (header.messageLengthFromHeader != calculatedAttributesByteLength) {
    notes +=
        "Header Message Length (${header.messageLengthFromHeader} bytes for attributes) does NOT match the sum of parsed attribute TLV blocks ($calculatedAttributesByteLength bytes).\n";
  }

  final int actualAttributeDataInPacket = totalPacketLength - 20;
  if (actualAttributeDataInPacket != calculatedAttributesByteLength) {
    notes +=
        "The actual attribute data present in the packet ($actualAttributeDataInPacket bytes) does not match the sum of fully parsed attribute TLV blocks ($calculatedAttributesByteLength bytes). This could indicate malformed attributes or parsing stopped early.\n";
  } else if (notes.isEmpty &&
      header.messageLengthFromHeader != actualAttributeDataInPacket) {
    // This is the specific case for the user's packet
    notes +=
        "The STUN header's Message Length field (${header.messageLengthFromHeader}) indicates ${header.messageLengthFromHeader} bytes of attributes. However, the actual UDP payload contains $actualAttributeDataInPacket bytes of attributes, which have been fully parsed.\n";
  }

  return StunMessage(
      header: header, attributes: attributes, notes: notes.trim());
}

void main() {
  final Uint8List udpData = Uint8List.fromList([
    0,
    1,
    0,
    76,
    33,
    18,
    164,
    66,
    114,
    97,
    105,
    84,
    43,
    89,
    100,
    57,
    80,
    72,
    116,
    54,
    0,
    6,
    0,
    9,
    121,
    120,
    89,
    98,
    58,
    75,
    84,
    83,
    102,
    0,
    0,
    0,
    192,
    87,
    0,
    4,
    0,
    1,
    0,
    10,
    128,
    41,
    0,
    8,
    108,
    234,
    92,
    211,
    220,
    152,
    0,
    28,
    0,
    36,
    0,
    4,
    110,
    127,
    30,
    255,
    0,
    8,
    0,
    20,
    121,
    93,
    242,
    189,
    181,
    34,
    248,
    105,
    246,
    115,
    172,
    24,
    252,
    168,
    214,
    36,
    60,
    15,
    85,
    30
  ]);
  // StunProtocol stunProtocol = StunProtocol.RFC5780;
  final StunMessage? parsedMessage = parseStunPacket(udpData);

  // final Message parsedMessage = Message.decode(udpData);

  // final StunMessage? parsedMessage = parseStunPacket(udpData);

  if (parsedMessage != null) {
    print(parsedMessage);
  }
}
