import 'dart:typed_data';

import 'package:dartls/types/types.dart';

class TlsRandom {
  DateTime dateTime;
  Uint8List randBytes;

  TlsRandom(this.dateTime, this.randBytes);

  factory TlsRandom.unmarshal(Uint8List data, int offset, int arrayLength) {
    Uint32 seconds = Uint32.fromBytes(data.sublist(offset, offset + 4));
    DateTime dateTime =
        DateTime.fromMillisecondsSinceEpoch(seconds.value * 1000);
    offset += 4;

    Uint8List randBytes = data.sublist(offset, offset + 28);

    return TlsRandom(dateTime, randBytes);
  }

  Uint8List marshal() {
    final data = Uint8List.fromList([
      ...Uint32((dateTime.millisecond / 1000).toInt()).toBytes(),
      ...randBytes
    ]);

    if (data.length != 32) throw "invalid length";
    return data;
  }

  @override
  String toString() {
    // TODO: implement toString
    return """Tls random(gmt unix time: $dateTime,
                random bytes: $randBytes)""";

// """
//        cipher_suites_length: $cipher_suites_length,
//        cipher_suites: ${cipher_suites},
//        compression_methods_length: $compression_methods_length,
//        compression_methods: $compression_methods,
//        extensions: $extensions)
//        """;
  }
}
