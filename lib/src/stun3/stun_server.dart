import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart'; // For HMAC-SHA1
import 'dart:convert'; // For utf8 encoding

// --- STUN Attribute Type Constants ---
const int stunAttrXorMappedAddress = 0x0020;
const int stunAttrSoftware = 0x8022;
const int stunAttrMessageIntegrity = 0x0008;
const int stunAttrFingerprint = 0x8028;

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
        print('Received data ${datagram.data}');
        handleStunRequest(socket, datagram);
      }
    }
  }
}

Future<void> startStunClient() async {
  final RawDatagramSocket socket =
      await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  print(
      'STUN server listening on UDP port ${socket.address.address}:${socket.port}');

  print("Sending data to stun server");
  socket.send(request, InternetAddress("10.100.53.194"), 4444);
  // Listen for incoming datagrams
  await for (RawSocketEvent event in socket) {
    if (event == RawSocketEvent.read) {
      Datagram? datagram = socket.receive();
      if (datagram != null) {
        // handleStunRequest(socket, datagram);
        print(
            'Received response from ${datagram.address.address}:${datagram.port}');
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
    return;
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
    // For a real server, you might send an error response or just ignore.
    return;
  }

  // Validate total message length against header's message length
  if (requestBytes.length != (20 + messageLength)) {
    print(
        'Received packet with invalid length. Header says $messageLength, actual is ${requestBytes.length - 20} from $clientAddress:$clientPort');
    return;
  }

  // Only handle STUN Binding Requests for this implementation
  if (messageType != stunBindingRequest) {
    print(
        'Received non-Binding Request (type: ${messageType.toRadixString(16)}) from $clientAddress:$clientPort');
    // Optionally send an error response indicating unsupported message type (e.g., 400 Bad Request)
    return;
  }

  print(
      'Received STUN Binding Request from $clientAddress:$clientPort, Transaction ID: ${transactionId.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');

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
  xorMappedAddressValueBuilder.addByte(0x00); // Reserved (0x00)
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

// --- Main function to run the server ---
Future<void> main() async {
  startStunServer(4444); // Standard STUN UDP port
  // await Future.delayed(Duration(seconds: 5)); // Give server time to start
  // await startStunClient(); // Client to send a request to the server
}

final request = Uint8List.fromList(
    [0, 1, 0, 0, 33, 18, 164, 66, 0, 0, 0, 0, 0, 0, 0, 0, 23, 235, 210, 205]);
