import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'dart:io'; // For UDP sockets and network addresses
import 'package:crypto/crypto.dart'; // You'll need to add the 'crypto' package to your pubspec.yaml
import 'package:convert/convert.dart'; // You'll need to add the 'convert' package to your pubspec.yaml
import 'package:collection/collection.dart'; // You'll need to add the 'collection' package for listEquals

// Constants
const int magicCookie = 0x2112A442;
const int messageHeaderSize = 20;
const int transactionIDSize = 12; // 96 bit
const int stunHeaderSize = 20;
const int hmacSignatureSize = 20;
const int fingerprintSize = 4;
const int fingerprintXorMask = 0x5354554e;
const int attributeHeaderSize = 4;

// Attribute Types
enum AttributeType {
  mappedAddress(0x0001),
  responseAddress(0x0002),
  changeRequest(0x0003),
  sourceAddress(0x0004),
  changedAddress(0x0005),
  userName(0x0006),
  password(0x0007),
  messageIntegrity(0x0008),
  errorCode(0x0009),
  unknownAttributes(0x000a),
  reflectedFrom(0x000b),
  realm(0x0014),
  nonce(0x0015),
  xorMappedAddress(0x0020),
  software(0x8022),
  alternateServer(0x8023),
  fingerprint(0x8028),

  // TURN attributes:
  channelNumber(0x000C),
  lifetime(0x000D),
  xorPeerAddress(0x0012),
  data(0x0013),
  xorRelayedAddress(0x0016),
  evenPort(0x0018),
  requestedPort(0x0019),
  dontFragment(0x001A),
  reservationRequest(0x0022),

  // ICE attributes:
  priority(0x0024),
  useCandidate(0x0025),
  iceControlled(0x8029),
  iceControlling(0x802A);

  final int value;
  const AttributeType(this.value);

  static AttributeType? fromInt(int value) => AttributeType.values
      .cast<AttributeType?>()
      .firstWhere((e) => e?.value == value, orElse: () => null);

  @override
  String toString() {
    return name;
  }
}

// Message Class
enum MessageClass {
  request(0x00),
  indication(0x01),
  successResponse(0x02),
  errorResponse(0x03);

  final int value;
  const MessageClass(this.value);

  factory MessageClass.fromInt(int value) =>
      MessageClass.values.firstWhere((e) => e.value == value,
          orElse: () => throw Exception('Unknown message class: $value'));
}

// Message Method
enum MessageMethod {
  stunBinding(0x0001),
  turnAllocate(0x0003),
  turnRefresh(0x0004),
  turnSend(0x0006),
  turnData(0x0007),
  turnCreatePermission(0x0008),
  turnChannelBind(0x0009),
  turnConnect(0x000a),
  turnConnectionBind(0x000b),
  turnConnectionAttempt(0x000c);

  final int value;
  const MessageMethod(this.value);

  factory MessageMethod.fromInt(int value) =>
      MessageMethod.values.firstWhere((e) => e.value == value,
          orElse: () => throw Exception('Unknown message method: $value'));
}

// Message Type
class MessageType {
  final MessageMethod messageMethod;
  final MessageClass messageClass;

  MessageType({required this.messageMethod, required this.messageClass});

  factory MessageType.decode(int mtValue) {
    print(
        'MessageType.decode: Decoding message type value: 0x${mtValue.toRadixString(16)}');
    // Decoding class.
    const int c0Bit = 0x1;
    const int c1Bit = 0x2;
    const int classC0Shift = 4;
    const int classC1Shift = 7;

    final int c0 = (mtValue >> classC0Shift) & c0Bit;
    final int c1 = (mtValue >> classC1Shift) & c1Bit;
    final int classValue = c0 + c1;
    print('MessageType.decode: Decoded class value: $classValue');

    // Decoding method.
    const int methodABits = 0xf; // 0b0000000000001111
    const int methodBBits = 0x70; // 0b0000000001110000
    const int methodDBits = 0xf80; // 0b0000111110000000
    const int methodBShift = 1;
    const int methodDShift = 2;

    final int a = mtValue & methodABits; // A(M0-M3)
    final int b = (mtValue >> methodBShift) & methodBBits; // B(M4-M6)
    final int d = (mtValue >> methodDShift) & methodDBits; // D(M7-M11)
    final int m = a + b + d;
    print('MessageType.decode: Decoded method value: 0x${m.toRadixString(16)}');

    final messageClass = MessageClass.fromInt(classValue);
    final messageMethod = MessageMethod.fromInt(m);
    print(
        'MessageType.decode: Decoded message type: $messageMethod $messageClass');

    return MessageType(
      messageClass: messageClass,
      messageMethod: messageMethod,
    );
  }

  int encode() {
    print('MessageType.encode: Encoding message type: $this');
    final int m = messageMethod.value;
    const int methodABits = 0xf; // 0b0000000000001111
    const int methodBBits = 0x70; // 0b0000000001110000
    const int methodDBits = 0xf80; // 0b0000111110000000
    const int methodBShift = 1;
    const int methodDShift = 2;

    final int a = m & methodABits;
    final int b = (m >> methodBShift) & methodBBits;
    final int d = (m >> methodDShift) & methodDBits;

    // Shifting to add "holes" for C0 (at 4 bit) and C1 (8 bit).
    final int methodValue = a + (b << methodBShift) + (d << methodDShift);
    print(
        'MessageType.encode: Encoded method value: 0x${methodValue.toRadixString(16)}');

    // C0 is zero bit of C, C1 is first bit.
    const int c0Bit = 0x1;
    const int c1Bit = 0x2;
    const int classC0Shift = 4;
    const int classC1Shift = 7;

    final int c = messageClass.value;
    final int c0 = (c & c0Bit) << classC0Shift;
    final int c1 = (c & c1Bit) << classC1Shift;
    final int classValue = c0 + c1;
    print(
        'MessageType.encode: Encoded class value: 0x${classValue.toRadixString(16)}');

    final encodedValue = methodValue + classValue;
    print(
        'MessageType.encode: Final encoded message type value: 0x${encodedValue.toRadixString(16)}');
    return encodedValue;
  }

