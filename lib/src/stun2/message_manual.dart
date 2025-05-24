// var (
// 	//errInvalidTURNFrame    = errors.New("data is not a valid TURN frame, no STUN or ChannelData found")
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../agent/udp_client_socket.dart';
import 'attribute.dart';
import 'attribute_type.dart';
import 'attributes.dart';
import 'crc32.dart';
import 'message_type.dart';
import 'package:crypto/crypto.dart'; // You'll need to add the 'crypto' package to your pubspec.yaml
import '../stun/bits/bit_buffer.dart';

Exception errIncompleteTURNFrame =
    Exception("data contains incomplete STUN or TURN frame");
// )

class Message {
  MessageType messageType;
  Uint8List transactionID = Uint8List(TransactionIDSize);
  Map<dynamic, Attribute> attributes;
  late Uint8List rawMessage;

  Message(
      {required this.messageType,
      required this.transactionID,
      required this.attributes});

  factory Message.newMessage(MessageType messageType, Uint8List transactionID) {
    return Message(
      messageType: messageType,
      transactionID: transactionID,
      attributes: {},
    );
  }

  void setAttribute(Attribute attr) {
    attributes[attr.attributeType] = attr;
  }

  Uint8List encode(String pwd) {
    // print("attributes at encoding: $attributes");
    preEncode();
    // https://github.com/jitsi/ice4j/blob/311a495b21f38cc2dfcc4f7118dab96b8134aed6/src/main/java/org/ice4j/message/Message.java#L907

    List<Attribute> listedAttr = attributes.entries
        .where((entry) {
          return true;
        })
        .map((entry) => entry.value)
        .toList();

    List<Uint8List> encodedAttrs =
        List.generate(listedAttr.length, (index) => listedAttr[index].encode());
    // for _, attr := range m.Attributes {
    // 	encodedAttr := attr.Encode()
    // 	encodedAttrs = append(encodedAttrs, encodedAttr...)
    // }

    Iterable<int> count(Uint8List n) sync* {
      for (int i in n) {
        yield i;
      }
    }

    // final encodedListAttr=
    // encodedAttrs.expand(count);

    final encodedListAttr =
        Uint8List.fromList(encodedAttrs.expand(count).toList());

    final msgData = Uint8List(messageHeaderSize + encodedListAttr.length);

    final bd = ByteData.sublistView(msgData);

    bd.setUint16(0, messageType.encode());
    bd.setUint16(2, encodedAttrs.length);
    bd.setUint32(4, magicCookie);
    // copy(result[8:20], m.TransactionID[:])
    msgData.setRange(8, 20, transactionID);
    msgData.setAll(20, encodedListAttr);
    // copy(result[20:], encodedAttrs)
    final result = postEncode(msgData, encodedListAttr.length, pwd);

    return result;
  }

  void preEncode() {
    // https://github.com/jitsi/ice4j/blob/32a8aadae8fde9b94081f8d002b6fda3490c20dc/src/main/java/org/ice4j/message/Message.java#L1015
    // delete(m.Attributes, AttrMessageIntegrity)
    attributes.remove(AttributeType.MessageIntegrity);
    attributes.remove(AttributeType.Fingerprint);
    // delete(m.Attributes, AttrFingerprint)
    attributes[AttributeType.Software] =
        createAttrSoftware("config.Val.Server.SoftwareName");
  }

  Uint8List postEncode(Uint8List encodedMessage, int dataLength, String pwd) {
    // https://github.com/jitsi/ice4j/blob/32a8aadae8fde9b94081f8d002b6fda3490c20dc/src/main/java/org/ice4j/message/Message.java#L1015
    Uint8List valueMsgIntegrity = calculateHmac(encodedMessage, pwd);

    final messageIntegrityAttr = Attribute(
      attributeType: AttributeType.MessageIntegrity,
      value: valueMsgIntegrity,
      // offsetInMessage: valueMsgIntegrity.length
    );

    final encodedMessageIntegrity = messageIntegrityAttr.encode();
    encodedMessage =
        Uint8List.fromList([...encodedMessage, ...encodedMessageIntegrity]);

    Uint8List valueFingerprint = calculateFingerprint(encodedMessage);
    final messageFingerprint = Attribute(
      attributeType: AttributeType.Fingerprint,
      value: valueFingerprint,
      // offsetInMessage: valueFingerprint.length
    );

    final encodedFingerprint = messageFingerprint.encode();

    encodedMessage =
        Uint8List.fromList([...encodedMessage, ...encodedFingerprint]);

    final bd = ByteData.sublistView(encodedMessage);

    bd.setUint16(
        2,
        dataLength +
            encodedMessageIntegrity.length +
            encodedFingerprint.length);

    return encodedMessage;
  }

