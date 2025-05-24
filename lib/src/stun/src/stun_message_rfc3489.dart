/*
 * Copyright (C) 2025 halifox
 *
 * This file is part of dart_stun.
 *
 * dart_stun is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation, either version 3 of the License,
 * or (at your option) any later version.
 *
 * dart_stun is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with dart_stun. If not, see <http://www.gnu.org/licenses/>.
 */

import 'dart:convert';
import 'dart:typed_data';

import '../bits/bit_buffer.dart';
import '../stun.dart';

// 11.2  Message Attributes
//
//    After the header are 0 or more attributes.  Each attribute is TLV
//    encoded, with a 16 bit type, 16 bit length, and variable value:
//
//     0                   1                   2                   3
//     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
//    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//    |         Type                  |            Length             |
//    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//    |                             Value                             ....
//    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//
//    The following types are defined:
//
//    0x0001: MAPPED-ADDRESS
//    0x0002: RESPONSE-ADDRESS
//    0x0003: CHANGE-REQUEST
//    0x0004: SOURCE-ADDRESS
//    0x0005: CHANGED-ADDRESS
//    0x0006: USERNAME
//    0x0007: PASSWORD
//    0x0008: MESSAGE-INTEGRITY
//    0x0009: ERROR-CODE
//    0x000a: UNKNOWN-ATTRIBUTES
//    0x000b: REFLECTED-FROM
//
//    To allow future revisions of this specification to add new attributes
//    if needed, the attribute space is divided into optional and mandatory
//    ones.  Attributes with values greater than 0x7fff are optional, which
//    means that the message can be processed by the client or server even
//    though the attribute is not understood.  Attributes with values less
//    than or equal to 0x7fff are mandatory to understand, which means that
//    the client or server cannot process the message unless it understands
//    the attribute.
//
//    The MESSAGE-INTEGRITY attribute MUST be the last attribute within a
//    message.  Any attributes that are known, but are not supposed to be
//    present in a message (MAPPED-ADDRESS in a request, for example) MUST
//    be ignored.
//
//    Table 2 indicates which attributes are present in which messages.  An
//    M indicates that inclusion of the attribute in the message is
//    mandatory, O means its optional, C means it's conditional based on
//    some other aspect of the message, and N/A means that the attribute is
//    not applicable to that message type.
//
//
//
//
//
// Rosenberg, et al.           Standards Track                    [Page 26]
//
// RFC 3489                          STUN                        March 2003
//
//
//                                          Binding  Shared  Shared  Shared
//                        Binding  Binding  Error    Secret  Secret  Secret
//    Att.                Req.     Resp.    Resp.    Req.    Resp.   Error
//                                                                   Resp.
//    _____________________________________________________________________
//    MAPPED-ADDRESS      N/A      M        N/A      N/A     N/A     N/A
//    RESPONSE-ADDRESS    O        N/A      N/A      N/A     N/A     N/A
//    CHANGE-REQUEST      O        N/A      N/A      N/A     N/A     N/A
//    SOURCE-ADDRESS      N/A      M        N/A      N/A     N/A     N/A
//    CHANGED-ADDRESS     N/A      M        N/A      N/A     N/A     N/A
//    USERNAME            O        N/A      N/A      N/A     M       N/A
//    PASSWORD            N/A      N/A      N/A      N/A     M       N/A
//    MESSAGE-INTEGRITY   O        O        N/A      N/A     N/A     N/A
//    ERROR-CODE          N/A      N/A      M        N/A     N/A     M
//    UNKNOWN-ATTRIBUTES  N/A      N/A      C        N/A     N/A     C
//    REFLECTED-FROM      N/A      C        N/A      N/A     N/A     N/A
//
//    Table 2: Summary of Attributes
//
//    The length refers to the length of the value element, expressed as an
//    unsigned integral number of bytes.

var types = {
  StunAttributes.TYPE_MAPPED_ADDRESS: () => MappedAddressAttribute(),
  StunAttributes.TYPE_RESPONSE_ADDRESS: () => ResponseAddress(),
  StunAttributes.TYPE_CHANGE_ADDRESS: () => ChangeAddress(),
  StunAttributes.TYPE_SOURCE_ADDRESS: () => SourceAddress(),
  StunAttributes.TYPE_CHANGED_ADDRESS: () => ChangedAddress(),
  StunAttributes.TYPE_USERNAME: () => Username(),
  StunAttributes.TYPE_PASSWORD: () => Password(),
  StunAttributes.TYPE_MESSAGE_INTEGRITY: () => MessageIntegrity(),
  StunAttributes.TYPE_ERROR_CODE: () => ErrorCode(),
  StunAttributes.TYPE_UNKNOWN_ATTRIBUTES: () => UnknownAttributes(),
  StunAttributes.TYPE_REFLECTED_FROM: () => ReflectedFrom(),
};

