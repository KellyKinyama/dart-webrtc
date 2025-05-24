// class BaseDtlsHandshakeMessage {}

import 'dart:convert';
import 'dart:typed_data';
import 'package:dartls/src/dtls/crypto.dart';

import 'handshake/application.dart';
import 'handshake/change_cipher_spec.dart';
import 'handshake/handshake_context.dart';

import 'handshake/alert.dart';
import 'handshake/handshake.dart';
import 'handshake/handshake_header.dart';
import 'record_layer_header.dart';

class DtlsErrors {
  static const errIncompleteDtlsMessage =
      'data contains incomplete DTLS message';
  static const errUnknownDtlsContentType =
      'data contains unknown DTLS content type';
  static const errUnknownDtlsHandshakeType =
      'data contains unknown DTLS handshake type';
}

class DecodeDtlsMessageResult {
  final RecordLayerHeader? recordHeader;
  final HandshakeHeader? handshakeHeader;
  final dynamic message;
  final int finalOffset;

  DecodeDtlsMessageResult(
      this.recordHeader, this.handshakeHeader, this.message, this.finalOffset);

  static Future<DecodeDtlsMessageResult> decode(
      HandshakeContext context,
      Uint8List buf,
      int offset,
      int arrayLen,
      CipherSuiteId cipherSuite) async {
    if (arrayLen < 1) {
      throw ArgumentError(DtlsErrors.errIncompleteDtlsMessage);
    }

    // print("Header content type: ${ContentType.fromInt(buf[0])}");
    // final recordHeaderOffset = 0;

    final (header, decodedOffset, err) =
        RecordLayerHeader.unmarshal(buf, offset: offset, arrayLen: arrayLen);

    // final data=Uint8List.fromList()

    // print("Record header: $header");

    //print("offset: $offset, decodedOffset: $decodedOffset");
    offset = decodedOffset;

    if (header.epoch < context.clientEpoch) {
      // Ignore incoming message
      print("Header epock: ${header.epoch}");
      offset += header.contentLen;
      return DecodeDtlsMessageResult(null, null, null, offset);
    }

    context.clientEpoch = header.epoch;

    context.protocolVersion = header.protocolVersion;

    Uint8List? decryptedBytes;
    // Uint8List? encryptedBytes;

    if (header.epoch > 0) {
      print("Data arrived encrypted!!!");
      // throw UnimplementedError("Encryption is not yet implemented");

      // Data arrives encrypted, we should decrypt it before.
      if (context.isCipherSuiteInitialized) {
        // encryptedBytes = buf.sublist(offset, offset + header.contentLen);
        offset += header.contentLen;

        if (cipherSuite ==
                CipherSuiteId.Tls_Ecdhe_Ecdsa_With_Aes_128_Gcm_Sha256 ||
            cipherSuite == CipherSuiteId.Tls_Psk_With_Aes_128_Gcm_Sha256) {
          decryptedBytes = await context.gcm.decrypt(buf);
        }

        if (cipherSuite == CipherSuiteId.Tls_Psk_With_Aes_128_Ccm) {
          decryptedBytes = context.ccm.decrypt(buf);
        }
        if (cipherSuite == CipherSuiteId.Tls_Psk_With_Aes_128_Ccm_8) {
          decryptedBytes = context.ccm8.decrypt(buf);
        }
        // 	if err != nil {
        // 		return nil, nil, nil, offset, err
        // 	}
      }

      // Data arrives encrypted, we should decrypt it before.
      // if context.IsCipherSuiteInitialized {
      // 	encryptedBytes = buf[offset : offset+int(header.Length)]
      // 	offset += int(header.Length)
      // 	decryptedBytes, err = context.GCM.Decrypt(header, encryptedBytes)
      // 	if err != nil {
      // 		return nil, nil, nil, offset, err
      // 	}
      // }
      // }
    }

    context.clientEpoch = header.epoch;

    // if (header.contentType != ContentType.content_handshake) {
    print("Content type: ${header.contentType}");
    // }
    switch (header.contentType) {
      case ContentType.content_handshake:
        if (decryptedBytes == null) {
          final offsetBackup = offset;
          final (handshakeHeader, decodedOffset, err) =
              HandshakeHeader.unmarshal(buf, offset, arrayLen);

          // print("handshake header: ${handshakeHeader.handshakeType}");

          offset = decodedOffset;

          if (handshakeHeader.length.value !=
              handshakeHeader.fragmentLength.value) {
            // Ignore fragmented packets
            print('Ignore fragmented packets: ${header.contentType}');
            return DecodeDtlsMessageResult(null, null, null, offset);
          }

          final (result, decodedHandshakeOffset, _) =
              decodeHandshake(header, handshakeHeader, buf, offset, arrayLen);
          offset = decodedHandshakeOffset;

          context.HandshakeMessagesReceived[handshakeHeader.handshakeType] =
              Uint8List.fromList(buf.sublist(offsetBackup));

          return DecodeDtlsMessageResult(
              header, handshakeHeader, result, offset);
        } else {
          offset = 0;

          final (decryptedHeader, decryptedOffset, decryptedErr) =
              RecordLayerHeader.unmarshal(buf,
                  offset: offset, arrayLen: arrayLen);

          offset = decryptedOffset;
          final (handshakeHeader, decodedOffset, err) = HandshakeHeader.decode(
              decryptedBytes, offset, decryptedBytes.length);

          offset = decodedOffset;

          final (result, decoded, er) = decodeHandshake(decryptedHeader,
              handshakeHeader, decryptedBytes, offset, decryptedBytes.length);

          print("Decrypted handshake type: ${handshakeHeader.handshakeType}");

          context.HandshakeMessagesReceived[handshakeHeader.handshakeType] =
              // decryptedBytes;
              decryptedBytes.sublist(decryptedOffset);

          return DecodeDtlsMessageResult(
              header, handshakeHeader, result, decoded + offset);
        }

      case ContentType.content_change_cipher_spec:
        {
          print(" Content type: ${header.contentType}");

          // throw UnimplementedError(
          //     "Content type: ${header.contentType} is not implemented");

          var (changeCipherSpec, decodedOffset, err) =
              ChangeCipherSpec.unmarshal(buf, offset, arrayLen);

          print("Change cipher spec: $changeCipherSpec");

          return DecodeDtlsMessageResult(
              header, null, changeCipherSpec, decodedOffset);
        }

      case ContentType.content_alert:
        final (alert, decodedAlert, _) = Alert.unmarshal(buf, offset, arrayLen);

        return DecodeDtlsMessageResult(header, null, alert, decodedAlert);

      case ContentType.content_application_data:
        {
          offset = 0;

          final (decryptedHeader, decryptedOffset, decryptedErr) =
              RecordLayerHeader.unmarshal(decryptedBytes!,
                  offset: offset, arrayLen: arrayLen);

          offset = decryptedOffset;
          print(
              "Application data: ${utf8.decode(decryptedBytes.sublist(decryptedOffset))}");

          final (appData, decodedApplicationData, _) =
              ApplicationData.unmarshal(buf, offset, decryptedBytes.length);
          return DecodeDtlsMessageResult(
              header, null, appData, decodedApplicationData);
        }

      // throw UnimplementedError("Unhandled content type: ${header.contentType}");

      // throw UnimplementedError("Unhandled content type: ${header.contentType}");
      default:
        {
          throw UnimplementedError(
              "Unhandled content type: ${header.contentType}");
        }
    }

    print("Message: $header");

    return DecodeDtlsMessageResult(null, null, null, offset);
  }

