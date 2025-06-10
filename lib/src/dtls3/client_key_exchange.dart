import 'dart:typed_data';

import 'dtls.dart';
import 'handshake_header.dart';

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
      return 2 + identityHint.length;
    }
  }

  // Marshal to byte array
  Uint8List encode() {
    final byteData = BytesBuilder();

    if ((identityHint.isNotEmpty && publicKey.isNotEmpty) ||
        (identityHint.isEmpty && publicKey.isEmpty)) {
      throw Error(); // Replace with your own error handling.
    }

    if (publicKey.isNotEmpty) {
      byteData.addByte(publicKey.length);
      byteData.add(Uint8List.fromList(publicKey));
    } else {
      byteData.addByte(identityHint.length);
      byteData.add(Uint8List.fromList(identityHint));
    }

    final bytes = byteData.toBytes();
    print("Client key exchange encoded data: $bytes");

    return bytes;
  }

  // Unmarshal from byte array
  static (ClientKeyExchange, int) decode(
      Uint8List data, int offset, int arrayLen) {
    print("Client key exchange data: ${data.sublist(offset)}");
    // int pskLength = ((data[0] << 8) | data[1]);
    // int offset = 0;
    final publicKeyLength = data[offset];
    offset++;
    // print("PSK length: $pskLength");

    // if (pskLength > data.length - 2) {
    //   throw "errBufferTooSmall";
    // }

    // print("Data length: ${data.length}");
    // print("PSK length: ${pskLength + 2}");
    // if (pskLength > 0) {
    //   print("PSK length: ${data.sublist(2, 2 + pskLength)}");
    //   return ClientKeyExchange(
    //     identityHint: data.sublist(2, 2 + pskLength),
    //     publicKey: [],
    //   );
    // }

    // print("PSK length: $pskLength");

    //int publicKeyLength = data[0];
    // if (data.length != publicKeyLength + 1) {
    //   throw Error(); // Replace with your own error handling.
    // }

    final publicKey = data.sublist(offset, offset + publicKeyLength);
    offset += publicKey.length;

    return (ClientKeyExchange(identityHint: [], publicKey: publicKey), offset);
  }

  // static ClientKeyExchange unmarshal(Uint8List buf) {
  //   int offset = 0;
  //   final publicKeyLength = buf[offset];
  //   offset++;
  //   final publicKey = buf.sublist(offset, offset + publicKeyLength);
  //   offset += (publicKeyLength);
  //   return ClientKeyExchange(
  //     identityHint: [],
  //     publicKey: publicKey,
  //   );
  // }

  @override
  String toString() {
    // TODO: implement toString
    return "{identityHint: $identityHint, publicKey: $publicKey}";
  }

  // static (ClientKeyExchange, int, bool?) decode(
  //     Uint8List buf, int offset, int arrayLen) {
  //   return (ClientKeyExchange.unmarshal(buf.sublist(offset)), offset, null);
  // }
}

void main() async {
  // Example usage
  final handshake = ClientKeyExchange(
    identityHint: [1, 2, 3],
    publicKey: Uint8List(0),
  );

  // Marshal the data to a byte array
  Uint8List marshalledData = handshake.encode();

  print('Marshalled: $marshalledData');
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

// final raw_psk = Uint8List.fromList([
//   0,
//   21,
//   119,
//   101,
//   98,
//   114,
//   116,
//   99,
//   45,
//   114,
//   115,
//   32,
//   68,
//   84,
//   76,
//   83,
//   32,
//   83,
//   101,
//   114,
//   118,
//   101,
//   114,
//   20,
//   254,
//   253,
//   0,
//   0,
//   0,
//   0,
//   0,
//   0,
//   0,
//   3,
//   0,
//   1,
//   1,
//   22,
//   254,
//   253,
//   0,
//   1,
//   0,
//   0,
//   0,
//   0,
//   0,
//   0,
//   0,
//   40,
//   44,
//   145,
//   205,
//   20,
//   79,
//   158,
//   191,
//   100,
//   243,
//   201,
//   201,
//   189,
//   229,
//   250,
//   130,
//   239,
//   90,
//   129,
//   255,
//   105,
//   86,
//   8,
//   175,
//   228,
//   117,
//   136,
//   13,
//   24,
//   204,
//   188,
//   30,
//   216,
//   206,
//   141,
//   191,
//   170,
//   253,
//   96,
//   22,
//   150
// ]);

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