  @override
  String toString() {
    return '$messageMethod $messageClass';
  }
}

// Attribute
class Attribute {
  AttributeType? attributeType;
  int? rawAttributeType; // To store unknown attribute types
  Uint8List value;
  int offsetInMessage; // Offset of the attribute's header within the raw message buffer

  Attribute({
    this.attributeType,
    this.rawAttributeType,
    required this.value,
    required this.offsetInMessage,
  }) : assert(attributeType != null || rawAttributeType != null,
            'Attribute must have either attributeType or rawAttributeType');

  int getRawDataLength() {
    return value.length;
  }

  int getRawFullLength() {
    return attributeHeaderSize + value.length;
  }

  static Attribute decode(Uint8List buf, int offset) {
    print('Attribute.decode: Attempting to decode attribute at offset $offset');
    if (buf.length - offset < attributeHeaderSize) {
      print(
          'Attribute.decode: Error: Buffer length (${buf.length}) - offset ($offset) < attributeHeaderSize ($attributeHeaderSize)');
      throw Exception(
          'Data contains incomplete STUN or TURN frame (attribute header)');
    }

    final int offsetBackup = offset;
    final byteData = ByteData.view(buf.buffer);

    final int attrTypeVal = byteData.getUint16(offset, Endian.big);
    print(
        'Attribute.decode: Decoded attribute type value: 0x${attrTypeVal.toRadixString(16)}');

    offset += 2;
    final int attrLength = byteData.getUint16(offset, Endian.big);
    print('Attribute.decode: Decoded attribute length: $attrLength');

    offset += 2;

    // Ensure there are enough bytes in the buffer for the attribute value
    if (buf.length - offset < attrLength) {
      print(
          'Attribute.decode: Error: Buffer length (${buf.length}) - offset ($offset) < attributeLength ($attrLength)');
      throw Exception(
          'Data contains incomplete STUN or TURN frame (attribute value truncated)');
    }

    final attributeType = AttributeType.fromInt(attrTypeVal);
    print(
        'Attribute.decode: Resolved attribute type: ${attributeType ?? "Unknown (0x${attrTypeVal.toRadixString(16)})"}');

    if (attributeType != null) {
      final attribute = Attribute(
        attributeType: attributeType,
        value: buf.sublist(offset, offset + attrLength),
        offsetInMessage: offsetBackup,
      );
      print(
          'Attribute.decode: Successfully decoded known attribute: $attribute');
      return attribute;
    } else {
      // Handle unknown attribute type
      final attribute = Attribute(
        rawAttributeType: attrTypeVal,
        value: buf.sublist(offset, offset + attrLength),
        offsetInMessage: offsetBackup,
      );
      print(
          'Attribute.decode: Successfully decoded unknown attribute: $attribute');
      return attribute;
    }
  }

  Uint8List encode() {
    final typeValue =
        attributeType != null ? attributeType!.value : rawAttributeType!;
    print(
        'Attribute.encode: Encoding attribute type 0x${typeValue.toRadixString(16)} with data length ${value.length}');
    int attrLen = 4 + value.length;
    // Add padding to make the attribute length a multiple of 4
    final padding = (4 - (value.length % 4)) % 4;
    attrLen += padding;
    print(
        'Attribute.encode: Attribute padded length: $attrLen (padding: $padding)');

    final result = Uint8List(attrLen);
    final byteData = ByteData.view(result.buffer);

    byteData.setUint16(0, typeValue, Endian.big);
    byteData.setUint16(2, value.length,
        Endian.big); // Store actual data length, not padded length
    result.setRange(4, 4 + value.length, value);
    // Padding bytes are implicitly zeroed out by Uint8List initialization

    print('Attribute.encode: Encoded attribute bytes: ${hex.encode(result)}');
    return result;
  }

  @override
  String toString() {
    final type = attributeType != null
        ? attributeType.toString()
        : '0x${rawAttributeType!.toRadixString(16).padLeft(4, '0')}';
    // Attempt to decode value as UTF-8, fallback to hex if malformed
    String valueStr;
    try {
      // Only decode if it's a reasonable length for a string attribute
      if (value.length > 0 && value.length < 256) {
        // Arbitrary limit to avoid large binary data issues
        valueStr = utf8.decode(value);
      } else {
        valueStr = hex.encode(value);
      }
    } catch (_) {
      valueStr = hex.encode(value); // Use hex from convert package
    }
    return '$type: [$valueStr]';
  }
}

// IPFamily
enum IPFamily {
  ipv4(0x01),
  ipv6(0x02);

  final int value;
  const IPFamily(this.value);

  factory IPFamily.fromInt(int value) =>
      IPFamily.values.firstWhere((e) => e.value == value,
          orElse: () => throw Exception('Unknown IP family: $value'));
}

// MappedAddress
class MappedAddress {
  IPFamily ipFamily;
  InternetAddress ip; // Using InternetAddress for IP address in Dart
  int port;

  MappedAddress({required this.ipFamily, required this.ip, required this.port});

