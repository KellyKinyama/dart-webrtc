// Builds the canonical handshake message transcript used as input to the
// PRF for both the Extended Master Secret and the Finished verify_data.
//
// The transcript is the concatenation of the raw handshake messages
// (handshake header + body) in this exact order, with the
// HelloVerifyRequest exchange and the first ClientHello dropped per
// RFC 6347 §4.2.1:
//
//   ClientHello        (received)   <- the cookie-bearing one
//   ServerHello        (sent)
//   Certificate        (sent)
//   ServerKeyExchange  (sent)
//   ServerHelloDone    (sent)
//   ClientKeyExchange  (received)
//   [Finished          (received)]   only when including received Finished

import 'dart:typed_data';

import '../handshake/handshake.dart';
import '../handshake/handshake_context.dart';

/// Concatenates the handshake transcript from a context.
///
/// [includeReceivedFinished] = true is used when computing the verify_data
/// the server expects in the *outgoing* (server) Finished, after the client
/// Finished has been received.
Uint8List buildHandshakeTranscript(
  HandshakeContext context, {
  bool includeReceivedFinished = false,
}) {
  final out = BytesBuilder();
  _append(out, context.HandshakeMessagesReceived, HandshakeType.client_hello);
  _append(out, context.HandshakeMessagesSent, HandshakeType.server_hello);
  _append(out, context.HandshakeMessagesSent, HandshakeType.certificate);
  _append(
      out, context.HandshakeMessagesSent, HandshakeType.server_key_exchange);
  _append(out, context.HandshakeMessagesSent, HandshakeType.server_hello_done);
  _append(out, context.HandshakeMessagesReceived,
      HandshakeType.client_key_exchange);
  if (includeReceivedFinished) {
    _append(out, context.HandshakeMessagesReceived, HandshakeType.finished);
  }
  return out.toBytes();
}

void _append(
  BytesBuilder out,
  Map<HandshakeType, Uint8List> messages,
  HandshakeType type,
) {
  final msg = messages[type];
  if (msg == null) {
    throw StateError('transcript missing handshake message: $type');
  }
  out.add(msg);
}
