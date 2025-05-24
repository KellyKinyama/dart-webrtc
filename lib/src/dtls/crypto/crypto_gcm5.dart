import 'dart:typed_data';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

import '../handshake/handshake.dart';
import '../record_layer_header.dart';

const int gcmTagLength = 16;
const int gcmNonceLength = 12;
const int recordLayerHeaderSize = 13;

class GCM {
  final AesGcm _localGcm;
  final AesGcm _remoteGcm;
  final SecretKey localKey;
  final SecretKey remoteKey;
  final Uint8List localWriteIV;
  final Uint8List remoteWriteIV;

  GCM._(this._localGcm, this.localKey, this.localWriteIV, this._remoteGcm,
      this.remoteKey, this.remoteWriteIV);

  static Future<GCM> create(Uint8List localKey, Uint8List localWriteIV,
      Uint8List remoteKey, Uint8List remoteWriteIV) async {
    // print("local key: $localKey, local IV: $localWriteIV");
    // print("remote key: $remoteKey, remote IV: $remoteWriteIV");
    final localGCM = AesGcm.with128bits();
    final remoteGCM = AesGcm.with128bits();

    return GCM._(localGCM, SecretKey(localKey), localWriteIV, remoteGCM,
        SecretKey(remoteKey), remoteWriteIV);
  }

  Future<Uint8List> encrypt(RecordLayerHeader header, Uint8List raw) async {
    // print("encryption key: $localKey, encryption IV: $localWriteIV");
    final payload = raw.sublist(recordLayerHeaderSize);
    final rawHeader = raw.sublist(0, recordLayerHeaderSize);

    final nonce = Uint8List(gcmNonceLength);
    nonce.setRange(0, 4, localWriteIV.sublist(0, 4));
    nonce.setRange(4, 12, _randomBytes(8));

    final additionalData = _generateAEADAdditionalData(header, payload.length);

    // print("Additional data: ${additionalData}");
    // print("nonce key: ${nonce}");

    final secretBox = await _localGcm.encrypt(payload,
        secretKey: localKey, nonce: nonce, aad: additionalData);

    final result = Uint8List(rawHeader.length +
        nonce.length -
        4 +
        secretBox.cipherText.length +
        secretBox.mac.bytes.length);
    result.setRange(0, rawHeader.length, rawHeader);
    result.setRange(rawHeader.length, rawHeader.length + 8, nonce.sublist(4));
    result.setRange(rawHeader.length + 8, result.length,
        secretBox.cipherText + secretBox.mac.bytes);

    // Update record layer size
    final rLen = (result.length - recordLayerHeaderSize).toUnsigned(16);
    result.setRange(recordLayerHeaderSize - 2, recordLayerHeaderSize,
        Uint8List(2)..buffer.asByteData().setUint16(0, rLen, Endian.big));

    return result;
  }

  Future<Uint8List?> decrypt(Uint8List r) async {
    if (r.length <= recordLayerHeaderSize + 8) {
      return null;
    }

    final (header, _, _) = RecordLayerHeader.unmarshal(
        r.sublist(0, recordLayerHeaderSize),
        offset: 0,
        arrayLen: r.length);
    if (header.contentType == ContentType.content_change_cipher_spec) {
      print("Nothing to encript");
      return r;
    }

    final nonce = Uint8List(gcmNonceLength);
    nonce.setRange(0, 4, remoteWriteIV.sublist(0, 4)); // Copy IV prefix
    nonce.setRange(
        4,
        12,
        r.sublist(recordLayerHeaderSize,
            recordLayerHeaderSize + 8)); // Restore nonce suffix

    final ciphertext = r.sublist(recordLayerHeaderSize + 8);
    final additionalData =
        _generateAEADAdditionalData(header, ciphertext.length - gcmTagLength);

    final secretBox = SecretBox(
        ciphertext.sublist(0, ciphertext.length - gcmTagLength),
        nonce: nonce,
        mac: Mac(ciphertext.sublist(ciphertext.length - gcmTagLength)));

    final decrypted = await _localGcm.decrypt(secretBox,
        secretKey: remoteKey, aad: additionalData);

    final result = Uint8List(recordLayerHeaderSize + decrypted.length);
    result.setRange(
        0, recordLayerHeaderSize, r.sublist(0, recordLayerHeaderSize));
    result.setRange(recordLayerHeaderSize, result.length, decrypted);

    print("decripted data: $result");

    return result;
    // } catch (e) {
    //   print("[Decrypt] MAC Authentication Failed: $e");
    //   return null;
    // }
  }

  Uint8List _randomBytes(int length) {
    final rand = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rand.nextInt(256)));
  }

  Uint8List _generateAEADAdditionalData(
      RecordLayerHeader header, int payloadLen) {
    final additionalData = Uint8List(13);
    final byteData = ByteData.sublistView(additionalData);

    byteData.setUint16(0, header.epoch, Endian.big);
    additionalData.setRange(2, 8, header.marshalSequence());
    additionalData[8] = header.contentType.value;
    byteData.setUint8(9, header.protocolVersion.major);
    byteData.setUint8(10, header.protocolVersion.minor);
    byteData.setUint16(11, payloadLen, Endian.big);

    return additionalData;
  }
}

String bytesToHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
}


// [Encrypt] IV: 14cdba450001000000000001
// [Encrypt] Explicit Nonce: 0001000000000001
// [Encrypt] Write Key: 02e9390c5e32dc1efc4d164668e63044
// [Encrypt] Additional Data: { epoch: 1, sequence: 1, type: 23, version: 65277, length: 17 }
// [Encrypt] Additional Buffer: 000100000000000117fefd0011
// [Encrypt] Data: 68656c6c6f2066726f6d20636c69656e74
// [Encrypt] Encrypted Head Part: 354af591d5d651044ff67e94cef40d5499
// [Encrypt] Encrypted Final Part:
// [Encrypt] Auth Tag: 958b2f354d4366217aa3a1e99ca00791