  @override
  String toString() {
    return '$ipFamily:$ip:$port';
  }
}

// Message
class Message {
  MessageType messageType;
  Uint8List transactionID;
  Map<int, Attribute>
      attributes; // Changed key to int to handle raw attribute types
  Uint8List rawMessage; // Stores the raw bytes of the received message

  Message({
    required this.messageType,
    required this.transactionID,
    required this.attributes,
    required this.rawMessage,
  });

  factory Message.decode(Uint8List buf) {
    print('Message.decode: Decoding buffer of length ${buf.length}');
    if (buf.length < stunHeaderSize) {
      print('Message.decode: Error: Buffer too short for STUN header');
      throw Exception(
          'Data contains incomplete STUN or TURN frame (buffer too short for header)');
    }

    final byteData = ByteData.view(buf.buffer);

    final int messageTypeVal = byteData.getUint16(0, Endian.big);
    final int messageLength = byteData.getUint16(2, Endian.big);
    final int magicCookieVal = byteData.getUint32(4, Endian.big);

    print(
        'Message.decode: Message Type Value: 0x${messageTypeVal.toRadixString(16)}');
    print('Message.decode: Message Length: $messageLength');
    print(
        'Message.decode: Magic Cookie: 0x${magicCookieVal.toRadixString(16)}');
    print(
        'Message.decode: Expected Magic Cookie: 0x${magicCookie.toRadixString(16)}');

    if (magicCookieVal != magicCookie) {
      print('Message.decode: Error: Magic Cookie mismatch');
      throw Exception(
          'Data is not a valid TURN frame, no STUN or ChannelData found (Magic Cookie mismatch)');
    }

    final transactionID = buf.sublist(8, 8 + transactionIDSize);
    print('Message.decode: Transaction ID: ${hex.encode(transactionID)}');

    final attributes = <int, Attribute>{}; // Changed key to int

    int offset = stunHeaderSize;
    final int attributesEnd = stunHeaderSize + messageLength;
    print(
        'Message.decode: Expected end of attributes in buffer: $attributesEnd (buffer length: ${buf.length})');

    // Ensure the buffer is at least as long as the header plus the declared message length.
    // If not, we cannot possibly decode the full message as indicated by the length field.
    if (buf.length < attributesEnd) {
      print(
          'Message.decode: Error: Buffer length ${buf.length} < expected attributes end ${attributesEnd}');
      throw Exception(
          'Data contains incomplete STUN or TURN frame (buffer shorter than declared message length)');
    }

    int attributeCount = 0;
    // Loop through the attribute data as long as there's enough data in the buffer
    // to potentially decode another attribute header and the current offset is within
    // the bounds indicated by the message length.
    while (
        buf.length - offset >= attributeHeaderSize && offset < attributesEnd) {
      attributeCount++;
      print(
          'Message.decode: Decoding attribute #$attributeCount at offset $offset');
      final decodedAttr = Attribute.decode(buf, offset);

      // Ensure the attribute's data does not extend beyond the message's declared length
      final attributeDataEndInMessage =
          (offset - stunHeaderSize) + decodedAttr.getRawDataLength();
      if (attributeDataEndInMessage > messageLength) {
        print(
            'Message.decode: Error: Attribute data extends beyond message length. Attribute data ends in message at $attributeDataEndInMessage, message length is $messageLength');
        throw Exception(
            'Data contains malformed STUN message (attribute data extends beyond message length)');
      }

      final attributeKey = decodedAttr.attributeType != null
          ? decodedAttr.attributeType!.value
          : decodedAttr.rawAttributeType!;
      attributes[attributeKey] = decodedAttr;
      print(
          'Message.decode: Added attribute with key 0x${attributeKey.toRadixString(16)}');

      // Calculate the padded length of the current attribute to advance the offset correctly
      final paddedAttributeLength = attributeHeaderSize +
          decodedAttr.getRawDataLength() +
          (4 - (decodedAttr.getRawDataLength() % 4)) % 4;
      print(
          'Message.decode: Decoded attribute padded length: $paddedAttributeLength');

      offset += paddedAttributeLength;
      print('Message.decode: Advanced offset to $offset');

      // Ensure offset after processing the attribute does not go beyond the expected end of attributes
      if (offset > attributesEnd) {
        // This can happen if the last attribute's padded length
        // calculated based on its declared length exceeds messageLength.
        print(
            'Message.decode: Error: Offset ($offset) exceeded expected attributes end ($attributesEnd) after attribute processing.');
        throw Exception(
            'Data contains malformed STUN message (offset exceeded message length after attribute processing)');
      }
    }
    print(
        'Message.decode: Finished decoding attributes. Final offset: $offset, Expected attributes end: $attributesEnd');

    // After the loop, check if we processed exactly the amount of data indicated by messageLength.
    // If the loop terminated because buf.length - offset < attributeHeaderSize, it means
    // the buffer ran out of data prematurely, and offset will be less than attributesEnd.
    if (offset - stunHeaderSize != messageLength) {
      print(
          'Message.decode: Decoded length mismatch. Decoded length: ${offset - stunHeaderSize}, Message length: $messageLength');
      // If offset is less than attributesEnd, it means the buffer was truncated.
      if (offset < attributesEnd) {
        print('Message.decode: Error: Buffer ran out of data prematurely.');
        throw Exception(
            'Data contains incomplete STUN or TURN frame (buffer ran out of data during attribute decoding)');
      }
      // If offset is greater than attributesEnd, it implies trailing data after the last attribute,
      // which should ideally be caught by the checks inside the loop, but this is a safeguard.
      // Depending on desired strictness, you might just warn about trailing data.
      // For now, we'll consider it a format error if we didn't end exactly at attributesEnd.
      if (offset > attributesEnd) {
        print('Message.decode: Error: Trailing data after attributes.');
        throw Exception(
            'Data contains malformed STUN message (trailing data after attributes)');
      }
    }
    print('Message.decode: Successfully decoded message.');

    return Message(
      messageType: MessageType.decode(messageTypeVal),
      transactionID: transactionID,
      attributes: attributes,
      rawMessage: buf, // Store the original raw buffer
    );
  }

