import 'dart:convert';
import 'dart:typed_data';
import 'alert.dart';
import 'application.dart';
import 'change_cipher_spec.dart';
import 'client_hello.dart';
import 'client_key_exchange.dart';
import 'dtls.dart'; // Assuming common DTLS types are here
import 'finished.dart';
import 'handshake_context.dart';
import 'handshake_header.dart'; // For HandshakeHeader, HandshakeType, Uint24
import 'record_header.dart'; // For RecordHeader, ContentType
import 'hello_verify_request.dart'; // For HelloVerifyRequest
// import 'package:dtls/src/handshake/client_hello.dart'; // Assuming this exists or will be created
// import 'package:dtls/src/handshake/server_hello.dart'; // Assuming this exists or will be created
// import 'package:dtls/src/handshake/certificate.dart'; // Assuming this exists or will be created
// import 'package:dtls/src/handshake/server_key_exchange.dart'; // Assuming this exists or will be created
// import 'package:dtls/src/handshake/certificate_request.dart'; // Assuming this exists or will be created
// import 'package:dtls/src/handshake/server_hello_done.dart'; // Assuming this exists or will be created
// import 'package:dtls/src/handshake/client_key_exchange.dart'; // Assuming this exists or will be created
// import 'package:dtls/src/handshake/finished.dart'; // Assuming this exists or will be created
// import 'package:dtls/src/handshake/change_cipher_spec.dart'; // Assuming this exists or will be created
// import 'package:dtls/src/handshake/alert.dart'; // Assuming this exists or will be created

abstract class BaseDtlsMessage {
  ContentType getContentType();
  Uint8List encode();
  // (int, dynamic) decode(Uint8List buf, int offset, int arrayLen); // Dart doesn't allow static abstract methods
  @override
  String toString();
}

abstract class BaseDtlsHandshakeMessage extends BaseDtlsMessage {
  HandshakeType getHandshakeType();
}

class IncompleteDtlsMessageException implements Exception {
  final String message;
  IncompleteDtlsMessageException(
      [this.message = 'Data contains incomplete DTLS message']);
  @override
  String toString() => 'IncompleteDtlsMessageException: $message';
}

class UnknownDtlsContentTypeException implements Exception {
  final String message;
  UnknownDtlsContentTypeException(
      [this.message = 'Data contains unknown DTLS content type']);
  @override
  String toString() => 'UnknownDtlsContentTypeException: $message';
}

class UnknownDtlsHandshakeTypeException implements Exception {
  final String message;
  UnknownDtlsHandshakeTypeException(
      [this.message = 'Data contains unknown DTLS handshake type']);
  @override
  String toString() => 'UnknownDtlsHandshakeTypeException: $message';
}

bool isDtlsPacket(Uint8List buf, int offset, int arrayLen) {
  return arrayLen > 0 && buf[offset] >= 20 && buf[offset] <= 63;
}

