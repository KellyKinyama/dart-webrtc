import 'dart:typed_data';
import 'dart:io'; // For InternetAddress

import 'stun_message.dart';
import 'stun_message_rfc5389.dart'; // Assuming XorMappedAddressAttribute is here

StunMessage constructBindingSuccessResponse(
    List<int> receivedTransactionId,
    InternetAddress clientAddress,
    int clientPort) {
  // 1. Header
  final messageType = 0x0101; // Binding Response
  final magicCookie = 0x2112A442;

  // 2. XOR-MAPPED-ADDRESS Attribute
  final xorMappedAddress = XorMappedAddressAttribute();
  xorMappedAddress.family = clientAddress.type == InternetAddressType.IPv4
      ? 0x01
      : 0x02; // IPv4 or IPv6
  xorMappedAddress.port = clientPort;
  xorMappedAddress.address = clientAddress.rawAddress; // The IP address bytes
  xorMappedAddress.transactionId = receivedTransactionId; // Important for XORing
  xorMappedAddress.magicCookie = magicCookie;
  xorMappedAddress.encodeValue(); // Perform the XOR operation
  final xorMappedAddressBytes = xorMappedAddress.toBuffer();

  // 3. Calculate Total Attributes Length (including padding)
  int attributesLength = xorMappedAddressBytes.lengthInBytes - 4; // Subtracting type and length
  if (attributesLength % 4 != 0) {
    attributesLength += 4 - (attributesLength % 4); // Add padding
  }

  final header = StunHeader(
    messageType: messageType,
    messageLengthFromHeader: attributesLength,
    magicCookie: magicCookie,
    transactionId: receivedTransactionId,
  );

  final attributes = <StunAttribute>[
    xorMappedAddress,
  ];

  return StunMessage(header: header, attributes: attributes);
}