StunAttributes? resolveAttribute(BitBufferReader reader, int type, int length) {
  var creator = types[type];
  if (creator == null) return null;
  StunAttributes attribute = creator();
  attribute.fromBuffer(reader, type, length);
  return attribute;
}

// 11.2.1 MAPPED-ADDRESS
//
//    The MAPPED-ADDRESS attribute indicates the mapped IP address and
//    port.  It consists of an eight bit address family, and a sixteen bit
//    port, followed by a fixed length value representing the IP address.
//
//     0                   1                   2                   3
//     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
//    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//    |x x x x x x x x|    Family     |           Port                |
//    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//    |                             Address                           |
//    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//
//    The port is a network byte ordered representation of the mapped port.
//    The address family is always 0x01, corresponding to IPv4.  The first
//    8 bits of the MAPPED-ADDRESS are ignored, for the purposes of
//    aligning parameters on natural boundaries.  The IPv4 address is 32
//    bits.
class MappedAddressAttribute extends AddressAttribute {
  @override
  int type = StunAttributes.TYPE_MAPPED_ADDRESS;
}

// 11.2.2 RESPONSE-ADDRESS
//
//    The RESPONSE-ADDRESS attribute indicates where the response to a
//    Binding Request should be sent.  Its syntax is identical to MAPPED-
//    ADDRESS.
class ResponseAddress extends AddressAttribute {
  @override
  int type = StunAttributes.TYPE_RESPONSE_ADDRESS;
}

// 11.2.3  CHANGED-ADDRESS
//
//    The CHANGED-ADDRESS attribute indicates the IP address and port where
//    responses would have been sent from if the "change IP" and "change
//    port" flags had been set in the CHANGE-REQUEST attribute of the
//    Binding Request.  The attribute is always present in a Binding
//    Response, independent of the value of the flags.  Its syntax is
//    identical to MAPPED-ADDRESS.
class ChangedAddress extends AddressAttribute {
  @override
  int type = StunAttributes.TYPE_CHANGED_ADDRESS;
}

// 11.2.4 CHANGE-REQUEST
//
//    The CHANGE-REQUEST attribute is used by the client to request that
//    the server use a different address and/or port when sending the
//    response.  The attribute is 32 bits long, although only two bits (A
//    and B) are used:
//
//     0                   1                   2                   3
//     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
//    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//    |0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 A B 0|
//    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//
//    The meaning of the flags is:
//
//    A: This is the "change IP" flag.  If true, it requests the server
//       to send the Binding Response with a different IP address than the
//       one the Binding Request was received on.
//
//    B: This is the "change port" flag.  If true, it requests the
//       server to send the Binding Response with a different port than the
//       one the Binding Request was received on.
class ChangeAddress extends StunAttributes {
  @override
  int type = StunAttributes.TYPE_CHANGE_ADDRESS;

  @override
  int length = 4;

  late bool flagChangeIp;

  late bool flagChangePort;

  ChangeAddress({this.flagChangeIp = false, this.flagChangePort = false});

  @override
  fromBuffer(BitBufferReader reader, int type, int length) {
    super.fromBuffer(reader, type, length);
    int flag = reader.readUint(binaryDigits: 32);
    flagChangeIp = (flag & 0x04) != 0;
    flagChangePort = (flag & 0x02) != 0;
  }

  @override
  Uint8List toBuffer() {
    BitBuffer bitBuffer = BitBuffer();
    BitBufferWriter writer = BitBufferWriter(bitBuffer);
    writer.writeUint(type, binaryDigits: 16);
    writer.writeUint(length, binaryDigits: 16);
    int flag = 0;
    if (flagChangeIp) {
      flag |= 0x04;
    }
    if (flagChangePort) {
      flag |= 0x02;
    }
    writer.writeUint(flag, binaryDigits: 32);
    return bitBuffer.toUint8List();
  }

  @override
  String toString() {
    return """
  ${typeDisplayName}:
    Attribute Type: ${typeDisplayName}
    Attribute Length: ${length}
    flagChangeIp: ${flagChangeIp}
    flagChangePort: ${flagChangePort}
  """;
  }
}

// 11.2.5 SOURCE-ADDRESS
//
//    The SOURCE-ADDRESS attribute is present in Binding Responses.  It
//    indicates the source IP address and port that the server is sending
//    the response from.  Its syntax is identical to that of MAPPED-
//    ADDRESS.
class SourceAddress extends AddressAttribute {
  @override
  int type = StunAttributes.TYPE_SOURCE_ADDRESS;
}

