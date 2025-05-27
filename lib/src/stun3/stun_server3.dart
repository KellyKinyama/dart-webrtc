import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart'; // For HMAC-SHA1
import 'dart:convert'; // For utf8 encoding

// --- STUN Attribute Type Constants ---
const int stunAttrXorMappedAddress = 0x0020;
const int stunAttrMappedAddress = 0x0001; // Added for parsing client requests
const int stunAttrSoftware = 0x8022;
const int stunAttrMessageIntegrity = 0x0008;
const int stunAttrFingerprint = 0x8028;
const int stunAttrErrorCode = 0x0009; // Common error attribute

// --- STUN Message Type Constants ---
const int stunBindingRequest = 0x0001;
const int stunBindingResponse = 0x0101;
const int stunBindingErrorResponse = 0x0111;

// --- STUN Magic Cookie ---
const int stunMagicCookie = 0x2112A442;
// This is the XOR_MAGIC_COOKIE defined in RFC 5389 Section 15.5 for FINGERPRINT
const int stunFingerprintXorMagicCookie = 0x5354554E;

// --- Shared secret for MESSAGE-INTEGRITY (for demonstration purposes) ---
// In a real application, this would be dynamically retrieved based on user credentials or session.
// Make sure this is a strong, securely managed key.
final Uint8List sharedSecret =
    Uint8List.fromList(utf8.encode('super_secret_stun_key_1234567890'));

// --- Custom CRC32 Implementation ---
// Based on IEEE 802.3 polynomial 0x04C11DB7 (reversed: 0xEDB88320)
// This is a bit-by-bit implementation for simplicity and no external deps.
// For performance with very large data, a lookup table is usually preferred.
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
/// It uses the standard CRC32 algorithm and then XORs the result with
/// STUN's FINGERPRINT_XOR_MAGIC_COOKIE (0x5354554E).
int calculateStunFingerprintCrc32(Uint8List bytes) {
  return _calculateRawCrc32(bytes) ^ stunFingerprintXorMagicCookie;
}

/// Calculates HMAC-SHA1 for the given bytes and key.
Uint8List calculateHmacSha1(Uint8List bytes, Uint8List key) {
  final hmac = Hmac(sha1, key);
  return Uint8List.fromList(hmac.convert(bytes).bytes);
}

// --- Main STUN Server Logic ---

Future<void> startStunServer(int port) async {
  final RawDatagramSocket socket =
      await RawDatagramSocket.bind(InternetAddress("10.100.53.194"), port);
  print(
      'STUN server listening on UDP port ${socket.address.address}:${socket.port}');

  // Listen for incoming datagrams
  await for (RawSocketEvent event in socket) {
    if (event == RawSocketEvent.read) {
      Datagram? datagram = socket.receive();
      if (datagram != null) {
        // Corrected print statement to show sender info
        print('Received packet data ${datagram.data}');
        handleStunRequest(socket, datagram);
      }
    }
  }
}

Future<void> startStunClient() async {
  final RawDatagramSocket socket =
      await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  print(
      'STUN client listening on UDP port ${socket.address.address}:${socket.port}');

  print("Sending data to stun server");
  // Example request bytes for testing (can be replaced by a proper client request)
  final Uint8List request = Uint8List.fromList([
    0, 1, 0, 76, 33, 18, 164, 66, 57, 68, 90, 114, 106, 76, 79, 109, 88, 103,
    71, 121,
    0, 6, 0, 9, 121, 120, 89, 98, 58, 77, 72, 99, 82, 0, 0,
    0, // MAPPED-ADDRESS (9 bytes + 3 padding)
    192, 87, 0, 4, 0, 1, 0, 10, // UNKNOWN-ATTRIBUTE (c057)
    128, 41, 0, 8, 80, 149, 75, 177, 64, 136, 87, 10, 0, 36, 0,
    4, // UNKNOWN-ATTRIBUTE (8029)
    110, 127, 30, 255, // Value for previous unknown
    0, 8, 0, 20, // MESSAGE-INTEGRITY (Type 0x0008, Length 20)
    128, 203, 15, 157, 255, 124, 86, 252, 111, 243, 99, 180, 89, 188, 45, 219,
    237, 240, 132, 97, // HMAC-SHA1 value
    128, 40, 0, 4, // FINGERPRINT (Type 0x8028, Length 4)
    237, 169, 72, 148 // CRC32 value
  ]);

  socket.send(request, InternetAddress("10.100.53.194"), 4444);
  print("Sent STUN Binding Request to 10.100.53.194:4444");

  // Listen for incoming datagrams
  await for (RawSocketEvent event in socket) {
    if (event == RawSocketEvent.read) {
      Datagram? datagram = socket.receive();
      if (datagram != null) {
        print(
            'Received response from ${datagram.address.address}:${datagram.port} with size ${datagram.data.length} bytes');
        // You would typically parse the response here to check the XOR-MAPPED-ADDRESS
        // For now, just print the raw bytes.
        print('Response bytes: ${datagram.data}');
      }
    }
  }
}