  Uint8List encode(String pwd) {
    print('Message.encode: Starting encoding message...');
    // Pre-encode: Remove MESSAGE-INTEGRITY and FINGERPRINT, add SOFTWARE
    print(
        'Message.encode: Removing MESSAGE-INTEGRITY and FINGERPRINT attributes...');
    attributes.remove(AttributeType.messageIntegrity.value);
    attributes.remove(AttributeType.fingerprint.value);
    // Assuming a createAttrSoftware equivalent function exists or is handled elsewhere
    // For now, let's add a placeholder SOFTWARE attribute if it's needed.
    final softwareAttr =
        createAttrSoftware("Dart STUN Client"); // Placeholder software name
    print(
        'Message.encode: Adding SOFTWARE attribute: ${softwareAttr.toString()}');
    attributes[softwareAttr.attributeType!.value] = softwareAttr;

    var encodedAttrs = Uint8List(0);
    // Sort attributes by type value before encoding for consistent order (recommended by RFC)
    final sortedAttributeKeys = attributes.keys.toList()..sort();
    print(
        'Message.encode: Encoding attributes in order: ${sortedAttributeKeys.map((k) => '0x${k.toRadixString(16)}').join(', ')}');
    for (final key in sortedAttributeKeys) {
      final attr = attributes[key]!;
      final encodedAttr = attr.encode();
      encodedAttrs = Uint8List.fromList([...encodedAttrs, ...encodedAttr]);
    }
    print(
        'Message.encode: Encoded attributes total length: ${encodedAttrs.length}');

    var result = Uint8List.fromList([
      ...Uint8List(stunHeaderSize), // Placeholder for header
      ...encodedAttrs
    ]);
    final byteData = ByteData.view(result.buffer);

    byteData.setUint16(0, messageType.encode(), Endian.big);
    byteData.setUint32(4, magicCookie, Endian.big);
    result.setRange(8, 8 + transactionIDSize, transactionID);
    print(
        'Message.encode: Initial message header and attributes created. Length: ${result.length}');

    // Post-encode: Calculate and add MESSAGE-INTEGRITY and FINGERPRINT

    // Calculate the size of MESSAGE-INTEGRITY and FINGERPRINT attributes with padding
    final messageIntegrityPaddedSize = attributeHeaderSize +
        hmacSignatureSize +
        (4 - (hmacSignatureSize % 4)) % 4;
    final fingerprintPaddedSize =
        attributeHeaderSize + fingerprintSize + (4 - (fingerprintSize % 4)) % 4;
    print(
        'Message.encode: MESSAGE-INTEGRITY padded size: $messageIntegrityPaddedSize');
    print('Message.encode: FINGERPRINT padded size: $fingerprintPaddedSize');

    // For HMAC calculation, the message length in the header is the length
    // of the message *excluding* MESSAGE-INTEGRITY and FINGERPRINT attributes.
    final lengthForHmacHeader = encodedAttrs.length;
    print(
        'Message.encode: Setting header length for HMAC calculation: $lengthForHmacHeader');
    ByteData.view(result.buffer).setUint16(2, lengthForHmacHeader, Endian.big);

    // Calculate HMAC over the message up to this point
    print('Message.encode: Calculating HMAC...');
    final hmac = calculateHmac(result, pwd);
    print('Message.encode: Calculated HMAC: ${hex.encode(hmac)}');

    final messageIntegrityAttr = Attribute(
      attributeType: AttributeType.messageIntegrity,
      value: hmac,
      offsetInMessage: result
          .length, // This offset is relative to the *current* result buffer
    );
    print('Message.encode: Encoding MESSAGE-INTEGRITY attribute...');
    final encodedMessageIntegrity = messageIntegrityAttr.encode();
    print(
        'Message.encode: Encoded MESSAGE-INTEGRITY length: ${encodedMessageIntegrity.length}');
    result = Uint8List.fromList([...result, ...encodedMessageIntegrity]);
    print(
        'Message.encode: Message length after adding MESSAGE-INTEGRITY: ${result.length}');

    // For Fingerprint calculation, the message length in the header is the length
    // of the message *including* the MESSAGE-INTEGRITY attribute, but *excluding* the FINGERPRINT attribute.
    final lengthForFingerprintHeader =
        encodedAttrs.length + encodedMessageIntegrity.length;
    print(
        'Message.encode: Setting header length for Fingerprint calculation: $lengthForFingerprintHeader');
    ByteData.view(result.buffer)
        .setUint16(2, lengthForFingerprintHeader, Endian.big);

    // Calculate Fingerprint over the message up to this point
    print('Message.encode: Calculating Fingerprint...');
    final fingerprint = calculateFingerprint(result);
    print('Message.encode: Calculated Fingerprint: ${hex.encode(fingerprint)}');

    final fingerprintAttr = Attribute(
      attributeType: AttributeType.fingerprint,
      value: fingerprint,
      offsetInMessage: result
          .length, // This offset is relative to the *current* result buffer
    );
    print('Message.encode: Encoding FINGERPRINT attribute...');
    final encodedFingerprint = fingerprintAttr.encode();
    print(
        'Message.encode: Encoded FINGERPRINT length: ${encodedFingerprint.length}');

    result = Uint8List.fromList([...result, ...encodedFingerprint]);
    print(
        'Message.encode: Message length after adding FINGERPRINT: ${result.length}');

    // Final update of the message length in the header with the total length
    final totalMessageLength = encodedAttrs.length +
        encodedMessageIntegrity.length +
        encodedFingerprint.length;
    print(
        'Message.encode: Final total message length for header: $totalMessageLength');
    ByteData.view(result.buffer).setUint16(2, totalMessageLength, Endian.big);

    print(
        'Message.encode: Finished encoding message. Final length: ${result.length}');
    return result;
  }