Future<(RecordHeader?, HandshakeHeader?, dynamic, int)> decodeDtlsMessage(
    HandshakeContext context, Uint8List buf, int offset, int arrayLen) async {
  if (arrayLen < 1) {
    throw ArgumentError(IncompleteDtlsMessageException);
  }

  // print("Header content type: ${ContentType.fromInt(buf[0])}");
  // final recordHeaderOffset = 0;

  final (header, decodedOffset, err) =
      RecordHeader.decode(buf, offset, arrayLen);

  // final data=Uint8List.fromList()

  // print("Record header: $header");

  //print("offset: $offset, decodedOffset: $decodedOffset");
  offset = decodedOffset;

  if (header.epoch < context.clientEpoch) {
    // Ignore incoming message
    print("Header epock: ${header.epoch}");
    offset += header.length;
    return (null, null, null, offset);
  }

  context.clientEpoch = header.epoch;

  context.protocolVersion = header.version;

  Uint8List? decryptedBytes;
  // Uint8List? encryptedBytes;

  if (header.epoch > 0) {
    print("Data arrived encrypted!!!");
    // throw UnimplementedError("Encryption is not yet implemented");

    // Data arrives encrypted, we should decrypt it before.
    if (context.isCipherSuiteInitialized) {
      // encryptedBytes = buf.sublist(offset, offset + header.contentLen);
      offset += header.length;

      // if (cipherSuite ==
      //         CipherSuiteId.Tls_Ecdhe_Ecdsa_With_Aes_128_Gcm_Sha256 ||
      //     cipherSuite == CipherSuiteId.Tls_Psk_With_Aes_128_Gcm_Sha256) {
      decryptedBytes = await context.gcm.decrypt(buf);
      // }

      // if (cipherSuite == CipherSuiteId.Tls_Psk_With_Aes_128_Ccm) {
      //   decryptedBytes = context.ccm.decrypt(buf);
      // }
      // if (cipherSuite == CipherSuiteId.Tls_Psk_With_Aes_128_Ccm_8) {
      //   decryptedBytes = context.ccm8.decrypt(buf);
      // }
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
    case ContentType.handshake:
      if (decryptedBytes == null) {
        final offsetBackup = offset;
        final (handshakeHeader, decodedOffset) =
            HandshakeHeader.decode(buf, offset, arrayLen);

        // print("handshake header: ${handshakeHeader.handshakeType}");

        offset = decodedOffset;

        if (handshakeHeader.length.toUint32() !=
            handshakeHeader.fragmentLength.toUint32()) {
          // Ignore fragmented packets
          print('Ignore fragmented packets: ${header.contentType}');
          return (null, null, null, offset);
        }

        final (result, decodedHandshakeOffset) =
            decodeHandshake(header, handshakeHeader, buf, offset, arrayLen);
        offset = decodedHandshakeOffset;

        context.handshakeMessagesReceived[handshakeHeader.handshakeType] =
            Uint8List.fromList(buf.sublist(offsetBackup));

        return (header, handshakeHeader, result!, offset);
      } else {
        offset = 0;

        final (decryptedHeader, decryptedOffset, decryptedErr) =
            RecordHeader.decode(buf, offset, arrayLen);

        offset = decryptedOffset;
        final (handshakeHeader, decodedOffset) = HandshakeHeader.decode(
            decryptedBytes, offset, decryptedBytes.length);

        offset = decodedOffset;

        final (result, decoded) = decodeHandshake(decryptedHeader,
            handshakeHeader, decryptedBytes, offset, decryptedBytes.length);

        print("Decrypted handshake type: ${handshakeHeader.handshakeType}");

        context.handshakeMessagesReceived[handshakeHeader.handshakeType] =
            // decryptedBytes;
            decryptedBytes.sublist(decryptedOffset);

        return (header, handshakeHeader!, result!, decoded + offset);
      }

    case ContentType.changeCipherSpec:
      {
        print(" Content type: ${header.contentType}");

        // throw UnimplementedError(
        //     "Content type: ${header.contentType} is not implemented");

        var (changeCipherSpec, decodedOffset, err) =
            ChangeCipherSpec.unmarshal(buf, offset, arrayLen);

        print("Change cipher spec: $changeCipherSpec");

        return (header, null, changeCipherSpec, decodedOffset);
      }

    case ContentType.alert:
      final (alert, decodedAlert, _) = Alert.unmarshal(buf, offset, arrayLen);

      return (header, null, alert, decodedAlert);

    case ContentType.applicationData:
      {
        offset = 0;

        final (decryptedHeader, decryptedOffset, decryptedErr) =
            RecordHeader.decode(decryptedBytes!, offset, arrayLen);

        offset = decryptedOffset;
        print(
            "Application data: ${utf8.decode(decryptedBytes.sublist(decryptedOffset))}");

        final (appData, decodedApplicationData, _) =
            ApplicationData.unmarshal(buf, offset, decryptedBytes.length);
        return (header, null, appData, decodedApplicationData);
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

  return (null, null, null, offset);
}

/// Decodes a DTLS message from a byte array.
/// Corresponds to Go's `DecodeDtlsMessage` function.
// Future<(RecordHeader?, HandshakeHeader?, dynamic, int)> decodeDtlsMessage(
// // (RecordHeader?, HandshakeHeader?, BaseDtlsMessage?, int) decodeDtlsMessage(
//     HandshakeContext context,
//     Uint8List buf,
//     int offset,
//     int arrayLen) async {
//   if (arrayLen < 1) {
//     // return (null, null, null, offset, IncompleteDtlsMessageException());
//     throw IncompleteDtlsMessageException;
//   }

//   final (header, newOffset, headerError) =
//       RecordHeader.decode(buf, offset, arrayLen);
//   if (headerError != null) {
//     // return (null, null, null, newOffset, headerError);
//     throw headerError;
//   }
//   offset = newOffset;

//   if (header == null) {
//     // return (null, null, null, offset, 'RecordHeader is null after decode');
//     throw Exception('RecordHeader is null after decode');
//   }

//   if (header.epoch < context.clientEpoch) {
//     // Ignore incoming message
//     offset += header.length;
//     return (null, null, null, offset);
//   }

//   context.clientEpoch = header.epoch;

//   Uint8List? decryptedBytes;
//   if (header.epoch > 0) {
//     // Data arrives encrypted, we should decrypt it before.
//     if (context.isCipherSuiteInitialized) {
//       print("Data arrived encrypted!!!");
//       throw Exception("Data arrived encrypted");
//       offset += header.length;
//       // You'll need to implement your GCM decryption here.
//       // decryptedBytes = context.cipher.decrypt(header, encryptedBytes);
//       // if (decryptedBytes == null) {
//       //   return (null, null, null, offset, 'Decryption failed');
//       // }
//       // For now, assuming decryption makes no changes or is bypassed for unencrypted testing
//       decryptedBytes = await context.gcm.decrypt(buf);
//     }
//   }

//   HandshakeHeader? handshakeHeader;
//   dynamic message;

//   switch (header.contentType) {
//     case ContentType.handshake:
//       if (decryptedBytes == null) {
//         final offsetBackup = offset;
//         final (hHeader, hOffset) =
//             HandshakeHeader.decode(buf, offset, arrayLen);

//         handshakeHeader = hHeader;
//         offset = hOffset;

//         if (handshakeHeader == null) {
//           // return (
//           //   null,
//           //   null,
//           //   null,
//           //   offset,
//           //   'HandshakeHeader is null after decode'
//           // );

//           throw Exception('HandshakeHeader is null after decode');
//         }

//         if (handshakeHeader.length.toUint32() !=
//             handshakeHeader.fragmentLength.toUint32()) {
//           // Ignore fragmented packets
//           // logging.warning("Ignore fragmented packets: ${header.contentType}");
//           return (
//             null,
//             null,
//             null,
//             offset + handshakeHeader.fragmentLength.toUint32()
//           );
//         }

//         final (msg, msgOffset) =
//             decodeHandshake(header, handshakeHeader, buf, offset, arrayLen);
//         print("Handshake message: $msg");

//         context.handshakeMessagesReceived[handshakeHeader.handshakeType] =
//             Uint8List.fromList(buf.sublist(offsetBackup));

//         message = msg;
//         offset = msgOffset;
//         if (message == null) {
//           throw Exception("Message is null");
//         }
//       } else {
//         final (hHeader, hOffset) =
//             HandshakeHeader.decode(decryptedBytes, 0, decryptedBytes.length);

//         handshakeHeader = hHeader;

//         if (handshakeHeader == null) {
//           // return (
//           //   null,
//           //   null,
//           //   null,
//           //   offset,
//           //   'HandshakeHeader is null after decryption and decode'
//           // );
//           throw Exception(
//               'HandshakeHeader is null after decryption and decode');
//         }

//         final (msg, msgOffset) = decodeHandshake(header, handshakeHeader,
//             decryptedBytes, hOffset, decryptedBytes.length);
//         message = msg;
//         if (message == null) {
//           throw Exception("Message is null");
//         }
//       }
//       break;
//     case ContentType.changeCipherSpec:
//       // message = ChangeCipherSpec.decode(decryptedBytes ?? Uint8List.fromList(buf.sublist(offset)));
//       // if (decryptedBytes == null) {
//       //   offset += message.length; // Assuming ChangeCipherSpec has a length
//       // }
//       // Placeholder: You'll need to implement ChangeCipherSpec decoding  // if (decryptedBytes == null) {
//       //   offset += message.length; // Assuming ChangeCipherSpec has a length
//       // }
//       // Placeholder: You'll need to implement ChangeCipherSpec decoding
//       var (changeCipherSpec, decodedOffset, err) =
//           ChangeCipherSpec.unmarshal(buf, offset, arrayLen);
//       print("Change cipher spec: $changeCipherSpec");
//       break;
//     case ContentType.alert:
//       // message = Alert.decode(buf, offset, arrayLen);
//       final (alert, decodedAlert, _) = Alert.unmarshal(buf, offset, arrayLen);
//       // decryptedBytes ?? Uint8List.fromList(buf.sublist(offset)));
//       // if (decryptedBytes == null) {
//       //   offset += message.length; // Assuming Alert has a length
//       // }
//       // Placeholder: You'll need to implement Alert decoding
//       throw UnimplementedError("$alert");
//       break;
//     default:
//       throw UnknownDtlsContentTypeException();
//       break;
//   }

//   return (header, handshakeHeader, message, offset);
// }

/// Decodes a DTLS handshake message based on its type.
/// Corresponds to Go's `decodeHandshake` function.
(dynamic, int) decodeHandshake(RecordHeader header,
    HandshakeHeader handshakeHeader, Uint8List buf, int offset, int arrayLen) {
  var result;
  print("Handshake type: ${handshakeHeader.handshakeType}");
  switch (handshakeHeader.handshakeType) {
    // These need to be actual Dart classes that implement BaseDtlsMessage
    case HandshakeType.clientHello:
      (result, offset) = ClientHello.unmarshal(buf, offset, arrayLen);
      // Placeholder
      // result = null; // Replace with actual ClientHello decode
      break;
    case HandshakeType.serverHello:
      // (result, offset, error) = ServerHello.unmarshal(buf, offset, arrayLen);
      // Placeholder
      throw UnimplementedError("${handshakeHeader.handshakeType}");
      result = null; // Replace with actual ServerHello decode
      break;
    case HandshakeType.certificate:
      // (result, offset, error) = Certificate.decode(buf, offset, arrayLen);
      // Placeholder
      throw UnimplementedError("${handshakeHeader.handshakeType}");
      result = null; // Replace with actual Certificate decode
      break;
    case HandshakeType.serverKeyExchange:
      // (result, offset, error) = ServerKeyExchange.decode(buf, offset, arrayLen);
      // Placeholder
      throw UnimplementedError("${handshakeHeader.handshakeType}");
      result = null; // Replace with actual ServerKeyExchange decode
      break;
    case HandshakeType.certificateRequest:
      // (result, offset, error) = CertificateRequest.decode(buf, offset, arrayLen);
      // Placeholder
      throw UnimplementedError("${handshakeHeader.handshakeType}");
      result = null; // Replace with actual CertificateRequest decode
      break;
    case HandshakeType.serverHelloDone:
      // (result, offset, error) = ServerHelloDone.decode(buf, offset, arrayLen);
      // Placeholder
      result = null; // Replace with actual ServerHelloDone decode
      throw UnimplementedError("${handshakeHeader.handshakeType}");
      break;
    case HandshakeType.clientKeyExchange:
      (result, offset) = ClientKeyExchange.decode(buf, offset, arrayLen);
      // Placeholder
      // result = null; // Replace with actual ClientKeyExchange decode
      break;
    case HandshakeType.finished:
      (result, offset) = Finished.decode(buf, offset, arrayLen);
      // Placeholder
      // result = null; // Replace with actual Finished decode
      // throw UnimplementedError("${handshakeHeader.handshakeType}");
      break;
    case HandshakeType.helloVerifyRequest:
      final (hvr, hvrOffset, hvrError) =
          HelloVerifyRequest.decode(buf, offset, arrayLen);
      result = hvr;
      offset = hvrOffset;
      break;
    default:
      throw UnknownDtlsHandshakeTypeException();
  }

  return (result, offset);
}

// void main() {
//   HandshakeContext context = HandshakeContext();
//   final decodeDtlsMsg =
//       decodeDtlsMessage(context, rawDtlsMsg, 0, rawDtlsMsg.length);
//   print("Decoded DTLS Message: $decodeDtlsMsg");
// }

final rawDtlsMsg = Uint8List.fromList([
  22,
  254,
  255,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
  160,
  1,
  0,
  0,
  148,
  0,
  1,
  0,
  0,
  0,
  0,
  0,
  148,
  254,
  253,
  81,
  38,
  10,
  38,
  219,
  97,
  229,
  104,
  36,
  182,
  33,
  212,
  13,
  194,
  113,
  65,
  211,
  29,
  187,
  120,
  40,
  8,
  54,
  56,
  81,
  97,
  121,
  161,
  175,
  132,
  106,
  246,
  0,
  20,
  172,
  189,
  117,
  180,
  188,
  4,
  202,
  159,
  66,
  4,
  77,
  113,
  39,
  0,
  99,
  149,
  97,
  137,
  122,
  117,
  0,
  22,
  192,
  43,
  192,
  47,
  204,
  169,
  204,
  168,
  192,
  9,
  192,
  19,
  192,
  10,
  192,
  20,
  0,
  156,
  0,
  47,
  0,
  53,
  1,
  0,
  0,
  64,
  0,
  13,
  0,
  20,
  0,
  18,
  4,
  3,
  8,
  4,
  4,
  1,
  5,
  3,
  8,
  5,
  5,
  1,
  8,
  6,
  6,
  1,
  2,
  1,
  255,
  1,
  0,
  1,
  0,
  0,
  11,
  0,
  2,
  1,
  0,
  0,
  14,
  0,
  9,
  0,
  6,
  0,
  1,
  0,
  8,
  0,
  7,
  0,
  0,
  10,
  0,
  8,
  0,
  6,
  0,
  29,
  0,
  23,
  0,
  24,
  0,
  23,
  0,
  0
]);
