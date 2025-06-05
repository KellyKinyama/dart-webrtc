// dtls.dart (Placeholder for common DTLS types)

import 'dart:typed_data';

enum DtlsVersion {
  DTLSv1_2(0xfeff),
  DTLSv1_0(0xfeff),
  Unsupported(0x0000);

  const DtlsVersion(this.value);
  final int value;

  factory DtlsVersion.fromInt(int val) {
    return values.firstWhere((e) => e.value == val,
        orElse: () => DtlsVersion.Unsupported);
  }

  @override
  String toString() {
    switch (this) {
      case DTLSv1_2:
        return "DTLSv1.2";
      case DTLSv1_0:
        return "DTLSv1.0";
      default:
        return "Unsupported";
    }
  }
}

class ProtocolVersion {
  final int major;
  final int minor;

  ProtocolVersion(this.major, this.minor);

  @override
  String toString() => '$major.$minor';
}

class DtlsRandom {
  Uint8List gmtUnixTime;
  Uint8List bytes;

  DtlsRandom({required this.gmtUnixTime, required this.bytes});

  static (DtlsRandom, int) decode(Uint8List buf, int offset) {
    final reader = ByteData.sublistView(buf);
    final gmt = buf.sublist(offset, offset + 4);
    offset += 4;
    final randBytes = buf.sublist(offset, offset + 28);
    offset += 28;
    return (DtlsRandom(gmtUnixTime: gmt, bytes: randBytes), offset);
  }

  Uint8List encode() {
    final builder = BytesBuilder();
    builder.add(gmtUnixTime);
    builder.add(bytes);
    return builder.toBytes();
  }

  // @override
  // String toString() =>
  //     'Random(gmt: ${gmtUnixTime.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}, bytes: ${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()})';

  @override
  String toString() =>
      'Random(gmt: ${gmtUnixTime.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}, bytes: $bytes)';
}

enum CipherSuiteId {
  TLS_NULL_WITH_NULL_NULL(0x0000),
  TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256(0xc02b),
  TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256(0xc02f),
  TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA(0xc009),
  TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA(0xc013),
  Unsupported(0x0000);

  const CipherSuiteId(this.value);
  final int value;

  factory CipherSuiteId.fromInt(int val) {
    return values.firstWhere((e) => e.value == val,
        orElse: () => CipherSuiteId.Unsupported);
  }

  @override
  String toString() {
    switch (this) {
      case TLS_NULL_WITH_NULL_NULL:
        return "TLS_NULL_WITH_NULL_NULL";
      case TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256:
        return "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256";
      case TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256:
        return "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256";
      case TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA:
        return "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA";
      case TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA:
        return "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA";
      default:
        return "Unsupported";
    }
  }
}

// enum ContentType {
//   Handshake(22),
//   Unsupported(0);

//   const ContentType(this.value);
//   final int value;

//   factory ContentType.fromInt(int val) {
//     return values.firstWhere((e) => e.value == val,
//         orElse: () => ContentType.Unsupported);
//   }
// }

enum ContentType {
  changeCipherSpec(20),
  alert(21),
  handshake(22),
  applicationData(23),
  Unsupported(0);

  const ContentType(this.value);
  final int value;

  factory ContentType.fromInt(int key) {
    return values.firstWhere((element) => element.value == key);
  }
}

// enum HandshakeType {
//   ClientHello(1),
//   ServerHello(2),
//   Unsupported(0);

//   const HandshakeType(this.value);
//   final int value;

//   factory HandshakeType.fromInt(int val) {
//     return values.firstWhere((e) => e.value == val,
//         orElse: () => HandshakeType.Unsupported);
//   }
// }
