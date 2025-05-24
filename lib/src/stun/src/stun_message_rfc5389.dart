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

import '../bits/bit_buffer.dart';
import 'stun_message_rfc3489.dart' as rfc3489;
import '../stun.dart';

// 15.  STUN Attributes
//
//    After the STUN header are zero or more attributes.  Each attribute
//    MUST be TLV encoded, with a 16-bit type, 16-bit length, and value.
//    Each STUN attribute MUST end on a 32-bit boundary.  As mentioned
//    above, all fields in an attribute are transmitted most significant
//    bit first.
//
//        0                   1                   2                   3
//        0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
//       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//       |         Type                  |            Length             |
//       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//       |                         Value (variable)                ....
//       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//
//                     Figure 4: Format of STUN Attributes
//
//
//
//
// Rosenberg, et al.           Standards Track                    [Page 31]
//
// RFC 5389                          STUN                      October 2008
//
//
//    The value in the length field MUST contain the length of the Value
//    part of the attribute, prior to padding, measured in bytes.  Since
//    STUN aligns attributes on 32-bit boundaries, attributes whose content
//    is not a multiple of 4 bytes are padded with 1, 2, or 3 bytes of
//    padding so that its value contains a multiple of 4 bytes.  The
//    padding bits are ignored, and may be any value.
//
//    Any attribute type MAY appear more than once in a STUN message.
//    Unless specified otherwise, the order of appearance is significant:
//    only the first occurrence needs to be processed by a receiver, and
//    any duplicates MAY be ignored by a receiver.
//
//    To allow future revisions of this specification to add new attributes
//    if needed, the attribute space is divided into two ranges.
//    Attributes with type values between 0x0000 and 0x7FFF are
//    comprehension-required attributes, which means that the STUN agent
//    cannot successfully process the message unless it understands the
//    attribute.  Attributes with type values between 0x8000 and 0xFFFF are
//    comprehension-optional attributes, which means that those attributes
//    can be ignored by the STUN agent if it does not understand them.
//
//    The set of STUN attribute types is maintained by IANA.  The initial
//    set defined by this specification is found in Section 18.2.
//
//    The rest of this section describes the format of the various
//    attributes defined in this specification.

// 18.2.  STUN Attribute Registry
//
//    A STUN Attribute type is a hex number in the range 0x0000 - 0xFFFF.
//    STUN attribute types in the range 0x0000 - 0x7FFF are considered
//    comprehension-required; STUN attribute types in the range 0x8000 -
//    0xFFFF are considered comprehension-optional.  A STUN agent handles
//    unknown comprehension-required and comprehension-optional attributes
//    differently.
//
//    The initial STUN Attributes types are:
//
//
//
// Rosenberg, et al.           Standards Track                    [Page 43]
//
// RFC 5389                          STUN                      October 2008
//
//
//    Comprehension-required range (0x0000-0x7FFF):
//      0x0000: (Reserved)
//      0x0001: MAPPED-ADDRESS
//      0x0002: (Reserved; was RESPONSE-ADDRESS)
//      0x0003: (Reserved; was CHANGE-ADDRESS)
//      0x0004: (Reserved; was SOURCE-ADDRESS)
//      0x0005: (Reserved; was CHANGED-ADDRESS)
//      0x0006: USERNAME
//      0x0007: (Reserved; was PASSWORD)
//      0x0008: MESSAGE-INTEGRITY
//      0x0009: ERROR-CODE
//      0x000A: UNKNOWN-ATTRIBUTES
//      0x000B: (Reserved; was REFLECTED-FROM)
//      0x0014: REALM
//      0x0015: NONCE
//      0x0020: XOR-MAPPED-ADDRESS
//
//    Comprehension-optional range (0x8000-0xFFFF)
//      0x8022: SOFTWARE
//      0x8023: ALTERNATE-SERVER
//      0x8028: FINGERPRINT
//
//    STUN Attribute types in the first half of the comprehension-required
//    range (0x0000 - 0x3FFF) and in the first half of the comprehension-
//    optional range (0x8000 - 0xBFFF) are assigned by IETF Review
//    [RFC5226].  STUN Attribute types in the second half of the
//    comprehension-required range (0x4000 - 0x7FFF) and in the second half
//    of the comprehension-optional range (0xC000 - 0xFFFF) are assigned by
//    Designated Expert [RFC5226].  The responsibility of the expert is to
//    verify that the selected codepoint(s) are not in use, and that the
//    request is not for an abnormally large number of codepoints.
//    Technical review of the extension itself is outside the scope of the
//    designated expert responsibility.
//
// 18.3.  STUN Error Code Registry
//
//    A STUN error code is a number in the range 0 - 699.  STUN error codes
//    are accompanied by a textual reason phrase in UTF-8 [RFC3629] that is
//    intended only for human consumption and can be anything appropriate;
//    this document proposes only suggested values.
//
//    STUN error codes are consistent in codepoint assignments and
//    semantics with SIP [RFC3261] and HTTP [RFC2616].
//
//    The initial values in this registry are given in Section 15.6.
//
//
//
//
//
//
// Rosenberg, et al.           Standards Track                    [Page 44]
//
// RFC 5389                          STUN                      October 2008
//
//
//    New STUN error codes are assigned based on IETF Review [RFC5226].
//    The specification must carefully consider how clients that do not
//    understand this error code will process it before granting the
//    request.  See the rules in Section 7.3.4.

