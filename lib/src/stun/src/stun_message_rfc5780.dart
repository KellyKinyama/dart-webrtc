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

import 'dart:typed_data';

import '../bits/bit_buffer.dart';
import '../stun.dart';

// 7.  New Attributes
//
//    This document defines several STUN attributes that are required for
//    NAT Behavior Discovery.  These attributes are all used only with
//    Binding Requests and Binding Responses.  CHANGE-REQUEST was
//    originally defined in RFC 3489 [RFC3489] but is redefined here as
//    that document is obsoleted by [RFC5389].
//
//      Comprehension-required range (0x0000-0x7FFF):
//        0x0003: CHANGE-REQUEST
//        0x0026: PADDING
//        0x0027: RESPONSE-PORT
//
//      Comprehension-optional range (0x8000-0xFFFF):
//        0x802b: RESPONSE-ORIGIN
//        0x802c: OTHER-ADDRESS

var types = {
  StunAttributes.TYPE_CHANGE_REQUEST: () => ChangeRequest(),
  StunAttributes.TYPE_PADDING: () => Padding(),
  StunAttributes.TYPE_RESPONSE_PORT: () => ResponsePort(),
  StunAttributes.TYPE_RESPONSE_ORIGIN: () => ResponseOrigin(),
  StunAttributes.TYPE_OTHER_ADDRESS: () => OtherAddress(),
};

StunAttributes? resolveAttribute(BitBufferReader reader, int type, int length) {
  var creator = types[type];
  if (creator == null) return null;
  StunAttributes attribute = creator();
  attribute.fromBuffer(reader, type, length);
  return attribute;
}

// 7.2.  CHANGE-REQUEST
//
//    The CHANGE-REQUEST attribute contains two flags to control the IP
//    address and port that the server uses to send the response.  These
//    flags are called the "change IP" and "change port" flags.  The
//    CHANGE-REQUEST attribute is allowed only in the Binding Request.  The
//    "change IP" and "change port" flags are useful for determining the
//    current filtering behavior of a NAT.  They instruct the server to
//    send the Binding Responses from the alternate source IP address
//    and/or alternate port.  The CHANGE-REQUEST attribute is optional in
//    the Binding Request.
//
//    The attribute is 32 bits long, although only two bits (A and B) are
//    used:
//
//     0                   1                   2                   3
//     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
//    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//    |0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 A B 0|
//    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//
//    The meanings of the flags are:
//
//    A: This is the "change IP" flag.  If true, it requests the server to
//       send the Binding Response with a different IP address than the one
//       the Binding Request was received on.
//
//    B: This is the "change port" flag.  If true, it requests the server
//       to send the Binding Response with a different port than the one
//       the Binding Request was received on.
class ChangeRequest extends AddressAttribute {
  @override
  int type = StunAttributes.TYPE_CHANGE_REQUEST;
}

// 7.3.  RESPONSE-ORIGIN
//
//    The RESPONSE-ORIGIN attribute is inserted by the server and indicates
//    the source IP address and port the response was sent from.  It is
//    useful for detecting double NAT configurations.  It is only present
//    in Binding Responses.
class ResponseOrigin extends AddressAttribute {
  @override
  int type = StunAttributes.TYPE_RESPONSE_ORIGIN;
}

// 7.4.  OTHER-ADDRESS
//
//    The OTHER-ADDRESS attribute is used in Binding Responses.  It informs
//    the client of the source IP address and port that would be used if
//    the client requested the "change IP" and "change port" behavior.
//    OTHER-ADDRESS MUST NOT be inserted into a Binding Response unless the
//    server has a second IP address.
//
//    OTHER-ADDRESS uses the same attribute number as CHANGED-ADDRESS from
//    RFC 3489 [RFC3489] because it is simply a new name with the same
//    semantics as CHANGED-ADDRESS.  It has been renamed to more clearly
//    indicate its function.
class OtherAddress extends AddressAttribute {
  @override
  int type = StunAttributes.TYPE_OTHER_ADDRESS;
}

// 7.5.  RESPONSE-PORT
//
//    The RESPONSE-PORT attribute contains a port.  The RESPONSE-PORT
//    attribute can be present in the Binding Request and indicates which
//    port the Binding Response will be sent to.  For servers which support
//    the RESPONSE-PORT attribute, the Binding Response MUST be transmitted
//    to the source IP address of the Binding Request and the port
//    contained in RESPONSE-PORT.  It is used in tests such as Section 4.6.
//    When not present, the server sends the Binding Response to the source
//    IP address and port of the Binding Request.  The server MUST NOT
//    process a request containing a RESPONSE-PORT and a PADDING attribute.
//    The RESPONSE-PORT attribute is optional in the Binding Request.
//    Server support for RESPONSE-PORT is optional.
//
//    RESPONSE-PORT is a 16-bit unsigned integer in network byte order
//    followed by 2 bytes of padding.  Allowable values of RESPONSE-PORT
//    are 0-65536.
class ResponsePort extends StunAttributes {
  @override
  int type = StunAttributes.TYPE_RESPONSE_PORT;

  @override
  int length = 0;

  late int port;

  @override
  fromBuffer(BitBufferReader reader, int type, int length) {
    super.fromBuffer(reader, type, length);
    port = reader.readUint(binaryDigits: 16);
    int _ = reader.readUint(binaryDigits: 2 * 8); //todo
  }

  @override
  Uint8List toBuffer() {
    BitBuffer bitBuffer = BitBuffer();
    BitBufferWriter writer = BitBufferWriter(bitBuffer);
    writer.writeUint(type, binaryDigits: 16);
    writer.writeUint(length, binaryDigits: 16);
    writer.writeUint(port, binaryDigits: 16);
    writer.writeUint(0x00, binaryDigits: 2 * 8);
    return bitBuffer.toUint8List();
  }

  @override
  String toString() {
    return """
  ${typeDisplayName}:
    Attribute Type: ${typeDisplayName}
    Attribute Length: ${length}
    port: ${port}
  """;
  }
}

// 7.6.  PADDING
//
//    The PADDING attribute allows for the entire message to be padded to
//    force the STUN message to be divided into IP fragments.  PADDING
//    consists entirely of a free-form string, the value of which does not
//    matter.  PADDING can be used in either Binding Requests or Binding
//    Responses.
//
//    PADDING MUST NOT be longer than the length that brings the total IP
//    datagram size to 64K.  It SHOULD be equal in length to the MTU of the
//    outgoing interface, rounded up to an even multiple of four bytes.
//    Because STUN messages with PADDING are intended to test the behavior
//    of UDP fragments, they are an exception to the usual rule that STUN
//    messages be less than the MTU of the path.
class Padding extends StunAttributes {
  @override
  int type = StunAttributes.TYPE_PADDING;

  @override
  int length = 0;

  @override
  fromBuffer(BitBufferReader reader, int type, int length) {
    super.fromBuffer(reader, type, length);
    reader.readIntList(length * 8, binaryDigits: 8, order: BitOrder.MSBFirst);
  }

  @override
  Uint8List toBuffer() {
    BitBuffer bitBuffer = BitBuffer();
    BitBufferWriter writer = BitBufferWriter(bitBuffer);
    writer.writeUint(type, binaryDigits: 16);
    writer.writeUint(length, binaryDigits: 16);
    writer.writeIntList(List.filled(length, 0),
        binaryDigits: 8, order: BitOrder.MSBFirst);
    return bitBuffer.toUint8List();
  }

  @override
  String toString() {
    return """
  ${typeDisplayName}:
    Attribute Type: ${typeDisplayName}
    Attribute Length: ${length}
  """;
  }
}