  Attribute createAttrSoftware(String software) {
    final value = utf8.encode(software);
    return Attribute(
      attributeType: AttributeType.Software,
      value: value,
      // offsetInMessage: value.length
    );
  }

  static Message decodeMessage(Uint8List buf, int offset, int arrayLen) {
    // final bd = ByteData.sublistView(stunData);

    BitBufferReader reader = BitBufferReader(BitBuffer.fromUint8List(buf));

    final first2Bits = reader.readUint(binaryDigits: 2);
    // print("First 2 bits: $first2Bits");
    final msgType = reader.readUint(binaryDigits: 14);

    final messageType = decodeMessageType(msgType);

    // print("Message type: $messageType");

    final msgLength = reader.readUint(binaryDigits: 16);
    // print("Message length: $msgLength");
    // print("Data length: ${stunData.length}");
    final magicCookie = reader.readUint(binaryDigits: 32);
    // print("Magic cookie: $magicCookie");

    if (magicCookie != 0x2112A442) {
      // print("Warning: Invalid STUN Magic Cookie.");
      // Proceeding with parsing anyway for informational purposes.
    } else {
      // print("STUN Magic Cookie is valid : ${0x2112A442}");
    }
    final transactionId =
        List.generate(12, (element) => reader.readUint(binaryDigits: 8));
    // reader.readIntList(12, binaryDigits: 96);
    // print("Transaction ID: $transactionId, Length: ${transactionId.length}");

    final Map<dynamic, Attribute> attributes = {};
    while (reader.remaining > 0) {
      final type = reader.readUint(binaryDigits: 16);
      int length = reader.readUint(binaryDigits: 16);
      if (length % 4 != 0) {
        length = length + (4 - (length % 4));
        print("modulus length: $length");
      }

      final value =
          List.generate(length, (element) => reader.readUint(binaryDigits: 8));

      try {
        // print("""STUN attr[$iterator]{type: ${AttributeType.fromInt(type)},
        //    Length: $length, Actual length: $backupLength, Value: ${type == AttributeType.UserName.value ? utf8.decode(value.sublist(0, backupLength)) : value}""");
        attributes[AttributeType.fromInt(type)] = Attribute(
          attributeType: AttributeType.fromInt(type),
          value: Uint8List.fromList(value),
          // offsetInMessage: offsetBackup
        );
      } catch (e) {
        // print(
        //     """STUN attr[$iterator]{type: 0x${type.toRadixString(16).padLeft(4, '0')}},
        //    Length: $length, Actual length: $backupLength, Value: $value}""");
        attributes[type] = Attribute(
          attributeType: type,
          value: Uint8List.fromList(value),
          // offsetInMessage: offsetBackup
        );
      }
    }

    print("decoded attributes: $attributes");

    return Message(
        messageType: messageType,
        attributes: attributes,
        transactionID: Uint8List.fromList(transactionId));
  }

  @override
  String toString() {
    return "Message{attributes: $attributes}";
  }
}

// 	magicCookie       = 0x2112A442
const messageHeaderSize = 20;

const TransactionIDSize = 12; // 96 bit

const stunHeaderSize = 20;

// 	hmacSignatureSize = 20

// 	fingerprintSize = 4

const fingerprintXorMask = 0x5354554e;

// func calculateHmac(binMsg []byte, pwd string) []byte {
// 	key := []byte(pwd)
// 	messageLength := uint16(len(binMsg) + attributeHeaderSize + hmacSignatureSize - messageHeaderSize)
// 	binary.BigEndian.PutUint16(binMsg[2:4], messageLength)
// 	mac := hmac.New(sha1.New, key)
// 	mac.Write(binMsg)
// 	return mac.Sum(nil)
// }