var types = {
  StunAttributes.TYPE_MAPPED_ADDRESS: () => MappedAddressAttribute(),
  StunAttributes.TYPE_USERNAME: () => Username(),
  StunAttributes.TYPE_MESSAGE_INTEGRITY: () => MessageIntegrity(),
  StunAttributes.TYPE_ERROR_CODE: () => ErrorCode(),
  StunAttributes.TYPE_UNKNOWN_ATTRIBUTES: () => UnknownAttributes(),
  StunAttributes.TYPE_REALM: () => Realm(),
  StunAttributes.TYPE_NONCE: () => Nonce(),
  StunAttributes.TYPE_XOR_MAPPED_ADDRESS: () => XorMappedAddressAttribute(),
  StunAttributes.TYPE_SOFTWARE: () => Software(),
  StunAttributes.TYPE_ALTERNATE_SERVER: () => AlternateServer(),
  StunAttributes.TYPE_FINGERPRINT: () => Fingerprint(),
};

StunAttributes? resolveAttribute(BitBufferReader reader, int type, int length) {
  var creator = types[type];
  if (creator == null) return null;
  StunAttributes attribute = creator();
  attribute.fromBuffer(reader, type, length);
  return attribute;
}

//15.1.  MAPPED-ADDRESS
//
//    The MAPPED-ADDRESS attribute indicates a reflexive transport address
//    of the client.  It consists of an 8-bit address family and a 16-bit
//    port, followed by a fixed-length value representing the IP address.
//    If the address family is IPv4, the address MUST be 32 bits.  If the
//    address family is IPv6, the address MUST be 128 bits.  All fields
//    must be in network byte order.

//    The format of the MAPPED-ADDRESS attribute is:
//
//        0                   1                   2                   3
//        0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
//       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//       |0 0 0 0 0 0 0 0|    Family     |           Port                |
//       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//       |                                                               |
//       |                 Address (32 bits or 128 bits)                 |
//       |                                                               |
//       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//
//                Figure 5: Format of MAPPED-ADDRESS Attribute
//
//    The address family can take on the following values:
//
//    0x01:IPv4
//    0x02:IPv6
//
//    The first 8 bits of the MAPPED-ADDRESS MUST be set to 0 and MUST be
//    ignored by receivers.  These bits are present for aligning parameters
//    on natural 32-bit boundaries.
//
//    This attribute is used only by servers for achieving backwards
//    compatibility with RFC 3489 [RFC3489] clients.
typedef MappedAddressAttribute = rfc3489.MappedAddressAttribute;

//15.2.  XOR-MAPPED-ADDRESS
//
//    The XOR-MAPPED-ADDRESS attribute is identical to the MAPPED-ADDRESS
//    attribute, except that the reflexive transport address is obfuscated
//    through the XOR function.
//
//    The format of the XOR-MAPPED-ADDRESS is:
//
//       0                   1                   2                   3
//       0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
//      +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//      |x x x x x x x x|    Family     |         X-Port                |
//      +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//      |                X-Address (Variable)
//      +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//
//              Figure 6: Format of XOR-MAPPED-ADDRESS Attribute
//
//    The Family represents the IP address family, and is encoded
//    identically to the Family in MAPPED-ADDRESS.
//
//    X-Port is computed by taking the mapped port in host byte order,
//    XOR'ing it with the most significant 16 bits of the magic cookie, and
//    then the converting the result to network byte order.  If the IP
//    address family is IPv4, X-Address is computed by taking the mapped IP
//    address in host byte order, XOR'ing it with the magic cookie, and
//    converting the result to network byte order.  If the IP address
//    family is IPv6, X-Address is computed by taking the mapped IP address
//    in host byte order, XOR'ing it with the concatenation of the magic
//    cookie and the 96-bit transaction ID, and converting the result to
//    network byte order.
//
//    The rules for encoding and processing the first 8 bits of the
//    attribute's value, the rules for handling multiple occurrences of the
//    attribute, and the rules for processing address families are the same
//    as for MAPPED-ADDRESS.
//
//    Note: XOR-MAPPED-ADDRESS and MAPPED-ADDRESS differ only in their
//    encoding of the transport address.  The former encodes the transport
//    address by exclusive-or'ing it with the magic cookie.  The latter
//    encodes it directly in binary.  RFC 3489 originally specified only
//    MAPPED-ADDRESS.  However, deployment experience found that some NATs
//    rewrite the 32-bit binary payloads containing the NAT's public IP
//    address, such as STUN's MAPPED-ADDRESS attribute, in the well-meaning
//    but misguided attempt at providing a generic ALG function.  Such
//    behavior interferes with the operation of STUN and also causes
//    failure of STUN's message-integrity checking.
class XorMappedAddressAttribute extends AddressAttribute {
  @override
  int type = StunAttributes.TYPE_XOR_MAPPED_ADDRESS;
}