  void validate(String ufrag, String pwd) {
    print('Message.validate: Starting validation...');
    print('Message.validate: Validating against ufrag: "$ufrag"');

    final userNameAttr = attributes[AttributeType.userName.value];
    if (userNameAttr != null && userNameAttr.attributeType != null) {
      print('Message.validate: Found USERNAME attribute.');
      final userName = utf8.decode(userNameAttr.value).split(':')[0];
      print('Message.validate: Decoded username: "$userName"');
      if (userName != ufrag) {
        print('Message.validate: Error: Username mismatch.');
        throw Exception('Message not valid: UserName!');
      }
      print('Message.validate: Username validated successfully.');
    } else {
      print(
          'Message.validate: USERNAME attribute not found or is unknown type.');
    }

    final messageIntegrityAttr =
        attributes[AttributeType.messageIntegrity.value];
    if (messageIntegrityAttr != null &&
        messageIntegrityAttr.attributeType != null) {
      print('Message.validate: Found MESSAGE-INTEGRITY attribute.');
      print(
          'Message.validate: MESSAGE-INTEGRITY offset in raw message: ${messageIntegrityAttr.offsetInMessage}');
      print(
          'Message.validate: Received MESSAGE-INTEGRITY value: ${hex.encode(messageIntegrityAttr.value)}');

      // The HMAC is calculated over the STUN message, not including the MESSAGE-INTEGRITY
      // attribute itself, but including its header with a placeholder length that
      // accounts for the space the MESSAGE-INTEGRITY and FINGERPRINT attributes would occupy.

      // Create a temporary buffer that contains the raw message bytes up to the
      // start of the MESSAGE-INTEGRITY attribute.
      final binMsgForHmac =
          rawMessage.sublist(0, messageIntegrityAttr.offsetInMessage);
      print(
          'Message.validate: Buffer for HMAC calculation length: ${binMsgForHmac.length}');

      // Temporarily set the message length in the header of the temporary buffer.
      // This length is the total length of the original message *excluding* the
      // MESSAGE-INTEGRITY and FINGERPRINT attributes (including their headers and padding).
      final messageIntegrityPaddedSize = (attributeHeaderSize +
          hmacSignatureSize +
          (4 - (hmacSignatureSize % 4)) % 4);
      final fingerprintPaddedSize =
          (attributes.containsKey(AttributeType.fingerprint.value)
              ? (attributeHeaderSize +
                  fingerprintSize +
                  (4 - (fingerprintSize % 4)) % 4)
              : 0);

      final messageLengthForHmacHeader = (rawMessage.length - stunHeaderSize) -
          messageIntegrityPaddedSize -
          fingerprintPaddedSize;
      print(
          'Message.validate: Setting header length in temporary buffer for HMAC: $messageLengthForHmacHeader');
      ByteData.view(binMsgForHmac.buffer)
          .setUint16(2, messageLengthForHmacHeader, Endian.big);

      print('Message.validate: Calculating HMAC over temporary buffer...');
      final calculatedHmac = calculateHmac(binMsgForHmac, pwd);
      print('Message.validate: Calculated HMAC: ${hex.encode(calculatedHmac)}');

      if (!listEquals(calculatedHmac, messageIntegrityAttr.value)) {
        print('Message.validate: Error: MESSAGE-INTEGRITY mismatch.');
        throw Exception(
            'Message not valid: MESSAGE-INTEGRITY not valid expected: ${hex.encode(calculatedHmac)} , received: ${hex.encode(messageIntegrityAttr.value)} not compatible!');
      }
      print('Message.validate: MESSAGE-INTEGRITY validated successfully.');
    } else {
      print(
          'Message.validate: MESSAGE-INTEGRITY attribute not found or is unknown type.');
    }

    final fingerprintAttr = attributes[AttributeType.fingerprint.value];
    if (fingerprintAttr != null && fingerprintAttr.attributeType != null) {
      print('Message.validate: Found FINGERPRINT attribute.');
      print(
          'Message.validate: FINGERPRINT offset in raw message: ${fingerprintAttr.offsetInMessage}');
      print(
          'Message.validate: Received FINGERPRINT value: ${hex.encode(fingerprintAttr.value)}');

      // The Fingerprint is calculated over the entire STUN message including
      // the STUN header and the padded MESSAGE-INTEGRITY attribute,
      // but excluding the FINGERPRINT attribute itself.
      // The message length field in the header is set to the length *including*
      // the FINGERPRINT attribute when calculating the fingerprint.

      // Create a temporary buffer that contains the raw message bytes up to the
      // start of the FINGERPRINT attribute.
      final binMsgForFingerprint =
          rawMessage.sublist(0, fingerprintAttr.offsetInMessage);
      print(
          'Message.validate: Buffer for Fingerprint calculation length: ${binMsgForFingerprint.length}');

      // Temporarily set the message length in the header of the temporary buffer
      // to the total length of the original message *including* the Fingerprint attribute.
      final totalMessageLength = rawMessage.length;
      final messageLengthForFingerprintHeader =
          totalMessageLength - stunHeaderSize;
      print(
          'Message.validate: Setting header length in temporary buffer for Fingerprint: $messageLengthForFingerprintHeader');
      ByteData.view(binMsgForFingerprint.buffer)
          .setUint16(2, messageLengthForFingerprintHeader, Endian.big);

      print(
          'Message.validate: Calculating Fingerprint over temporary buffer...');
      final calculatedFingerprint = calculateFingerprint(binMsgForFingerprint);
      print(
          'Message.validate: Calculated Fingerprint: ${hex.encode(calculatedFingerprint)}');

      if (!listEquals(calculatedFingerprint, fingerprintAttr.value)) {
        print('Message.validate: Error: FINGERPRINT mismatch.');
        throw Exception(
            'Message not valid: FINGERPRINT not valid expected: ${hex.encode(calculatedFingerprint)} , received: ${hex.encode(fingerprintAttr.value)} not compatible!');
      }
      print('Message.validate: FINGERPRINT validated successfully.');
    } else {
      print(
          'Message.validate: FINGERPRINT attribute not found or is unknown type.');
    }
    print('Message.validate: Message validation finished.');
  }

