import 'dart:typed_data';
import 'dtls.dart'; // Assuming common DTLS types are here
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

// Placeholder for HandshakeContext. You'll need to define this based on your Go code.
// For now, it's a minimal class to allow the code to compile.
class HandshakeContext {
  int clientEpoch = 0;
  bool isCipherSuiteInitialized = false;
  // GCM cipher; // Uncomment and define if you have a GCM implementation
}

abstract class BaseDtlsMessage {
  ContentType getContentType();
  Uint8List encode();
  // (int, dynamic) decode(Uint8List buf, int offset, int arrayLen); // Dart doesn't allow static abstract methods
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

/// Decodes a DTLS message from a byte array.
/// Corresponds to Go's `DecodeDtlsMessage` function.
(RecordHeader?, HandshakeHeader?, BaseDtlsMessage?, int, dynamic)
    decodeDtlsMessage(
        HandshakeContext context, Uint8List buf, int offset, int arrayLen) {
  if (arrayLen < 1) {
    return (null, null, null, offset, IncompleteDtlsMessageException());
  }

  final (header, newOffset, headerError) =
      RecordHeader.decode(buf, offset, arrayLen);
  if (headerError != null) {
    return (null, null, null, newOffset, headerError);
  }
  offset = newOffset;

  if (header == null) {
    return (null, null, null, offset, 'RecordHeader is null after decode');
  }

  if (header.epoch < context.clientEpoch) {
    // Ignore incoming message
    offset += header.length;
    return (null, null, null, offset, null);
  }

  context.clientEpoch = header.epoch;

  Uint8List? decryptedBytes;
  if (header.epoch > 0) {
    // Data arrives encrypted, we should decrypt it before.
    if (context.isCipherSuiteInitialized) {
      final encryptedBytes =
          Uint8List.fromList(buf.sublist(offset, offset + header.length));
      offset += header.length;
      // You'll need to implement your GCM decryption here.
      // decryptedBytes = context.cipher.decrypt(header, encryptedBytes);
      // if (decryptedBytes == null) {
      //   return (null, null, null, offset, 'Decryption failed');
      // }
      // For now, assuming decryption makes no changes or is bypassed for unencrypted testing
      decryptedBytes = encryptedBytes;
    }
  }

  HandshakeHeader? handshakeHeader;
  BaseDtlsMessage? message;
  dynamic error;

  switch (header.contentType) {
    case ContentType.handshake:
      if (decryptedBytes == null) {
        final offsetBackup = offset;
        final (hHeader, hOffset, hError) =
            HandshakeHeader.decode(buf, offset, arrayLen);
        if (hError != null) {
          return (null, null, null, hOffset, hError);
        }
        handshakeHeader = hHeader;
        offset = hOffset;

        if (handshakeHeader == null) {
          return (
            null,
            null,
            null,
            offset,
            'HandshakeHeader is null after decode'
          );
        }

        if (handshakeHeader.length.toUint32() !=
            handshakeHeader.fragmentLength.toUint32()) {
          // Ignore fragmented packets
          // logging.warning("Ignore fragmented packets: ${header.contentType}");
          return (
            null,
            null,
            null,
            offset + handshakeHeader.fragmentLength.toUint32(),
            null
          );
        }

        final (msg, msgOffset, msgError) =
            decodeHandshake(header, handshakeHeader, buf, offset, arrayLen);
        message = msg;
        offset = msgOffset;
        error = msgError;
      } else {
        final (hHeader, hOffset, hError) =
            HandshakeHeader.decode(decryptedBytes, 0, decryptedBytes.length);
        if (hError != null) {
          return (null, null, null, offset, hError);
        }
        handshakeHeader = hHeader;

        if (handshakeHeader == null) {
          return (
            null,
            null,
            null,
            offset,
            'HandshakeHeader is null after decryption and decode'
          );
        }

        final (msg, msgOffset, msgError) = decodeHandshake(header,
            handshakeHeader, decryptedBytes, hOffset, decryptedBytes.length);
        message = msg;
        error = msgError;
      }
      break;
    case ContentType.changeCipherSpec:
      // message = ChangeCipherSpec.decode(decryptedBytes ?? Uint8List.fromList(buf.sublist(offset)));
      // if (decryptedBytes == null) {
      //   offset += message.length; // Assuming ChangeCipherSpec has a length
      // }
      // Placeholder: You'll need to implement ChangeCipherSpec decoding
      break;
    case ContentType.alert:
      // message = Alert.decode(decryptedBytes ?? Uint8List.fromList(buf.sublist(offset)));
      // if (decryptedBytes == null) {
      //   offset += message.length; // Assuming Alert has a length
      // }
      // Placeholder: You'll need to implement Alert decoding
      break;
    default:
      error = UnknownDtlsContentTypeException();
      break;
  }

  return (header, handshakeHeader, message, offset, error);
}

/// Decodes a DTLS handshake message based on its type.
/// Corresponds to Go's `decodeHandshake` function.
(BaseDtlsMessage?, int, dynamic) decodeHandshake(RecordHeader header,
    HandshakeHeader handshakeHeader, Uint8List buf, int offset, int arrayLen) {
  BaseDtlsMessage? result;
  dynamic error;

  switch (handshakeHeader.handshakeType) {
    // These need to be actual Dart classes that implement BaseDtlsMessage
    case HandshakeType.clientHello:
      // (result, offset, error) = ClientHello.unmarshal(buf, offset, arrayLen);
      // Placeholder
      result = null; // Replace with actual ClientHello decode
      break;
    case HandshakeType.serverHello:
      // (result, offset, error) = ServerHello.unmarshal(buf, offset, arrayLen);
      // Placeholder
      result = null; // Replace with actual ServerHello decode
      break;
    case HandshakeType.certificate:
      // (result, offset, error) = Certificate.decode(buf, offset, arrayLen);
      // Placeholder
      result = null; // Replace with actual Certificate decode
      break;
    case HandshakeType.serverKeyExchange:
      // (result, offset, error) = ServerKeyExchange.decode(buf, offset, arrayLen);
      // Placeholder
      result = null; // Replace with actual ServerKeyExchange decode
      break;
    case HandshakeType.certificateRequest:
      // (result, offset, error) = CertificateRequest.decode(buf, offset, arrayLen);
      // Placeholder
      result = null; // Replace with actual CertificateRequest decode
      break;
    case HandshakeType.serverHelloDone:
      // (result, offset, error) = ServerHelloDone.decode(buf, offset, arrayLen);
      // Placeholder
      result = null; // Replace with actual ServerHelloDone decode
      break;
    case HandshakeType.clientKeyExchange:
      // (result, offset, error) = ClientKeyExchange.decode(buf, offset, arrayLen);
      // Placeholder
      result = null; // Replace with actual ClientKeyExchange decode
      break;
    case HandshakeType.finished:
      // (result, offset, error) = Finished.decode(buf, offset, arrayLen);
      // Placeholder
      result = null; // Replace with actual Finished decode
      break;
    case HandshakeType.helloVerifyRequest:
      final (hvr, hvrOffset, hvrError) =
          HelloVerifyRequest.decode(buf, offset, arrayLen);
      result = hvr;
      offset = hvrOffset;
      error = hvrError;
      break;
    default:
      error = UnknownDtlsHandshakeTypeException();
      break;
  }

  return (result, offset, error);
}