// 15.3.  USERNAME
//
//    The USERNAME attribute is used for message integrity.  It identifies
//    the username and password combination used in the message-integrity
//    check.
//
//    The value of USERNAME is a variable-length value.  It MUST contain a
//    UTF-8 [RFC3629] encoded sequence of less than 513 bytes, and MUST
//    have been processed using SASLprep [RFC4013].
typedef Username = rfc3489.Username;

// 15.4.  MESSAGE-INTEGRITY
//
//    The MESSAGE-INTEGRITY attribute contains an HMAC-SHA1 [RFC2104] of
//    the STUN message.  The MESSAGE-INTEGRITY attribute can be present in
//    any STUN message type.  Since it uses the SHA1 hash, the HMAC will be
//    20 bytes.  The text used as input to HMAC is the STUN message,
//    including the header, up to and including the attribute preceding the
//    MESSAGE-INTEGRITY attribute.  With the exception of the FINGERPRINT
//    attribute, which appears after MESSAGE-INTEGRITY, agents MUST ignore
//    all other attributes that follow MESSAGE-INTEGRITY.
//
//
//
//
// Rosenberg, et al.           Standards Track                    [Page 34]
//
// RFC 5389                          STUN                      October 2008
//
//
//    The key for the HMAC depends on whether long-term or short-term
//    credentials are in use.  For long-term credentials, the key is 16
//    bytes:
//
//             key = MD5(username ":" realm ":" SASLprep(password))
//
//    That is, the 16-byte key is formed by taking the MD5 hash of the
//    result of concatenating the following five fields: (1) the username,
//    with any quotes and trailing nulls removed, as taken from the
//    USERNAME attribute (in which case SASLprep has already been applied);
//    (2) a single colon; (3) the realm, with any quotes and trailing nulls
//    removed; (4) a single colon; and (5) the password, with any trailing
//    nulls removed and after processing using SASLprep.  For example, if
//    the username was 'user', the realm was 'realm', and the password was
//    'pass', then the 16-byte HMAC key would be the result of performing
//    an MD5 hash on the string 'user:realm:pass', the resulting hash being
//    0x8493fbc53ba582fb4c044c456bdc40eb.
//
//    For short-term credentials:
//
//                           key = SASLprep(password)
//
//    where MD5 is defined in RFC 1321 [RFC1321] and SASLprep() is defined
//    in RFC 4013 [RFC4013].
//
//    The structure of the key when used with long-term credentials
//    facilitates deployment in systems that also utilize SIP.  Typically,
//    SIP systems utilizing SIP's digest authentication mechanism do not
//    actually store the password in the database.  Rather, they store a
//    value called H(A1), which is equal to the key defined above.
//
//    Based on the rules above, the hash used to construct MESSAGE-
//    INTEGRITY includes the length field from the STUN message header.
//    Prior to performing the hash, the MESSAGE-INTEGRITY attribute MUST be
//    inserted into the message (with dummy content).  The length MUST then
//    be set to point to the length of the message up to, and including,
//    the MESSAGE-INTEGRITY attribute itself, but excluding any attributes
//    after it.  Once the computation is performed, the value of the
//    MESSAGE-INTEGRITY attribute can be filled in, and the value of the
//    length in the STUN header can be set to its correct value -- the
//    length of the entire message.  Similarly, when validating the
//    MESSAGE-INTEGRITY, the length field should be adjusted to point to
//    the end of the MESSAGE-INTEGRITY attribute prior to calculating the
//    HMAC.  Such adjustment is necessary when attributes, such as
//    FINGERPRINT, appear after MESSAGE-INTEGRITY.

