import 'dart:typed_data';

import 'handshake.dart';

class ClientKeyExchange {
  final List<int> identityHint;
  final List<int> publicKey;

  ClientKeyExchange({
    required this.identityHint,
    required this.publicKey,
  });

  ContentType getContentType() {
    return ContentType.content_handshake;
  }

  // Handshake type
  HandshakeType getHandshakeType() {
    return HandshakeType.client_key_exchange;
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
  Uint8List marshal() {
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

    return byteData.toBytes();
  }

  // Unmarshal from byte array
  static (ClientKeyExchange, int, bool?) unmarshal(
      Uint8List data, int offset, int arrayLen) {
    // print("Client key exchange data: $data");
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

    return (
      ClientKeyExchange(identityHint: [], publicKey: publicKey),
      offset,
      null
    );
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
    publicKey: [],
  );

  // Marshal the data to a byte array
  Uint8List marshalledData = handshake.marshal();

  print('Marshalled: $marshalledData');
  // await File('handshake_data.dat').writeAsBytes(marshalledData);

  // Read the byte array back from the file and unmarshal it
  // Uint8List unmarshalledData = await File('handshake_data.dat').readAsBytes();
  final unmarshalled = ClientKeyExchange.unmarshal(raw_psk, 0, raw_psk.length);

  print('Unmarshalled: ${unmarshalled}');
  //print('Wanted:       ${raw_client_key_exchange.sublist(1)}');
}

final raw_psk = Uint8List.fromList([
  0,
  21,
  119,
  101,
  98,
  114,
  116,
  99,
  45,
  114,
  115,
  32,
  68,
  84,
  76,
  83,
  32,
  83,
  101,
  114,
  118,
  101,
  114,
  20,
  254,
  253,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  3,
  0,
  1,
  1,
  22,
  254,
  253,
  0,
  1,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  40,
  44,
  145,
  205,
  20,
  79,
  158,
  191,
  100,
  243,
  201,
  201,
  189,
  229,
  250,
  130,
  239,
  90,
  129,
  255,
  105,
  86,
  8,
  175,
  228,
  117,
  136,
  13,
  24,
  204,
  188,
  30,
  216,
  206,
  141,
  191,
  170,
  253,
  96,
  22,
  150
]);

final raw_client_key_exchange = Uint8List.fromList([
  0x20,
  0x26,
  0x78,
  0x4a,
  0x78,
  0x70,
  0xc1,
  0xf9,
  0x71,
  0xea,
  0x50,
  0x4a,
  0xb5,
  0xbb,
  0x00,
  0x76,
  0x02,
  0x05,
  0xda,
  0xf7,
  0xd0,
  0x3f,
  0xe3,
  0xf7,
  0x4e,
  0x8a,
  0x14,
  0x6f,
  0xb7,
  0xe0,
  0xc0,
  0xff,
  0x54,
]);