// 11.2.6 USERNAME
//
//    The USERNAME attribute is used for message integrity.  It serves as a
//    means to identify the shared secret used in the message integrity
//    check.  The USERNAME is always present in a Shared Secret Response,
//    along with the PASSWORD.  It is optionally present in a Binding
//    Request when message integrity is used.
//
//    The value of USERNAME is a variable length opaque value.  Its length
//    MUST be a multiple of 4 (measured in bytes) in order to guarantee
//    alignment of attributes on word boundaries.
class Username extends StunTextAttributes {
  @override
  int type = StunAttributes.TYPE_USERNAME;

  String get username => value;

  @override
  String toString() {
    return """
  ${typeDisplayName}:
    Attribute Type: ${typeDisplayName}
    Attribute Length: ${length}
    username: ${username}
  """;
  }
}

// 11.2.7 PASSWORD
//
//    The PASSWORD attribute is used in Shared Secret Responses.  It is
//    always present in a Shared Secret Response, along with the USERNAME.
//
//    The value of PASSWORD is a variable length value that is to be used
//    as a shared secret.  Its length MUST be a multiple of 4 (measured in
//    bytes) in order to guarantee alignment of attributes on word
//    boundaries.
class Password extends StunTextAttributes {
  @override
  int type = StunAttributes.TYPE_PASSWORD;

  String get password => value;

  @override
  String toString() {
    return """
  ${typeDisplayName}:
    Attribute Type: ${typeDisplayName}
    Attribute Length: ${length}
    password: ${password}
  """;
  }
}

// 11.2.8 MESSAGE-INTEGRITY
//
//    The MESSAGE-INTEGRITY attribute contains an HMAC-SHA1 [13] of the
//    STUN message.  It can be present in Binding Requests or Binding
//    Responses.  Since it uses the SHA1 hash, the HMAC will be 20 bytes.
//    The text used as input to HMAC is the STUN message, including the
//    header, up to and including the attribute preceding the MESSAGE-
//    INTEGRITY attribute. That text is then padded with zeroes so as to be
//    a multiple of 64 bytes.  As a result, the MESSAGE-INTEGRITY attribute
//    MUST be the last attribute in any STUN message.  The key used as
//    input to HMAC depends on the context.
class MessageIntegrity extends StunUInt8ListAttributes {
  @override
  int type = StunAttributes.TYPE_MESSAGE_INTEGRITY;

  List<int> get key => value;
}

// 11.2.9 ERROR-CODE
//
//    The ERROR-CODE attribute is present in the Binding Error Response and
//    Shared Secret Error Response.  It is a numeric value in the range of
//    100 to 699 plus a textual reason phrase encoded in UTF-8, and is
//    consistent in its code assignments and semantics with SIP [10] and
//    HTTP [15].  The reason phrase is meant for user consumption, and can
//    be anything appropriate for the response code.  The lengths of the
//    reason phrases MUST be a multiple of 4 (measured in bytes).  This can
//    be accomplished by added spaces to the end of the text, if necessary.
//    Recommended reason phrases for the defined response codes are
//    presented below.
//
//    To facilitate processing, the class of the error code (the hundreds
//    digit) is encoded separately from the rest of the code.
//
//      0                   1                   2                   3
//      0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
//     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//     |                   0                     |Class|     Number    |
//     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//     |      Reason Phrase (variable)                                ..
//     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//
//    The class represents the hundreds digit of the response code.  The
//    value MUST be between 1 and 6.  The number represents the response
//    code modulo 100, and its value MUST be between 0 and 99.
//
//    The following response codes, along with their recommended reason
//    phrases (in brackets) are defined at this time:
//
//    400 (Bad Request): The request was malformed.  The client should not
//         retry the request without modification from the previous
//         attempt.
//
//    401 (Unauthorized): The Binding Request did not contain a MESSAGE-
//         INTEGRITY attribute.
//
//    420 (Unknown Attribute): The server did not understand a mandatory
//         attribute in the request.
//
//    430 (Stale Credentials): The Binding Request did contain a MESSAGE-
//         INTEGRITY attribute, but it used a shared secret that has
//         expired.  The client should obtain a new shared secret and try
//         again.
//
//    431 (Integrity Check Failure): The Binding Request contained a
//         MESSAGE-INTEGRITY attribute, but the HMAC failed verification.
//         This could be a sign of a potential attack, or client
//         implementation error.
//
//    432 (Missing Username): The Binding Request contained a MESSAGE-
//         INTEGRITY attribute, but not a USERNAME attribute.  Both must be
//         present for integrity checks.
//
//    433 (Use TLS): The Shared Secret request has to be sent over TLS, but
//         was not received over TLS.
//
//    500 (Server Error): The server has suffered a temporary error. The
//         client should try again.
//
//    600 (Global Failure:) The server is refusing to fulfill the request.
//         The client should not retry.
//
class ErrorCode extends StunAttributes {
  @override
  int type = StunAttributes.TYPE_ERROR_CODE;