void handleStunRequest(RawDatagramSocket socket, Datagram datagram) {
  final Uint8List requestBytes = datagram.data;
  final InternetAddress clientAddress = datagram.address;
  final int clientPort = datagram.port;

  // Basic validation: A STUN message must be at least 20 bytes (header size)
  if (requestBytes.length < 20) {
    print(
        'Received malformed packet from $clientAddress:$clientPort (too short: ${requestBytes.length} bytes)');
    return; // Or send an error response (e.g., 400 Bad Request)
  }

  final ByteData requestData = ByteData.view(requestBytes.buffer);
  final int messageType = requestData.getUint16(0); // Bytes 0-1
  final int messageLength = requestData.getUint16(2); // Bytes 2-3
  final int magicCookie = requestData.getUint32(4); // Bytes 4-7
  final Uint8List transactionId = requestBytes.sublist(8, 20); // Bytes 8-19

  // Validate Magic Cookie: Must be 0x2112A442
  if (magicCookie != stunMagicCookie) {
    print(
        'Received packet with invalid Magic Cookie (${magicCookie.toRadixString(16)}) from $clientAddress:$clientPort');
    // Send an error response (e.g., 400 Bad Request) as per RFC 5389 Section 7.1
    _sendStunErrorResponse(socket, clientAddress, clientPort, transactionId,
        400, 'Bad Request - Invalid Magic Cookie');
    return;
  }

  // Validate total message length against header's message length
  if (requestBytes.length != (20 + messageLength)) {
    print(
        'Received packet with invalid length. Header says $messageLength, actual is ${requestBytes.length - 20} from $clientAddress:$clientPort');
    // Send an error response (e.g., 400 Bad Request)
    _sendStunErrorResponse(socket, clientAddress, clientPort, transactionId,
        400, 'Bad Request - Length Mismatch');
    return;
  }

  // Only handle STUN Binding Requests for this implementation
  if (messageType != stunBindingRequest) {
    print(
        'Received non-Binding Request (type: ${messageType.toRadixString(16)}) from $clientAddress:$clientPort');
    // Send an error response indicating unsupported message type (e.g., 400 Bad Request)
    _sendStunErrorResponse(socket, clientAddress, clientPort, transactionId,
        400, 'Bad Request - Unsupported Message Type');
    return;
  }

  print(
      'Received STUN Binding Request from $clientAddress:$clientPort, Transaction ID: ${transactionId.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');

  // --- Parse incoming attributes (optional, but good for robust server) ---
  int offset = 20;
  while (offset < requestBytes.length) {
    if (offset + 4 > requestBytes.length) {
      print('Warning: Incomplete attribute header. Skipping remaining bytes.');
      break;
    }

    final int attrType = requestData.getUint16(offset);
    final int attrLength = requestData.getUint16(offset + 2);
    final int attrValueStart = offset + 4;
    final int attrValueEnd = attrValueStart + attrLength;

    if (attrValueEnd > requestBytes.length) {
      print(
          'Warning: Attribute value extends beyond message boundary. Skipping.');
      break;
    }

    final Uint8List attrValue =
        requestBytes.sublist(attrValueStart, attrValueEnd);

    switch (attrType) {
      case stunAttrMappedAddress: // 0x0001
        print(
            '  Received MAPPED-ADDRESS attribute (0x0001). Length: $attrLength, Value: ${attrValue.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
        // Standard MAPPED-ADDRESS format for IPv4: [0x00, 0x01 (family), Port (2 bytes), IP (4 bytes)]
        if (attrLength >= 8) {
          final int family = attrValue[1];
          // Use ByteData.view with offsetInBytes to correctly read from the sublist's buffer
          final int port =
              ByteData.view(attrValue.buffer, attrValue.offsetInBytes + 2, 2)
                  .getUint16(0);
          String ip = '';
          if (family == 0x01 && attrLength >= 8) {
            // IPv4
            ip =
                '${attrValue[4]}.${attrValue[5]}.${attrValue[6]}.${attrValue[7]}';
            print('    Parsed MAPPED-ADDRESS: IPv4, Port: $port, IP: $ip');
          } else if (family == 0x02 && attrLength >= 20) {
            // IPv6
            print(
                '    Parsed MAPPED-ADDRESS: IPv6, Port: $port, IP: (IPv6 raw bytes: ${attrValue.sublist(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join()})');
          } else {
            // Log raw value and attempt ASCII decode for debugging non-standard data
            print(
                '    MAPPED-ADDRESS: Unknown family ($family) or invalid length for family. Raw value: ${attrValue.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
            try {
              print(
                  '    MAPPED-ADDRESS (attempted ASCII): "${utf8.decode(attrValue, allowMalformed: true)}"');
            } catch (e) {
              print('    MAPPED-ADDRESS: Could not decode as UTF8: $e');
            }
          }
        } else {
          // Log raw value and attempt ASCII decode for debugging non-standard data
          print(
              '    MAPPED-ADDRESS value too short for a valid address. Raw value: ${attrValue.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
          try {
            print(
                '    MAPPED-ADDRESS (attempted ASCII): "${utf8.decode(attrValue, allowMalformed: true)}"');
          } catch (e) {
            print('    MAPPED-ADDRESS: Could not decode as UTF8: $e');
          }
        }
        break;
      case stunAttrSoftware: // 0x8022
        try {
          final String softwareName = utf8.decode(
              attrValue.sublist(0, attrLength)); // Decode without padding
          print('  Received SOFTWARE attribute (0x8022): "$softwareName"');
        } catch (e) {
          print('  Error decoding SOFTWARE attribute: $e');
        }
        break;
      case stunAttrMessageIntegrity: // 0x0008
        print(
            '  Received MESSAGE-INTEGRITY attribute (0x0008). Hash: ${attrValue.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
        // In a real server, you'd calculate the HMAC over the received message
        // (excluding the MI and FP attributes) and validate it against this.
        // For simplicity, we are not doing full validation here, but merely parsing.
        break;
      case stunAttrFingerprint: // 0x8028
        print(
            '  Received FINGERPRINT attribute (0x8028). Checksum: ${attrValue.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
        // In a real server, you'd calculate the CRC32 over the received message
        // (excluding the FP attribute) and validate it against this.
        // For simplicity, we are not doing full validation here, but merely parsing.
        break;
      // Add cases for other known attributes you might expect
      default:
        print(
            '  Received Unknown Attribute (0x${attrType.toRadixString(16).padLeft(4, '0')}). Length: $attrLength, Value: ${attrValue.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
        break;
    }

    final int paddedAttrLength =
        (attrLength + 3) & ~3; // Pad to next multiple of 4
    offset += (4 + paddedAttrLength); // Move to start of next attribute
  }

  // --- Construct STUN Binding Response ---

  // 1. Build core attributes (XOR-MAPPED-ADDRESS, SOFTWARE)
  // These attributes are built first, before MESSAGE-INTEGRITY and FINGERPRINT,
  // as the latter depend on the bytes of the preceding message.
  final BytesBuilder attributesBuilder = BytesBuilder();

  // --- XOR-MAPPED-ADDRESS Attribute (Type: 0x0020) ---
  // Value: 8 bytes for IPv4 (Reserved, Family, X-Port, X-Address)
  final int xPort = clientPort ^
      (stunMagicCookie >>
          16); // XOR client port with top 16 bits of Magic Cookie
  final Uint8List clientIpBytes = clientAddress.rawAddress; // Get raw IP bytes
  final ByteData clientIpData = ByteData.view(clientIpBytes.buffer);
  final int clientIpInt =
      clientIpData.getUint32(0); // Assuming IPv4, get 32-bit integer
  final int xAddress =
      clientIpInt ^ stunMagicCookie; // XOR client IP with Magic Cookie

  final BytesBuilder xorMappedAddressValueBuilder = BytesBuilder();
  xorMappedAddressValueBuilder.addByte(0x00); // Reserved (0x00)
  xorMappedAddressValueBuilder.addByte(
      clientAddress.type == InternetAddressType.IPv4
          ? 0x01
          : 0x02); // Family (IPv4: 0x01, IPv6: 0x02)
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

  attributesBuilder.addByte(
      (stunAttrXorMappedAddress >> 8) & 0xFF); // Attribute Type high byte
  attributesBuilder
      .addByte(stunAttrXorMappedAddress & 0xFF); // Attribute Type low byte
  attributesBuilder
      .addByte((xorMappedAddressValue.length >> 8) & 0xFF); // Length high byte
  attributesBuilder
      .addByte(xorMappedAddressValue.length & 0xFF); // Length low byte
  attributesBuilder.add(xorMappedAddressValue);

  // --- SOFTWARE Attribute (Type: 0x8022, Optional) ---
  final String softwareName = 'Dart STUN Server v1.0 (with MI & FP)';
  final Uint8List softwareBytes = Uint8List.fromList(utf8.encode(softwareName));
  // Attributes must be padded to a multiple of 4 bytes.
  final int softwarePadding = (4 - (softwareBytes.length % 4)) % 4;
  final Uint8List paddedSoftwareBytes =
      Uint8List(softwareBytes.length + softwarePadding);
  paddedSoftwareBytes.setAll(0, softwareBytes); // Copy original bytes

  attributesBuilder.addByte((stunAttrSoftware >> 8) & 0xFF);
  attributesBuilder.addByte(stunAttrSoftware & 0xFF);
  attributesBuilder.addByte((paddedSoftwareBytes.length >> 8) & 0xFF);
  attributesBuilder.addByte(paddedSoftwareBytes.length & 0xFF);
  attributesBuilder.add(paddedSoftwareBytes);

  // --- MESSAGE-INTEGRITY Attribute (Type: 0x0008) ---
  // This attribute must be calculated over the entire STUN message *up to*
  // (but excluding) the MESSAGE-INTEGRITY attribute itself.
  // The STUN header's message length used for calculation must include
  // the MESSAGE-INTEGRITY attribute's length (20 bytes).

  // Tentative message length (header + current attributes + MI attr size)
  // MESSAGE-INTEGRITY attribute has a fixed size of 24 bytes (4 byte header + 20 byte hash).
  int tentativeMessageLength = 20 + attributesBuilder.length + 24;

  // Build a temporary header for HMAC calculation.
  // This header uses the 'tentativeMessageLength'.
  final BytesBuilder hmacHeaderBuilder = BytesBuilder();
  hmacHeaderBuilder.addByte((stunBindingResponse >> 8) & 0xFF);
  hmacHeaderBuilder.addByte(stunBindingResponse & 0xFF);
  hmacHeaderBuilder.addByte(
      (tentativeMessageLength >> 8) & 0xFF); // Placeholder length for HMAC
  hmacHeaderBuilder
      .addByte(tentativeMessageLength & 0xFF); // Placeholder length for HMAC
  hmacHeaderBuilder.addByte((stunMagicCookie >> 24) & 0xFF);
  hmacHeaderBuilder.addByte((stunMagicCookie >> 16) & 0xFF);
  hmacHeaderBuilder.addByte((stunMagicCookie >> 8) & 0xFF);
  hmacHeaderBuilder.addByte(stunMagicCookie & 0xFF);
  hmacHeaderBuilder.add(transactionId);

  // Combine temporary header with current attributes for HMAC calculation
  final Uint8List bytesForHmac = Uint8List.fromList(
      hmacHeaderBuilder.toBytes() + attributesBuilder.toBytes());

  // Calculate HMAC-SHA1 using the shared secret
  final Uint8List hmacHash = calculateHmacSha1(bytesForHmac, sharedSecret);

  // Add MESSAGE-INTEGRITY attribute to the attributes builder
  attributesBuilder.addByte((stunAttrMessageIntegrity >> 8) & 0xFF);
  attributesBuilder.addByte(stunAttrMessageIntegrity & 0xFF);
  attributesBuilder.addByte(0x00); // Length high (20 bytes for SHA1 hash)
  attributesBuilder.addByte(0x14); // Length low (20 bytes)
  attributesBuilder.add(hmacHash);

  // --- FINGERPRINT Attribute (Type: 0x8028) ---
  // This attribute must be calculated over the entire STUN message *up to*
  // (but excluding) the FINGERPRINT attribute itself.
  // This means it includes the MESSAGE-INTEGRITY attribute if present.
  // The STUN header's message length used for calculation must include
  // the FINGERPRINT attribute's length (4 bytes).

  // Final total message length (header + all attributes including MI and FP attr size)
  // FINGERPRINT attribute has a fixed size of 8 bytes (4 byte header + 4 byte checksum).
  int finalTotalMessageLength = 20 + attributesBuilder.length + 8;

  // Build a temporary header for CRC calculation.
  // This header uses the 'finalTotalMessageLength'.
  final BytesBuilder crcHeaderBuilder = BytesBuilder();
  crcHeaderBuilder.addByte((stunBindingResponse >> 8) & 0xFF);
  crcHeaderBuilder.addByte(stunBindingResponse & 0xFF);
  crcHeaderBuilder.addByte(
      (finalTotalMessageLength >> 8) & 0xFF); // Placeholder length for CRC
  crcHeaderBuilder
      .addByte(finalTotalMessageLength & 0xFF); // Placeholder length for CRC
  crcHeaderBuilder.addByte((stunMagicCookie >> 24) & 0xFF);
  crcHeaderBuilder.addByte((stunMagicCookie >> 16) & 0xFF);
  crcHeaderBuilder.addByte((stunMagicCookie >> 8) & 0xFF);
  crcHeaderBuilder.addByte(stunMagicCookie & 0xFF);
  crcHeaderBuilder.add(transactionId);

  // Combine temporary header with all attributes (including MESSAGE-INTEGRITY) for CRC calculation
  final Uint8List bytesForCrc = Uint8List.fromList(
      crcHeaderBuilder.toBytes() + attributesBuilder.toBytes());

  // Calculate CRC32 checksum (the helper function already XORs with XOR_MAGIC_COOKIE)
  final int crc32Checksum = calculateStunFingerprintCrc32(bytesForCrc);

  // Add FINGERPRINT attribute to the attributes builder
  attributesBuilder.addByte((stunAttrFingerprint >> 8) & 0xFF);
  attributesBuilder.addByte(stunAttrFingerprint & 0xFF);
  attributesBuilder.addByte(0x00); // Length high (4 bytes for CRC32)
  attributesBuilder.addByte(0x04); // Length low (4 bytes)
  // Add CRC32 value bytes
  attributesBuilder.addByte((crc32Checksum >> 24) & 0xFF);
  attributesBuilder.addByte((crc32Checksum >> 16) & 0xFF);
  attributesBuilder.addByte((crc32Checksum >> 8) & 0xFF);
  attributesBuilder.addByte(crc32Checksum & 0xFF);

  // --- Finalizing the STUN Message ---

  // Get the complete bytes of all attributes (including MI and FP)
  final Uint8List finalAttributesBytes = attributesBuilder.toBytes();

  // The true message length for the header is the length of all attributes.
  final int actualMessageLengthInHeader = finalAttributesBytes.length;

  // Build the final STUN Message Header
  final BytesBuilder finalHeaderBuilder = BytesBuilder();
  finalHeaderBuilder
      .addByte((stunBindingResponse >> 8) & 0xFF); // Message Type high byte
  finalHeaderBuilder
      .addByte(stunBindingResponse & 0xFF); // Message Type low byte
  finalHeaderBuilder.addByte(
      (actualMessageLengthInHeader >> 8) & 0xFF); // Message Length high byte
  finalHeaderBuilder
      .addByte(actualMessageLengthInHeader & 0xFF); // Message Length low byte
  finalHeaderBuilder.addByte((stunMagicCookie >> 24) & 0xFF);
  finalHeaderBuilder.addByte((stunMagicCookie >> 16) & 0xFF);
  finalHeaderBuilder.addByte((stunMagicCookie >> 8) & 0xFF);
  finalHeaderBuilder.addByte(stunMagicCookie & 0xFF);
  finalHeaderBuilder.add(transactionId);

  // Combine header and attributes to form the complete response message
  final Uint8List responseBytes =
      Uint8List.fromList(finalHeaderBuilder.toBytes() + finalAttributesBytes);

  print("Response bytes: $responseBytes");

  // Send the response back to the client
  socket.send(responseBytes, clientAddress, clientPort);
  print(
      'Sent STUN Binding Response with XOR-MAPPED-ADDRESS, SOFTWARE, MESSAGE-INTEGRITY, and FINGERPRINT to $clientAddress:$clientPort');
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
  // Value: 4 bytes (Class, Number, Reason Phrase)
  final int errorClass = (errorCode ~/ 100);
  final int errorNumber = (errorCode % 100);
  final Uint8List reasonPhraseBytes = utf8.encode(errorMessage);

  // Pad reason phrase to a multiple of 4 bytes
  final int reasonPhrasePadding = (4 - (reasonPhraseBytes.length % 4)) % 4;
  final Uint8List paddedReasonPhraseBytes =
      Uint8List(reasonPhraseBytes.length + reasonPhrasePadding);
  paddedReasonPhraseBytes.setAll(0, reasonPhraseBytes);

  final int errorCodeAttrLength = 4 +
      paddedReasonPhraseBytes
          .length; // 4 bytes for class/number + length of reason phrase

  attributesBuilder.addByte((stunAttrErrorCode >> 8) & 0xFF);
  attributesBuilder.addByte(stunAttrErrorCode & 0xFF);
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
      'Sent STUN Error Response ($errorCode - $errorMessage) to $clientAddress:$clientPort');
}

// --- Main function to run the server ---
Future<void> main() async {
  startStunServer(4444); // Standard STUN UDP port
  // Uncomment the line below to test the client sending the specific request
  // await Future.delayed(Duration(seconds: 2)); // Give server time to start
  // await startStunClient();
}
