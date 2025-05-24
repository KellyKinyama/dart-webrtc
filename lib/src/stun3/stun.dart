//6.  STUN Message Structure
//
//    STUN messages are encoded in binary using network-oriented format
//    (most significant byte or octet first, also commonly known as big-
//    endian).  The transmission order is described in detail in Appendix B
//    of RFC 791 [RFC0791].  Unless otherwise noted, numeric constants are
//    in decimal (base 10).
//
//    All STUN messages MUST start with a 20-byte header followed by zero
//    or more Attributes.  The STUN header contains a STUN message type,
//    magic cookie, transaction ID, and message length.
//
//        0               8               16              24            31
//        0                   1                   2                   3
//        0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
//       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//       |0 0|     STUN Message Type     |         Message Length        |
//       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//       |                         Magic Cookie                          |
//       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//       |                                                               |
//       |                     Transaction ID (96 bits)                  |
//       |                                                               |
//       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//
//                   Figure 2: Format of STUN Message Header
//
//    The most significant 2 bits of every STUN message MUST be zeroes.
//    This can be used to differentiate STUN packets from other protocols
//    when STUN is multiplexed with other protocols on the same port.
//
//    The message type defines the message class (request, success
//    response, failure response, or indication) and the message method
//    (the primary function) of the STUN message.  Although there are four
//    message classes, there are only two types of transactions in STUN:
//    request/response transactions (which consist of a request message and
//    a response message) and indication transactions (which consist of a
//    single indication message).  Response classes are split into error
//    and success responses to aid in quickly processing the STUN message.
//
//    The message type field is decomposed further into the following
//    structure:
//
//                         0                 1
//                         2  3  4 5 6 7 8 9 0 1 2 3 4 5
//
//                        +--+--+-+-+-+-+-+-+-+-+-+-+-+-+
//                        |M |M |M|M|M|C|M|M|M|C|M|M|M|M|
//                        |11|10|9|8|7|1|6|5|4|0|3|2|1|0|
//                        +--+--+-+-+-+-+-+-+-+-+-+-+-+-+
//
//                 Figure 3: Format of STUN Message Type Field
//
//    Here the bits in the message type field are shown as most significant
//    (M11) through least significant (M0).  M11 through M0 represent a 12-
//    bit encoding of the method.  C1 and C0 represent a 2-bit encoding of
//    the class.  A class of 0b00 is a request, a class of 0b01 is an
//    indication, a class of 0b10 is a success response, and a class of
//    0b11 is an error response.  This specification defines a single
//    method, Binding.  The method and class are orthogonal, so that for
//    each method, a request, success response, error response, and
//    indication are possible for that method.  Extensions defining new
//    methods MUST indicate which classes are permitted for that method.
//
//    For example, a Binding request has class=0b00 (request) and
//    method=0b000000000001 (Binding) and is encoded into the first 16 bits
//    as 0x0001.  A Binding response has class=0b10 (success response) and
//    method=0b000000000001, and is encoded into the first 16 bits as
//    0x0101.
//
//       Note: This unfortunate encoding is due to assignment of values in
//       [RFC3489] that did not consider encoding Indications, Success, and
//       Errors using bit fields.
//
//    The magic cookie field MUST contain the fixed value 0x2112A442 in
//    network byte order.  In RFC 3489 [RFC3489], this field was part of
//    the transaction ID; placing the magic cookie in this location allows
//    a server to detect if the client will understand certain attributes
//    that were added in this revised specification.  In addition, it aids
//    in distinguishing STUN packets from packets of other protocols when
//    STUN is multiplexed with those other protocols on the same port.
//
//    The transaction ID is a 96-bit identifier, used to uniquely identify
//    STUN transactions.  For request/response transactions, the
//    transaction ID is chosen by the STUN client for the request and
//    echoed by the server in the response.  For indications, it is chosen
//    by the agent sending the indication.  It primarily serves to
//    correlate requests with responses, though it also plays a small role
//    in helping to prevent certain types of attacks.  The server also uses
//    the transaction ID as a key to identify each transaction uniquely
//    across all clients.  As such, the transaction ID MUST be uniformly
//    and randomly chosen from the interval 0 .. 2**96-1, and SHOULD be
//    cryptographically random.  Resends of the same request reuse the same
//    transaction ID, but the client MUST choose a new transaction ID for
//    new transactions unless the new request is bit-wise identical to the
//    previous request and sent from the same transport address to the same
//    IP address.  Success and error responses MUST carry the same
//    transaction ID as their corresponding request.  When an agent is
//    acting as a STUN server and STUN client on the same port, the
//    transaction IDs in requests sent by the agent have no relationship to
//    the transaction IDs in requests received by the agent.
//
//    The message length MUST contain the size, in bytes, of the message
//    not including the 20-byte STUN header.  Since all STUN attributes are
//    padded to a multiple of 4 bytes, the last 2 bits of this field are
//    always zero.  This provides another way to distinguish STUN packets
//    from packets of other protocols.
//
//    Following the STUN fixed portion of the header are zero or more
//    attributes.  Each attribute is TLV (Type-Length-Value) encoded.  The
//    details of the encoding, and of the attributes themselves are given
//    in Section 15.