  void setAttribute(Attribute attr) {
    final attributeKey = attr.attributeType != null
        ? attr.attributeType!.value
        : attr.rawAttributeType!;
    print(
        'Message.setAttribute: Setting attribute 0x${attributeKey.toRadixString(16)}');
    attributes[attributeKey] = attr;
  }

  // Helper function to create a Software attribute (placeholder for config value)
  Attribute createAttrSoftware(String software) {
    print(
        'Message.createAttrSoftware: Creating SOFTWARE attribute with value: "$software"');
    return Attribute(
      attributeType: AttributeType.software,
      value: utf8.encode(software) as Uint8List,
      offsetInMessage: 0, // Offset is determined during encoding
    );
  }

  @override
  String toString() {
    final transactionIDStr = base64Encode(transactionID);
    final attrsStr = attributes.values.map((a) => a.toString()).join(' ');
    return '$messageType id=$transactionIDStr attrs=$attrsStr';
  }
}

// Helper function for HMAC calculation
Uint8List calculateHmac(Uint8List binMsg, String pwd) {
  print('calculateHmac: Calculating HMAC...');
  final key = utf8.encode(pwd);
  final hmacSha1 = Hmac(sha1, key);
  final digest = hmacSha1.convert(binMsg);
  print('calculateHmac: HMAC calculation finished.');
  return Uint8List.fromList(digest.bytes);
}

// Helper function for Fingerprint calculation
Uint8List calculateFingerprint(Uint8List binMsg) {
  print('calculateFingerprint: Calculating Fingerprint (CRC32)...');
  final result = Uint8List(4);
  final byteData = ByteData.view(result.buffer);

  // You need a proper CRC32 implementation in Dart.
  // This is a placeholder.
  int crc = getCrc32(binMsg);
  print(
      'calculateFingerprint: Calculated CRC32 (placeholder): 0x${crc.toRadixString(16)}');

  final fingerprintValue = crc ^ fingerprintXorMask;
  print(
      'calculateFingerprint: Fingerprint value (CRC32 ^ Mask): 0x${fingerprintValue.toRadixString(16)}');

  byteData.setUint32(0, fingerprintValue, Endian.big);
  print('calculateFingerprint: Fingerprint calculation finished.');
  return result;
}

// Dummy CRC32 function (you need a proper implementation)
int getCrc32(Uint8List bytes) {
  // This is a placeholder. You need a proper CRC32 implementation in Dart.
  // You might find a package for this.
  print('getCrc32: Using dummy CRC32 implementation.');
  int crc = 0; // Dummy value
  // Basic checksum as a placeholder
  for (int i = 0; i < bytes.length; i++) {
    crc =
        (crc + bytes[i]) & 0xFFFFFFFF; // Simple sum, keeping it within 32 bits
  }
  print('getCrc32: Dummy CRC32 result: 0x${crc.toRadixString(16)}');
  return crc;
}

// Helper function to compare lists
bool listEquals<T>(List<T>? a, List<T>? b) {
  print('listEquals: Comparing lists.');
  const listEquality = ListEquality();
  final areEqual = listEquality.equals(a, b);
  print('listEquals: Lists are equal: $areEqual');
  return areEqual;
}

// IP Family used in MappedAddress and XorMappedAddress decoding
enum IPFamilyAttr {
  ipv4(0x01),
  ipv6(0x02);

  final int value;
  const IPFamilyAttr(this.value);

  factory IPFamilyAttr.fromInt(int value) =>
      IPFamilyAttr.values.firstWhere((e) => e.value == value,
          orElse: () =>
              throw Exception('Unknown IP family attribute value: $value'));
}