  @override
  String toString() {
    // TODO: implement toString
    return "DtlsMessage(recordHeader: $recordHeader, handshakeHeader: $handshakeHeader, message: $message)";
  }
}

// void main() {
//   HandshakeContext context = HandshakeContext();
//   DecodeDtlsMessageResult.decode(context, rawDtlsMsg, 0, rawDtlsMsg.length);
// }

final rawDtlsMsg = Uint8List.fromList([
  22,
  254,
  253,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  39,
  0,
  127,
  1,
  0,
  0,
  115,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  115,
  254,
  253,
  103,
  146,
  42,
  71,
  152,
  94,
  17,
  98,
  238,
  96,
  121,
  212,
  84,
  208,
  209,
  7,
  127,
  234,
  186,
  105,
  152,
  213,
  72,
  209,
  201,
  212,
  153,
  102,
  93,
  138,
  166,
  111,
  0,
  0,
  0,
  8,
  192,
  43,
  192,
  10,
  192,
  47,
  192,
  20,
  1,
  0,
  0,
  65,
  0,
  13,
  0,
  16,
  0,
  14,
  4,
  3,
  5,
  3,
  6,
  3,
  4,
  1,
  5,
  1,
  6,
  1,
  8,
  7,
  255,
  1,
  0,
  1,
  0,
  0,
  10,
  0,
  8,
  0,
  6,
  0,
  23,
  0,
  29,
  0,
  24,
  0,
  11,
  0,
  2,
  1,
  0,
  0,
  23,
  0,
  0,
  0,
  0,
  0,
  14,
  0,
  12,
  0,
  0,
  9,
  108,
  111,
  99,
  97,
  108,
  104,
  111,
  115,
  116
]);