  @override
  late int length = reason.length + 8;

  late int head;
  late int code;
  late String reason;

  @override
  fromBuffer(BitBufferReader reader, int type, int length) {
    super.fromBuffer(reader, type, length);
    head = reader.readUint(binaryDigits: 21);
    int clz = reader.readUint(binaryDigits: 3);
    int number = reader.readUint(binaryDigits: 8);
    code = clz * 100 + number;
    int lenReason = length * 8 - 21 - 3 - 8;
    reason = reader.readUtf8String(lenReason,
        binaryDigits: 8, order: BitOrder.MSBFirst);
  }

  @override
  Uint8List toBuffer() {
    BitBuffer bitBuffer = BitBuffer();
    BitBufferWriter writer = BitBufferWriter(bitBuffer);
    writer.writeUint(type, binaryDigits: 16);
    writer.writeUint(length, binaryDigits: 16);

    int clz = code ~/ 100; // 提取百位（类）
    int number = code % 100; // 提取十位和个位（编号）

    writer.writeUint(head, binaryDigits: 21); // 写入21位head
    writer.writeUint(clz, binaryDigits: 3); // 写入3位clz
    writer.writeUint(number, binaryDigits: 8); // 写入8位number

    writer.writeUtf8String(reason,
        binaryDigits: 8, order: BitOrder.MSBFirst); // 写入reason

    return bitBuffer.toUint8List();
  }

  @override
  String toString() {
    return """
  ${typeDisplayName}:
    Attribute Type: ${typeDisplayName}
    Attribute Length: ${length}
    code: ${code}
    reason: ${reason}
  """;
  }
}

// 11.2.10 UNKNOWN-ATTRIBUTES
//
//    The UNKNOWN-ATTRIBUTES attribute is present only in a Binding Error
//    Response or Shared Secret Error Response when the response code in
//    the ERROR-CODE attribute is 420.
//
//    The attribute contains a list of 16 bit values, each of which
//    represents an attribute type that was not understood by the server.
//    If the number of unknown attributes is an odd number, one of the
//    attributes MUST be repeated in the list, so that the total length of
//    the list is a multiple of 4 bytes.
//
//    0                   1                   2                   3
//      0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
//     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//     |      Attribute 1 Type           |     Attribute 2 Type        |
//     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//     |      Attribute 3 Type           |     Attribute 4 Type    ...
//     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
class UnknownAttributes extends StunAttributes {
  @override
  int type = StunAttributes.TYPE_UNKNOWN_ATTRIBUTES;

  @override
  late int length = types.length * 2;

  late List<int> types;

  @override
  fromBuffer(BitBufferReader reader, int type, int length) {
    super.fromBuffer(reader, type, length);
    types = reader.readIntList(length * 8,
        binaryDigits: 16, order: BitOrder.MSBFirst);
  }

  @override
  Uint8List toBuffer() {
    BitBuffer bitBuffer = BitBuffer();
    BitBufferWriter writer = BitBufferWriter(bitBuffer);
    writer.writeUint(type, binaryDigits: 16);
    writer.writeUint(length, binaryDigits: 16);
    writer.writeUtf8String(utf8.decode(types),
        binaryDigits: 16, order: BitOrder.MSBFirst);
    return bitBuffer.toUint8List();
  }

  @override
  String toString() {
    return """
  ${typeDisplayName}:
    Attribute Type: ${typeDisplayName}
    Attribute Length: ${length}
    types: ${types}
  """;
  }
}

// 11.2.11 REFLECTED-FROM
//
//    The REFLECTED-FROM attribute is present only in Binding Responses,
//    when the Binding Request contained a RESPONSE-ADDRESS attribute.  The
//    attribute contains the identity (in terms of IP address) of the
//    source where the request came from.  Its purpose is to provide
//    traceability, so that a STUN server cannot be used as a reflector for
//    denial-of-service attacks.
//
//    Its syntax is identical to the MAPPED-ADDRESS attribute.
class ReflectedFrom extends AddressAttribute {
  @override
  int type = StunAttributes.TYPE_REFLECTED_FROM;
}
