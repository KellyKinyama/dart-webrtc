import 'dart:io';
import 'dart:typed_data';

Future<void> main() async {
  const stunServerAddress = 'stun.l.google.com';
  const stunServerPort = 19302;

  try {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    print('Local UDP socket bound to: ${socket.address}:${socket.port}');

    // 1. Construct the STUN Binding Request (simplified)
    final transactionId = generateTransactionId();
    final bindingRequest = constructStunBindingRequest(transactionId);

    // 2. Send the STUN Binding Request to the server
    final remoteAddress = InternetAddress(stunServerAddress);
    socket.send(bindingRequest, remoteAddress, stunServerPort);
    print('STUN Binding Request sent to $stunServerAddress:$stunServerPort');

    // 3. Listen for the STUN Binding Response
    await socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram != null) {
          final responseData = datagram.data;
          final remoteHost = datagram.address;
          final remotePort = datagram.port;

          print('Received STUN response from $remoteHost:$remotePort');
          parseStunBindingResponse(responseData, transactionId);
        }
      }
    });

    // Allow some time for the response to arrive
    await Future.delayed(Duration(seconds: 5));

    socket.close();
  } catch (e) {
    print('Error occurred: $e');
  }
}

// --- STUN Message Construction ---

Uint8List constructStunBindingRequest(Uint8List transactionId) {
  final messageType = 0x0001; // Binding Request
  final messageLength = 0x0000; // No attributes in this simplified request

  final buffer = BytesBuilder();
  buffer.addUint16(messageType);
  buffer.addUint16(messageLength);
  buffer.add(kMagicCookie);
  buffer.add(transactionId);

  return buffer.toBytes();
}

// STUN Magic Cookie (fixed value)
final kMagicCookie = Uint8List.fromList([0x21, 0x12, 0xA4, 0x42]);

// Generate a random 12-byte transaction ID
Uint8List generateTransactionId() {
  final random = Random.secure();
  final transactionId = Uint8List(12);
  for (var i = 0; i < 12; i++) {
    transactionId[i] = random.nextInt(256);
  }
  return transactionId;
}

// --- STUN Message Parsing (Simplified - Focus on XOR-MAPPED-ADDRESS) ---

void parseStunBindingResponse(Uint8List data, Uint8List originalTransactionId) {
  if (data.length < 20) {
    print('Error: Received STUN response is too short.');
    return;
  }

  final messageType = data.buffer.asUint16List(0, 1)[0];
  final messageLength = data.buffer.asUint16List(2, 1)[0];
  final magicCookie = data.sublist(4, 8);
  final transactionId = data.sublist(8, 20);

  if (!listEquals(magicCookie, kMagicCookie)) {
    print('Error: Invalid STUN Magic Cookie.');
    return;
  }

  if (!listEquals(transactionId, originalTransactionId)) {
    print('Error: Transaction ID mismatch.');
    return;
  }

  if (messageType == 0x0101) { // Binding Response Success
    print('Received STUN Binding Response (Success)');

    int attributeOffset = 20;
    while (attributeOffset < data.length) {
      if (attributeOffset + 4 > data.length) {
        print('Error: Incomplete attribute header.');
        break;
      }

      final attributeType = data.buffer.asUint16List(attributeOffset, 1)[0];
      final attributeLength = data.buffer.asUint16List(attributeOffset + 2, 1)[0];
      final attributeValueOffset = attributeOffset + 4;

      if (attributeValueOffset + attributeLength > data.length) {
        print('Error: Incomplete attribute value.');
        break;
      }

      final attributeValue = data.sublist(attributeValueOffset, attributeValueOffset + attributeLength);

      switch (attributeType) {
        case 0x0020: // XOR-MAPPED-ADDRESS
          parseXorMappedAddressAttribute(attributeValue);
          break;
        // Handle other attributes as needed (e.g., MAPPED-ADDRESS)
        default:
          print('Received unknown attribute: 0x${attributeType.toRadixString(16).padLeft(4, '0')} (Length: $attributeLength)');
      }

      attributeOffset += 4 + attributeLength;
      // STUN attributes are often padded to a multiple of 4 bytes
      if (attributeLength % 4 != 0) {
        attributeOffset += (4 - (attributeLength % 4));
      }
    }
  } else if (messageType == 0x0111) { // Binding Error Response
    print('Received STUN Binding Response (Error)');
    // Implement error code parsing here
  } else {
    print('Received unknown STUN message type: 0x${messageType.toRadixString(16).padLeft(4, '0')}');
  }
}

void parseXorMappedAddressAttribute(Uint8List attributeValue) {
  if (attributeValue.length < 8) {
    print('Error: XOR-MAPPED-ADDRESS attribute is too short.');
    return;
  }

  final family = attributeValue.buffer.asUint16List(0, 1)[0];
  final portXored = attributeValue.buffer.asUint16List(2, 1)[0];
  final addressXoredBytes = attributeValue.sublist(4);

  if (family == 0x01) { // IPv4
    if (addressXoredBytes.length != 4) {
      print('Error: Invalid IPv4 address length in XOR-MAPPED-ADDRESS.');
      return;
    }
    final port = portXored ^ kMagicCookie.buffer.asUint16List(0, 1)[0];
    final addressBytes = Uint8List(4);
    for (var i = 0; i < 4; i++) {
      addressBytes[i] = addressXoredBytes[i] ^ kMagicCookie[i];
    }
    final address = InternetAddress.fromRawAddress(addressBytes);
    print('Discovered public IPv4 address: $address:$port (via XOR-MAPPED-ADDRESS)');
  } else if (family == 0x02) { // IPv6
    // Implement IPv6 XOR-MAPPED-ADDRESS parsing if needed
    print('IPv6 XOR-MAPPED-ADDRESS parsing not implemented in this example.');
  } else {
    print('Error: Unknown address family in XOR-MAPPED-ADDRESS: $family');
  }
}

import 'dart:math';
import 'package:collection/collection.dart'; // For listEquals