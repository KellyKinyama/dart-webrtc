import 'dart:typed_data';

import 'dtls.dart';
import 'handshake_header.dart';

// Assuming these are defined in your project
// import 'dtls.dart'; // Make sure ContentType and HandshakeType are defined here
// import 'handshake_header.dart'; // If you have other shared handshake definitions

// Placeholder for your DTLS related enums/classes if they are not in separate files

// Custom error for better clarity
class ClientKeyExchangeError extends Error {
  final String message;
  ClientKeyExchangeError(this.message);

  @override
  String toString() => 'ClientKeyExchangeError: $message';
}

class ClientKeyExchange {
  final List<int> identityHint;
  final Uint8List publicKey;

  ClientKeyExchange({
    required this.identityHint,
    required this.publicKey,
  });

  ContentType getContentType() {
    return ContentType.handshake;
  }

  // Handshake type
  HandshakeType getHandshakeType() {
    return HandshakeType.clientKeyExchange;
  }

  // Calculate size
  int size() {
    if (publicKey.isNotEmpty) {
      return 1 + publicKey.length;
    } else {
      // Identity hint length is 2 bytes
      return 2 + identityHint.length;
    }
  }

  // Marshal to byte array
  Uint8List encode() {
    final byteData = BytesBuilder();

    if ((identityHint.isNotEmpty && publicKey.isNotEmpty) ||
        (identityHint.isEmpty && publicKey.isEmpty)) {
      throw ClientKeyExchangeError(
          'ClientKeyExchange must have either identityHint or publicKey, but not both or neither.');
    }

    if (publicKey.isNotEmpty) {
      // Public key length is 1 byte
      if (publicKey.length > 255) {
        throw ClientKeyExchangeError(
            'Public key length exceeds 255 bytes, cannot encode with 1-byte length.');
      }
      byteData.addByte(publicKey.length);
      byteData.add(publicKey); // publicKey is already Uint8List
    } else {
      // Identity hint length is 2 bytes (Big Endian)
      if (identityHint.length > 65535) {
        throw ClientKeyExchangeError(
            'Identity hint length exceeds 65535 bytes, cannot encode with 2-byte length.');
      }
      byteData.addByte((identityHint.length >> 8) & 0xFF); // High byte
      byteData.addByte(identityHint.length & 0xFF); // Low byte
      byteData.add(Uint8List.fromList(identityHint));
    }

    return byteData.toBytes();
  }

  // Unmarshal from byte array
  static (ClientKeyExchange, int) decode(
      Uint8List data, int offset, int arrayLen) {
    if (arrayLen == 0) {
      throw ClientKeyExchangeError(
          'Cannot decode ClientKeyExchange from empty buffer.');
    }

    // Attempt to parse as PSK identity hint first (2-byte length)
    if (arrayLen >= 2) {
      final int pskLength = (data[offset] << 8) | data[offset + 1];
      if (arrayLen >= 2 + pskLength) {
        // It looks like a PSK identity hint
        final identityHint = data.sublist(offset + 2, offset + 2 + pskLength);
        final newOffset = offset + 2 + pskLength;
        return (
          ClientKeyExchange(
              identityHint: identityHint, publicKey: Uint8List(0)),
          newOffset
        );
      }
    }

    // If it didn't match PSK format, attempt to parse as Public Key (1-byte length)
    if (arrayLen >= 1) {
      final int publicKeyLength = data[offset];
      if (arrayLen >= 1 + publicKeyLength) {
        final publicKey =
            data.sublist(offset + 1, offset + 1 + publicKeyLength);
        final newOffset = offset + 1 + publicKeyLength;
        return (
          ClientKeyExchange(identityHint: [], publicKey: publicKey),
          newOffset
        );
      }
    }

    // If neither format matched, it's an error
    throw ClientKeyExchangeError(
        'Failed to decode ClientKeyExchange: insufficient data or invalid format.');
  }

  @override
  String toString() {
    return "{identityHint: $identityHint, publicKey: $publicKey}";
  }
}

void main() async {
  // Example usage
  // final handshake = ClientKeyExchange(
  //   identityHint: [1, 2, 3],
  //   publicKey: Uint8List(0),
  // );

  // Marshal the data to a byte array
  // Uint8List marshalledData = handshake.encode();

  // print('Marshalled: $marshalledData');
  // await File('handshake_data.dat').writeAsBytes(marshalledData);

  // Read the byte array back from the file and unmarshal it
  // Uint8List unmarshalledData = await File('handshake_data.dat').readAsBytes();
  final (unmarshalled, _) =
      ClientKeyExchange.decode(clientKeyExchange, 0, clientKeyExchange.length);

  print('Unmarshalled: $unmarshalled');
  //print('Wanted:       ${raw_client_key_exchange.sublist(1)}');
  print("Remarshalled: ${unmarshalled.encode()}");
  print("Expected:     $clientKeyExchange");
}

final clientKeyExchange = Uint8List.fromList([
  0x10,
  0x00,
  0x00,
  0x21,
  0x20,
  0x35,
  0x80,
  0x72,
  0xd6,
  0x36,
  0x58,
  0x80,
  0xd1,
  0xae,
  0xea,
  0x32,
  0x9a,
  0xdf,
  0x91,
  0x21,
  0x38,
  0x38,
  0x51,
  0xed,
  0x21,
  0xa2,
  0x8e,
  0x3b,
  0x75,
  0xe9,
  0x65,
  0xd0,
  0xd2,
  0xcd,
  0x16,
  0x62,
  0x54,
]);