// Functions to decode specific attributes (based on attributes.go)
MappedAddress? decodeAttrXorMappedAddress(
    Attribute attr, Uint8List transactionID) {
  print('decodeAttrXorMappedAddress: Decoding XOR-MAPPED-ADDRESS attribute...');
  if (attr.attributeType != AttributeType.xorMappedAddress) {
    print(
        'decodeAttrXorMappedAddress: Attribute type is not XOR-MAPPED-ADDRESS.');
    return null;
  }
  if (transactionID.length != transactionIDSize) {
    print(
        'decodeAttrXorMappedAddress: Transaction ID size mismatch. Expected $transactionIDSize, got ${transactionID.length}.');
    return null; // Or throw an error if the transaction ID size is incorrect
  }

  final value = attr.value;
  print('decodeAttrXorMappedAddress: Attribute value length: ${value.length}');
  if (value.length < 8) {
    // Minimum length for XOR-MAPPED-ADDRESS is 8 bytes (1 family + 1 reserved + 2 port + 4 IPv4)
    // Or 20 bytes (1 family + 1 reserved + 2 port + 16 IPv6)
    print('decodeAttrXorMappedAddress: Attribute value length is too short.');
    return null; // Or throw an error
  }

  final byteData = ByteData.view(value.buffer);

  final int familyValue = value[1];
  print(
      'decodeAttrXorMappedAddress: Decoded family value: 0x${familyValue.toRadixString(16)}');
  final IPFamilyAttr ipFamily = IPFamilyAttr.fromInt(familyValue);

  final int port = byteData.getUint16(2, Endian.big);
  print('decodeAttrXorMappedAddress: Decoded raw port: $port');

  final Uint8List xorredAddressBytes = value.sublist(4);
  print(
      'decodeAttrXorMappedAddress: XORed address bytes length: ${xorredAddressBytes.length}');

  // Recreate the XOR mask: Magic Cookie (4 bytes) + Transaction ID (12 bytes)
  final xorMask = Uint8List(16);
  ByteData.view(xorMask.buffer).setUint32(0, magicCookie, Endian.big);
  xorMask.setRange(4, 16, transactionID);
  print(
      'decodeAttrXorMappedAddress: Generated XOR mask: ${hex.encode(xorMask)}');

  final addressBytes = Uint8List(xorredAddressBytes.length);
  for (int i = 0; i < xorredAddressBytes.length; i++) {
    addressBytes[i] = xorredAddressBytes[i] ^ xorMask[i];
  }
  print(
      'decodeAttrXorMappedAddress: Decoded address bytes: ${hex.encode(addressBytes)}');

  InternetAddress ip;
  try {
    print(
        'decodeAttrXorMappedAddress: Attempting to create InternetAddress...');
    ip = InternetAddress.fromRawAddress(addressBytes);
    print('decodeAttrXorMappedAddress: Created InternetAddress: ${ip.address}');
  } catch (e) {
    print(
        'decodeAttrXorMappedAddress: Error creating InternetAddress from bytes: $e');
    return null; // Or handle the error appropriately
  }

  // Port is XORed with the first 2 bytes of the XOR mask (Magic Cookie's first 2 bytes)
  final int portModifier =
      ByteData.view(xorMask.buffer).getUint16(0, Endian.big);
  print(
      'decodeAttrXorMappedAddress: Port XOR modifier: 0x${portModifier.toRadixString(16)}');
  final int decodedPort = port ^ portModifier;
  print('decodeAttrXorMappedAddress: Decoded port: $decodedPort');

  final mappedAddress = MappedAddress(
      ipFamily: ipFamily == IPFamilyAttr.ipv4 ? IPFamily.ipv4 : IPFamily.ipv6,
      ip: ip,
      port: decodedPort);
  print(
      'decodeAttrXorMappedAddress: Successfully decoded MappedAddress: $mappedAddress');
  return mappedAddress;
}

// Function to create a User Name attribute (based on attributes.go)
Attribute createAttrUserName(String userName) {
  print(
      'createAttrUserName: Creating USERNAME attribute with value: "$userName"');
  return Attribute(
    attributeType: AttributeType.userName,
    value: utf8.encode(userName) as Uint8List,
    offsetInMessage: 0, // Offset is determined during encoding
  );
}

// StunClient class (based on stunclient.go)
class StunClient {
  final String serverAddr;
  final String ufrag;
  final String pwd;

  StunClient(
      {required this.serverAddr, required this.ufrag, required this.pwd});