// Helper function for HMAC calculation
Uint8List calculateHmac(Uint8List binMsg, String pwd) {
  print('calculateHmac: Calculating HMAC...');
  final key = utf8.encode(pwd);
  final hmacSha1 = Hmac(sha1, key);
  final digest = hmacSha1.convert(binMsg);
  print('calculateHmac: HMAC calculation finished.');
  return Uint8List.fromList(digest.bytes);
}

// func calculateFingerprint(binMsg []byte) []byte {
// 	result := make([]byte, 4)
// 	messageLength := uint16(len(binMsg) + attributeHeaderSize + fingerprintSize - messageHeaderSize)
// 	binary.BigEndian.PutUint16(binMsg[2:4], messageLength)

// 	binary.BigEndian.PutUint32(result, crc32.ChecksumIEEE(binMsg)^fingerprintXorMask)
// 	return result
// }

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
  return crc32(bytes);
  // This is a placeholder. You need a proper CRC32 implementation in Dart.
  // You might find a package for this.
}

// func (m *Message) Validate(ufrag string, pwd string) {
// 	// https://github.com/jitsi/ice4j/blob/311a495b21f38cc2dfcc4f7118dab96b8134aed6/src/main/java/org/ice4j/stack/StunStack.java#L1254
// 	userNameAttr, okUserName := m.Attributes[AttrUserName]
// 	if okUserName {
// 		userName := strings.Split(string(userNameAttr.Value), ":")[0]
// 		if userName != ufrag {
// 			panic("Message not valid: UserName!")
// 		}
// 	}
// 	if messageIntegrityAttr, ok := m.Attributes[AttrMessageIntegrity]; ok {
// 		if !okUserName {
// 			panic("Message not valid: missing username!")
// 		}
// 		binMsg := make([]byte, messageIntegrityAttr.OffsetInMessage)
// 		copy(binMsg, m.RawMessage[0:messageIntegrityAttr.OffsetInMessage])

// 		calculatedHmac := calculateHmac(binMsg, pwd)
// 		if !bytes.Equal(calculatedHmac, messageIntegrityAttr.Value) {
// 			panic(fmt.Sprintf("Message not valid: MESSAGE-INTEGRITY not valid expected: %v , received: %v not compatible!", calculatedHmac, messageIntegrityAttr.Value))
// 		}
// 	}

// 	if fingerprintAttr, ok := m.Attributes[AttrFingerprint]; ok {
// 		binMsg := make([]byte, fingerprintAttr.OffsetInMessage)
// 		copy(binMsg, m.RawMessage[0:fingerprintAttr.OffsetInMessage])

// 		calculatedFingerprint := calculateFingerprint(binMsg)
// 		if !bytes.Equal(calculatedFingerprint, fingerprintAttr.Value) {
// 			panic(fmt.Sprintf("Message not valid: FINGERPRINT not valid expected: %v , received: %v not compatible!", calculatedFingerprint, fingerprintAttr.Value))
// 		}
// 	}
// }

Future<void> main() async {
  // StunProtocol stunProtocol = StunProtocol.RFC5780;
  // final StunMessage? parsedMessage = StunMessage.form(udpData, stunProtocol);

  final Message parsedMessage =
      Message.decodeMessage(udpData, 0, udpData.length);

  // final StunMessage? parsedMessage = parseStunPacket(udpData);

  // if (parsedMessage != null) {
  print(parsedMessage);
  final encoded = parsedMessage.encode("KTSf");
  print("Encoded message: $encoded");
  Message.decodeMessage(encoded, 0, encoded.length);
  RawDatagramSocket socket =
      await RawDatagramSocket.bind(InternetAddress("127.0.0.1"), 4444);
  final reponseMsg = createBindingResponse(parsedMessage, socket,
      utf8.decode(parsedMessage.attributes[AttributeType.UserName]!.value));

  print("Presponse: $reponseMsg");

  // }
}

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