typedef MessageIntegrity = rfc3489.MessageIntegrity;

// 15.5.  FINGERPRINT
//
//    The FINGERPRINT attribute MAY be present in all STUN messages.  The
//    value of the attribute is computed as the CRC-32 of the STUN message
//    up to (but excluding) the FINGERPRINT attribute itself, XOR'ed with
//    the 32-bit value 0x5354554e (the XOR helps in cases where an
//    application packet is also using CRC-32 in it).  The 32-bit CRC is
//    the one defined in ITU V.42 [ITU.V42.2002], which has a generator
//    polynomial of x32+x26+x23+x22+x16+x12+x11+x10+x8+x7+x5+x4+x2+x+1.
//    When present, the FINGERPRINT attribute MUST be the last attribute in
//    the message, and thus will appear after MESSAGE-INTEGRITY.
//
//    The FINGERPRINT attribute can aid in distinguishing STUN packets from
//    packets of other protocols.  See Section 8.
//
//    As with MESSAGE-INTEGRITY, the CRC used in the FINGERPRINT attribute
//    covers the length field from the STUN message header.  Therefore,
//    this value must be correct and include the CRC attribute as part of
//    the message length, prior to computation of the CRC.  When using the
//    FINGERPRINT attribute in a message, the attribute is first placed
//    into the message with a dummy value, then the CRC is computed, and
//    then the value of the attribute is updated.  If the MESSAGE-INTEGRITY
//    attribute is also present, then it must be present with the correct
//    message-integrity value before the CRC is computed, since the CRC is
//    done over the value of the MESSAGE-INTEGRITY attribute as well.
class Fingerprint extends StunUInt8ListAttributes {
  @override
  int type = StunAttributes.TYPE_FINGERPRINT;

  List<int> get fingerprint => value;
}

// 15.6.  ERROR-CODE
//
//    The ERROR-CODE attribute is used in error response messages.  It
//    contains a numeric error code value in the range of 300 to 699 plus a
//    textual reason phrase encoded in UTF-8 [RFC3629], and is consistent
//    in its code assignments and semantics with SIP [RFC3261] and HTTP
//    [RFC2616].  The reason phrase is meant for user consumption, and can
//    be anything appropriate for the error code.  Recommended reason
//    phrases for the defined error codes are included in the IANA registry
//    for error codes.  The reason phrase MUST be a UTF-8 [RFC3629] encoded
//    sequence of less than 128 characters (which can be as long as 763
//    bytes).
//
//        0                   1                   2                   3
//        0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
//       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//       |           Reserved, should be 0         |Class|     Number    |
//       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//       |      Reason Phrase (variable)                                ..
//       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//
//                       Figure 7: ERROR-CODE Attribute
//
//
//
// Rosenberg, et al.           Standards Track                    [Page 36]
//
// RFC 5389                          STUN                      October 2008
//
//
//    To facilitate processing, the class of the error code (the hundreds
//    digit) is encoded separately from the rest of the code, as shown in
//    Figure 7.
//
//    The Reserved bits SHOULD be 0, and are for alignment on 32-bit
//    boundaries.  Receivers MUST ignore these bits.  The Class represents
//    the hundreds digit of the error code.  The value MUST be between 3
//    and 6.  The Number represents the error code modulo 100, and its
//    value MUST be between 0 and 99.
//
//    The following error codes, along with their recommended reason
//    phrases, are defined:
//
//    300  Try Alternate: The client should contact an alternate server for
//         this request.  This error response MUST only be sent if the
//         request included a USERNAME attribute and a valid MESSAGE-
//         INTEGRITY attribute; otherwise, it MUST NOT be sent and error
//         code 400 (Bad Request) is suggested.  This error response MUST
//         be protected with the MESSAGE-INTEGRITY attribute, and receivers
//         MUST validate the MESSAGE-INTEGRITY of this response before
//         redirecting themselves to an alternate server.
//
//              Note: Failure to generate and validate message integrity
//              for a 300 response allows an on-path attacker to falsify a
//              300 response thus causing subsequent STUN messages to be
//              sent to a victim.
//
//    400  Bad Request: The request was malformed.  The client SHOULD NOT
//         retry the request without modification from the previous
//         attempt.  The server may not be able to generate a valid
//         MESSAGE-INTEGRITY for this error, so the client MUST NOT expect
//         a valid MESSAGE-INTEGRITY attribute on this response.
//
//    401  Unauthorized: The request did not contain the correct
//         credentials to proceed.  The client should retry the request
//         with proper credentials.
//
//    420  Unknown Attribute: The server received a STUN packet containing
//         a comprehension-required attribute that it did not understand.
//         The server MUST put this unknown attribute in the UNKNOWN-
//         ATTRIBUTE attribute of its error response.
//
//    438  Stale Nonce: The NONCE used by the client was no longer valid.
//         The client should retry, using the NONCE provided in the
//         response.
//
//    500  Server Error: The server has suffered a temporary error.  The
//         client should try again.
//
//
//
// Rosenberg, et al.           Standards Track                    [Page 37]
//
// RFC 5389                          STUN                      October 2008
typedef ErrorCode = rfc3489.ErrorCode;