  Future<MappedAddress?> discover() async {
    print('StunClient.discover: Starting STUN discovery...');
    try {
      print('StunClient.discover: Generating transaction ID...');
      final transactionID = generateTransactionID();
      print(
          'StunClient.discover: Generated transaction ID: ${hex.encode(transactionID)}');

      print('StunClient.discover: Resolving server address: $serverAddr');
      final resolvedServerAddress =
          await InternetAddress.lookup(Uri.parse(serverAddr).host);
      if (resolvedServerAddress.isEmpty) {
        print('StunClient.discover: Error: Could not resolve server address.');
        return null;
      }
      final serverIP = resolvedServerAddress.first;
      final serverPort = Uri.parse(serverAddr).port;
      print(
          'StunClient.discover: Resolved server IP: ${serverIP.address}, Port: $serverPort');

      final serverEndpoint =
          InternetAddress(serverIP.address, type: serverIP.type);
      print(
          'StunClient.discover: Server endpoint: ${serverEndpoint.address}:${serverPort}');

      print('StunClient.discover: Creating Binding Request message...');
      final bindingRequest = createBindingRequest(transactionID);
      print('StunClient.discover: Encoding Binding Request message...');
      final encodedBindingRequest = bindingRequest.encode(pwd);
      print(
          'StunClient.discover: Encoded Binding Request length: ${encodedBindingRequest.length}');

      print('StunClient.discover: Binding to a UDP socket...');
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      print(
          'StunClient.discover: Bound to local address: ${socket.address.address}:${socket.port}');

      print(
          'StunClient.discover: Sending Binding Request to ${serverEndpoint.address}:${serverPort}');
      try {
        final sentBytes =
            socket.send(encodedBindingRequest, serverEndpoint, serverPort);
        print('StunClient.discover: Sent $sentBytes bytes.');
      } catch (e) {
        print('StunClient.discover: Error sending data: $e');
        socket.close();
        return null;
      }

      print('StunClient.discover: Waiting for response...');
      await for (RawSocketEvent event in socket) {
        print('StunClient.discover: Received socket event: $event');
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram == null) {
            print('StunClient.discover: Received null datagram.');
            continue;
          }

          final buf = datagram.data;
          final addr = datagram.address;
          final port = datagram.port;
          print(
              'StunClient.discover: Received ${buf.length} bytes from ${addr.address}:${port}');

          // If requested target server address and responder address not fit, ignore the packet
          // Comparing raw addresses for robustness
          if (!listEquals(addr.rawAddress, serverEndpoint.rawAddress) ||
              port != serverPort) {
            print(
                'StunClient.discover: Received packet from unexpected source. Expected ${serverEndpoint.address}:${serverPort}, got ${addr.address}:${port}. Ignoring.');
            continue;
          }
          print(
              'StunClient.discover: Received packet from the expected server.');

          try {
            print(
                'StunClient.discover: Attempting to decode received message...');
            // Validate that it's a STUN message first based on magic cookie
            if (buf.length >= stunHeaderSize) {
              final magicCookieVal =
                  ByteData.view(buf.buffer).getUint32(4, Endian.big);
              print(
                  'StunClient.discover: Received packet Magic Cookie: 0x${magicCookieVal.toRadixString(16)}');
              if (magicCookieVal != magicCookie) {
                print(
                    'StunClient.discover: Magic Cookie mismatch. Not a STUN message. Ignoring.');
                // Not a STUN message, could be Channel Data or something else, ignore for now
                continue;
              }
              print(
                  'StunClient.discover: Magic Cookie matches. Likely a STUN message.');
            } else {
              print(
                  'StunClient.discover: Received packet too short for STUN header. Ignoring.');
              continue;
            }

            final stunMessage = Message.decode(buf);
            print('StunClient.discover: Successfully decoded STUN message.');
            print('StunClient.discover: Validating STUN message...');
            stunMessage.validate(ufrag, pwd);
            print('StunClient.discover: STUN message validated successfully.');

            if (!listEquals(stunMessage.transactionID, transactionID)) {
              print(
                  'StunClient.discover: Transaction ID mismatch. Expected ${hex.encode(transactionID)}, got ${hex.encode(stunMessage.transactionID)}. Ignoring.');
              continue;
            }
            print('StunClient.discover: Transaction ID matches.');

            print(
                'StunClient.discover: Checking for XOR-MAPPED-ADDRESS attribute...');
            final xorMappedAddressAttr =
                stunMessage.attributes[AttributeType.xorMappedAddress.value];
            if (xorMappedAddressAttr == null ||
                xorMappedAddressAttr.attributeType == null) {
              print(
                  'StunClient.discover: XOR-MAPPED-ADDRESS attribute not found or is unknown type. Ignoring.');
              continue;
            }
            print('StunClient.discover: Found XOR-MAPPED-ADDRESS attribute.');

            print(
                'StunClient.discover: Decoding XOR-MAPPED-ADDRESS attribute...');
            final mappedAddress = decodeAttrXorMappedAddress(
                xorMappedAddressAttr,
                Uint8List.fromList(
                    stunMessage.transactionID)); // Pass Uint8List
            if (mappedAddress != null) {
              print(
                  'StunClient.discover: Successfully decoded Mapped Address: $mappedAddress');
              socket.close();
              print('StunClient.discover: Closed socket. Discovery finished.');
              return mappedAddress;
            } else {
              print(
                  'StunClient.discover: Failed to decode XOR-MAPPED-ADDRESS. Ignoring message.');
              continue; // Continue listening for other packets
            }
          } catch (e) {
            print(
                'StunClient.discover: Error processing received STUN message: $e');
            // Continue listening for other packets if decoding/validation fails
            continue;
          }
        }
      }
    } catch (e) {
      print('StunClient.discover: Error during STUN discovery: $e');
      return null; // Or re-throw the error
    }
    print(
        'StunClient.discover: Discovery loop finished without finding a valid mapped address.');
    return null; // Should not reach here in a typical discovery loop unless an error occurred or socket closed
  }

  Uint8List generateTransactionID() {
    print('generateTransactionID: Generating new transaction ID...');
    final random = Random.secure();
    final transactionID = Uint8List(transactionIDSize);
    for (int i = 0; i < transactionIDSize; i++) {
      transactionID[i] = random.nextInt(256);
    }
    print('generateTransactionID: Generated ID: ${hex.encode(transactionID)}');
    return transactionID;
  }

  Message createBindingRequest(Uint8List transactionID) {
    print('createBindingRequest: Creating STUN Binding Request...');
    final messageTypeBindingRequest = MessageType(
      messageMethod: MessageMethod.stunBinding,
      messageClass: MessageClass.request,
    );
    final responseMessage = Message(
      messageType: messageTypeBindingRequest,
      transactionID: transactionID,
      attributes: {},
      rawMessage: Uint8List(0), // Raw message is set during encoding
    );
    print('createBindingRequest: Binding Request message created.');
    // Add any required attributes for a Binding Request, e.g., SOFTWARE if needed
    // responseMessage.setAttribute(createAttrSoftware("Dart STUN Client"));
    return responseMessage;
  }
}
