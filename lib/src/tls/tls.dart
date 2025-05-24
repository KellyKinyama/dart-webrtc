// Core Dart translation of TLS suite logic from tls.c
// Includes CipherSuite definition, TLSParameters, message sending, and handshake support

import 'dart:typed_data';
import 'dart:math';
import 'dart:convert';

typedef DigestFunction = void Function();
typedef BulkCipherFunction = void Function(
  Uint8List input,
  int inputLen,
  Uint8List output,
  Uint8List iv,
  Uint8List key,
);

class CipherSuite {
  final int id;
  final int blockSize;
  final int ivSize;
  final int keySize;
  final int hashSize;
  final BulkCipherFunction? bulkEncrypt;
  final BulkCipherFunction? bulkDecrypt;
  final DigestFunction? newDigest;

  const CipherSuite({
    required this.id,
    required this.blockSize,
    required this.ivSize,
    required this.keySize,
    required this.hashSize,
    this.bulkEncrypt,
    this.bulkDecrypt,
    this.newDigest,
  });
}

const int MAX_SUPPORTED_CIPHER_SUITE = 50;

class ProtectionParameters {
  Uint8List macSecret = Uint8List(0);
  Uint8List key = Uint8List(0);
  Uint8List iv = Uint8List(0);
  int seqNum = 0;
  int suite = 0;
}

class TLSParameters {
  final ProtectionParameters pendingSend = ProtectionParameters();
  final ProtectionParameters pendingRecv = ProtectionParameters();
  final ProtectionParameters activeSend = ProtectionParameters();
  final ProtectionParameters activeRecv = ProtectionParameters();

  bool supportSecureRenegotiation = false;
  final Uint8List clientVerifyData = Uint8List(12);
  final Uint8List serverVerifyData = Uint8List(12);
  final Uint8List masterSecret = Uint8List(48);
  final Uint8List clientRandom = Uint8List(32);
  final Uint8List serverRandom = Uint8List(32);

  int sessionIdLength = 0;
  final Uint8List sessionId = Uint8List(32);
  bool gotClientHello = false;
  bool serverHelloDone = false;
  bool peerFinished = false;

  Uint8List? unreadBuffer;
  int unreadLength = 0;
}

class TLSPlaintext {
  final int type;
  final int versionMajor;
  final int versionMinor;
  final int length;

  TLSPlaintext(this.type, this.versionMajor, this.versionMinor, this.length);
}

// Constants
const int TLS_VERSION_MAJOR = 3;
const int TLS_VERSION_MINOR = 1;
const int VERIFY_DATA_LEN = 12;
const int MASTER_SECRET_LENGTH = 48;
const int RANDOM_LENGTH = 32;
const int CONTENT_TYPE_HANDSHAKE = 22;
const int HANDSHAKE_TYPE_CLIENT_HELLO = 1;
const int HANDSHAKE_TYPE_SERVER_HELLO = 2;

// Cipher suites (example only)
final List<CipherSuite> suites = [
  CipherSuite(id: 0x0000, blockSize: 0, ivSize: 0, keySize: 0, hashSize: 0),
];

// Utility
Uint8List appendBuffer(Uint8List dest, Uint8List src) {
  final buffer = Uint8List(dest.length + src.length);
  buffer.setAll(0, dest);
  buffer.setAll(dest.length, src);
  return buffer;
}

Uint8List hmac(Uint8List key, Uint8List message, DigestFunction? digestCreator) {
  return Uint8List(20); // Dummy placeholder
}

int sendMessage(int connection, int contentType, Uint8List content, ProtectionParameters parameters) {
  final suite = suites[parameters.suite];
  final header = TLSPlaintext(contentType, TLS_VERSION_MAJOR, TLS_VERSION_MINOR, content.length);
  final macHeader = Uint8List(13);
  macHeader.buffer.asByteData().setUint32(4, parameters.seqNum);
  macHeader[8] = contentType;
  macHeader[9] = header.versionMajor;
  macHeader[10] = header.versionMinor;
  macHeader.buffer.asByteData().setUint16(11, content.length);

  final mac = hmac(parameters.macSecret, appendBuffer(macHeader, content), suite.newDigest);
  parameters.seqNum++;

  Uint8List encrypted = content;
  if (suite.bulkEncrypt != null) {
    final iv = Uint8List(suite.ivSize);
    encrypted = Uint8List(content.length);
    suite.bulkEncrypt!(content, content.length, encrypted, iv, parameters.key);
  }

  final output = appendBuffer(mac, encrypted);
  print('Sending message: type=$contentType, len=${output.length}');
  return 0;
}

// TLS Handshake
Uint8List buildClientHello(TLSParameters parameters) {
  final rand = Random.secure();
  final timeBytes = ByteData(4)..setUint32(0, DateTime.now().millisecondsSinceEpoch ~/ 1000);
  final randomBytes = Uint8List.fromList(List.generate(28, (_) => rand.nextInt(256)));

  final random = Uint8List.fromList([...timeBytes.buffer.asUint8List(), ...randomBytes]);
  parameters.clientRandom.setAll(0, random);

  final sessionId = Uint8List(0);
  final suitesBytes = Uint8List.fromList([0x00, 0x2F]); // TLS_RSA_WITH_AES_128_CBC_SHA
  final compression = Uint8List.fromList([0x00]); // null

  final hello = BytesBuilder();
  hello.add([TLS_VERSION_MAJOR, TLS_VERSION_MINOR]);
  hello.add(random);
  hello.add([sessionId.length]);
  hello.add(sessionId);
  hello.add([(suitesBytes.length >> 8) & 0xFF, suitesBytes.length & 0xFF]);
  hello.add(suitesBytes);
  hello.add([compression.length]);
  hello.add(compression);

  final handshake = BytesBuilder();
  handshake.add([HANDSHAKE_TYPE_CLIENT_HELLO]);
  final body = hello.toBytes();
  handshake.add([(body.length >> 16) & 0xFF, (body.length >> 8) & 0xFF, body.length & 0xFF]);
  handshake.add(body);

  return handshake.toBytes();
}

Uint8List buildServerHello(TLSParameters parameters) {
  final rand = Random.secure();
  final timeBytes = ByteData(4)..setUint32(0, DateTime.now().millisecondsSinceEpoch ~/ 1000);
  final randomBytes = Uint8List.fromList(List.generate(28, (_) => rand.nextInt(256)));

  final random = Uint8List.fromList([...timeBytes.buffer.asUint8List(), ...randomBytes]);
  parameters.serverRandom.setAll(0, random);

  final sessionId = Uint8List.fromList([1, 2, 3, 4]);
  final suite = 0x002F;
  final compression = 0x00;

  final hello = BytesBuilder();
  hello.add([TLS_VERSION_MAJOR, TLS_VERSION_MINOR]);
  hello.add(random);
  hello.add([sessionId.length]);
  hello.add(sessionId);
  hello.add([(suite >> 8) & 0xFF, suite & 0xFF]);
  hello.add([compression]);

  final handshake = BytesBuilder();
  handshake.add([HANDSHAKE_TYPE_SERVER_HELLO]);
  final body = hello.toBytes();
  handshake.add([(body.length >> 16) & 0xFF, (body.length >> 8) & 0xFF, body.length & 0xFF]);
  handshake.add(body);

  return handshake.toBytes();
}