// 15.7.  REALM
//
//    The REALM attribute may be present in requests and responses.  It
//    contains text that meets the grammar for "realm-value" as described
//    in RFC 3261 [RFC3261] but without the double quotes and their
//    surrounding whitespace.  That is, it is an unquoted realm-value (and
//    is therefore a sequence of qdtext or quoted-pair).  It MUST be a
//    UTF-8 [RFC3629] encoded sequence of less than 128 characters (which
//    can be as long as 763 bytes), and MUST have been processed using
//    SASLprep [RFC4013].
//
//    Presence of the REALM attribute in a request indicates that long-term
//    credentials are being used for authentication.  Presence in certain
//    error responses indicates that the server wishes the client to use a
//    long-term credential for authentication.
class Realm extends StunTextAttributes {
  @override
  int type = StunAttributes.TYPE_REALM;

  String get realm => value;

  @override
  String toString() {
    return """
  ${typeDisplayName}:
    Attribute Type: ${typeDisplayName}
    Attribute Length: ${length}
    realm: ${realm}
  """;
  }
}

// 15.8.  NONCE
//
//    The NONCE attribute may be present in requests and responses.  It
//    contains a sequence of qdtext or quoted-pair, which are defined in
//    RFC 3261 [RFC3261].  Note that this means that the NONCE attribute
//    will not contain actual quote characters.  See RFC 2617 [RFC2617],
//    Section 4.3, for guidance on selection of nonce values in a server.
//
//    It MUST be less than 128 characters (which can be as long as 763
//    bytes).
class Nonce extends StunTextAttributes {
  @override
  int type = StunAttributes.TYPE_NONCE;

  String get nonce => value;

  @override
  String toString() {
    return """
  ${typeDisplayName}:
    Attribute Type: ${typeDisplayName}
    Attribute Length: ${length}
    nonce: ${nonce}
  """;
  }
}

// 15.9.  UNKNOWN-ATTRIBUTES
//
//    The UNKNOWN-ATTRIBUTES attribute is present only in an error response
//    when the response code in the ERROR-CODE attribute is 420.
//
//    The attribute contains a list of 16-bit values, each of which
//    represents an attribute type that was not understood by the server.
//
//        0                   1                   2                   3
//        0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
//       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//       |      Attribute 1 Type           |     Attribute 2 Type        |
//       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//       |      Attribute 3 Type           |     Attribute 4 Type    ...
//       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//
//
//              Figure 8: Format of UNKNOWN-ATTRIBUTES Attribute
//
//
//       Note: In [RFC3489], this field was padded to 32 by duplicating the
//       last attribute.  In this version of the specification, the normal
//       padding rules for attributes are used instead.
typedef UnknownAttributes = rfc3489.UnknownAttributes;

// 15.10.  SOFTWARE
//
//    The SOFTWARE attribute contains a textual description of the software
//    being used by the agent sending the message.  It is used by clients
//    and servers.  Its value SHOULD include manufacturer and version
//    number.  The attribute has no impact on operation of the protocol,
//    and serves only as a tool for diagnostic and debugging purposes.  The
//    value of SOFTWARE is variable length.  It MUST be a UTF-8 [RFC3629]
//    encoded sequence of less than 128 characters (which can be as long as
//    763 bytes).
class Software extends StunTextAttributes {
  @override
  int type = StunAttributes.TYPE_SOFTWARE;

  String get description => value;

  @override
  String toString() {
    return """
  ${typeDisplayName}:
    Attribute Type: ${typeDisplayName}
    Attribute Length: ${length}
    description: ${description}
  """;
  }
}

// 15.11.  ALTERNATE-SERVER
//
//    The alternate server represents an alternate transport address
//    identifying a different STUN server that the STUN client should try.
//
//    It is encoded in the same way as MAPPED-ADDRESS, and thus refers to a
//    single server by IP address.  The IP address family MUST be identical
//    to that of the source IP address of the request.
class AlternateServer extends AddressAttribute {
  @override
  int type = StunAttributes.TYPE_ALTERNATE_SERVER;
}
