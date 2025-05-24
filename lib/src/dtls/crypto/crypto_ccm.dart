import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'dart:math';

import '../handshake/handshake.dart';
import '../record_layer_header.dart';

const int ccmTagLength = 16;
const int ccmNonceLength = 12;
const int recordLayerHeaderSize = 13;

class CCM {
  final Uint8List localKey;
  final Uint8List remoteKey;
  final Uint8List localWriteIV;
  final Uint8List remoteWriteIV;

  CCM(this.localKey, this.localWriteIV, this.remoteKey, this.remoteWriteIV);

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

  Uint8List encrypt(RecordLayerHeader header, Uint8List raw) {
    final payload = raw.sublist(recordLayerHeaderSize);
    final rawHeader = raw.sublist(0, recordLayerHeaderSize);

    final nonce = Uint8List(ccmNonceLength);
    nonce.setRange(0, 4, localWriteIV.sublist(0, 4));
    nonce.setRange(4, 12, _randomBytes(8));

    final aad = _generateAEADAdditionalData(header, payload.length);

    final cipher = CCMBlockCipher(AESEngine());
    final params =
        AEADParameters(KeyParameter(localKey), ccmTagLength * 8, nonce, aad);
    cipher.init(true, params);

    final encrypted = cipher.process(payload);

    final result = Uint8List(rawHeader.length + 8 + encrypted.length);
    result.setRange(0, rawHeader.length, rawHeader);
    result.setRange(rawHeader.length, rawHeader.length + 8, nonce.sublist(4));
    result.setRange(rawHeader.length + 8, result.length, encrypted);

    final rLen = (result.length - recordLayerHeaderSize).toUnsigned(16);
    result.setRange(recordLayerHeaderSize - 2, recordLayerHeaderSize,
        Uint8List(2)..buffer.asByteData().setUint16(0, rLen, Endian.big));

    return result;
  }

  Uint8List? decrypt(Uint8List r) {
    if (r.length <= recordLayerHeaderSize + 8) {
      return null;
    }

    final (header, _, _) = RecordLayerHeader.unmarshal(
        r.sublist(0, recordLayerHeaderSize),
        offset: 0,
        arrayLen: r.length);
    if (header.contentType == ContentType.content_change_cipher_spec) {
      return r;
    }

    final nonce = Uint8List(ccmNonceLength);
    nonce.setRange(0, 4, remoteWriteIV.sublist(0, 4));
    nonce.setRange(
        4, 12, r.sublist(recordLayerHeaderSize, recordLayerHeaderSize + 8));

    final ciphertext = r.sublist(recordLayerHeaderSize + 8);
    final aad =
        _generateAEADAdditionalData(header, ciphertext.length - ccmTagLength);

    final cipher = CCMBlockCipher(AESEngine());
    final params =
        AEADParameters(KeyParameter(remoteKey), ccmTagLength * 8, nonce, aad);
    cipher.init(false, params);

    try {
      final decrypted = cipher.process(ciphertext);
      final result = Uint8List(recordLayerHeaderSize + decrypted.length);
      result.setRange(
          0, recordLayerHeaderSize, r.sublist(0, recordLayerHeaderSize));
      result.setRange(recordLayerHeaderSize, result.length, decrypted);
      return result;
    } catch (e) {
      print("[Decrypt] MAC Authentication Failed: $e");
      return null;
    }
  }
}

// String bytesToHex(Uint8List bytes) {
//   return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
// }