import 'dart:convert';
import 'dart:typed_data';
import '../stun/bits/bit_buffer.dart';
import '../stun2/attribute_type.dart';
import '../stun2/message_type.dart';

enum StunProtocol {
  RFC3489,
  RFC5389,
  RFC5780,
}

void main() {
  // final bd = ByteData.sublistView(stunData);

  BitBufferReader reader = BitBufferReader(BitBuffer.fromUint8List(stunData));

  final first2Bits = reader.readUint(binaryDigits: 2);
  print("First 2 bits: $first2Bits");
  final msgType = reader.readUint(binaryDigits: 14);

  final messageType = decodeMessageType(msgType);

  print("Message type: $messageType");

  final msgLength = reader.readUint(binaryDigits: 16);
  print("Message length: $msgLength");
  // print("Data length: ${stunData.length}");
  final magicCookie = reader.readUint(binaryDigits: 32);
  print("Magic cookie: $magicCookie");

  if (magicCookie != 0x2112A442) {
    print("Warning: Invalid STUN Magic Cookie.");
    // Proceeding with parsing anyway for informational purposes.
  } else {
    print("STUN Magic Cookie is valid : ${0x2112A442}");
  }
  final transactionId =
      List.generate(12, (element) => reader.readUint(binaryDigits: 8));
  // reader.readIntList(12, binaryDigits: 96);
  print("Transaction ID: $transactionId, Length: ${transactionId.length}");

  int iterator = 0;
  while (reader.remaining > 0) {
    final type = reader.readUint(binaryDigits: 16);
    int length = reader.readUint(binaryDigits: 16);
    final backupLength = length;
    if (length % 4 != 0) {
      length = length + (4 - (length % 4));
      print("modulus length: $length");
    }

    final value =
        List.generate(length, (element) => reader.readUint(binaryDigits: 8));

    try {
      print("""STUN attr[$iterator]{type: ${AttributeType.fromInt(type)},
         Length: $length, Actual length: $backupLength, Value: ${type == AttributeType.UserName.value ? utf8.decode(value.sublist(0, backupLength)) : value}""");
    } catch (e) {
      print(
          """STUN attr[$iterator]{type: 0x${type.toRadixString(16).padLeft(4, '0')}},
         Length: $length, Actual length: $backupLength, Value: $value}""");
    }

    iterator++;
  }

  //  while (reader.remaining > 0) {
  //   final type = reader.readUint(binaryDigits: 16);
  //   final length = reader.readUint(binaryDigits: 16);
  //   final value = //reader.readUint(binaryDigits: 16);
  //       List.generate(8, (element) => reader.readUint(binaryDigits: 8));
  //   // final padding=
  //   // print(
  //   //     "STUN attr[$iterator]{type: ${reader.readUint(binaryDigits: 16)}, Length: ${reader.readUint(binaryDigits: 16)}}");
  //   iterator++;
  // }
}

final Uint8List stunData = Uint8List.fromList([
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
