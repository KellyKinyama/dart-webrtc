// Encoding and sending of DTLS records (handshake / change_cipher_spec /
// application_data) for the server side.

import 'dart:io';
import 'dart:typed_data';

import '../handshake/handshake.dart';
import '../handshake/handshake_context.dart';
import '../handshake/handshake_header.dart';
import '../record_layer_header.dart';

/// Encapsulates the per-peer record I/O state for the server.
///
/// Owns the epoch / sequence-number bookkeeping and AEAD encryption call
/// for one DTLS association. The actual UDP send is delegated to a
/// [_sendRaw] callback so the same class can be used over different
/// transports / mocks.
class RecordWriter {
  final HandshakeContext context;
  final void Function(List<int> bytes) _sendRaw;

  RecordWriter(
      {required this.context, required void Function(List<int>) sendRaw})
      : _sendRaw = sendRaw;

  /// Marshals [message] (any DTLS message that exposes
  /// `marshal()`, `getContentType()` and — for handshake messages —
  /// `getHandshakeType()`), wraps it in the DTLS record layer, encrypts if
  /// required, and dispatches it to the peer.
  Future<void> send(dynamic message) async {
    final Uint8List body = message.marshal();
    final encoded = BytesBuilder();
    final ContentType contentType = message.getContentType();

    switch (contentType) {
      case ContentType.content_handshake:
        final handshakeHeader = HandshakeHeader(
          handshakeType: message.getHandshakeType(),
          length: Uint24.fromUInt32(body.length),
          messageSequence: context.serverHandshakeSequenceNumber,
          fragmentOffset: Uint24.fromUInt32(0),
          fragmentLength: Uint24.fromUInt32(body.length),
        );
        context.increaseServerHandshakeSequence();
        encoded.add(handshakeHeader.marshal());
        encoded.add(body);
        // Save the handshake message in the transcript map.
        context.HandshakeMessagesSent[message.getHandshakeType()] =
            encoded.toBytes();
        break;
      case ContentType.content_change_cipher_spec:
        encoded.add(body);
        break;
      default:
        encoded.add(body);
    }

    final payload = encoded.toBytes();
    final header = RecordLayerHeader(
      contentType: contentType,
      protocolVersion: ProtocolVersion(254, 253),
      epoch: context.serverEpoch,
      sequenceNumber: context.serverSequenceNumber,
      contentLen: payload.length,
    );

    var record = Uint8List.fromList(header.marshal() + payload);

    if (context.serverEpoch > 0 && context.isCipherSuiteInitialized) {
      record = await context.gcm.encrypt(header, record);
    }

    _sendRaw(record);
    context.increaseServerSequence();
  }
}

/// Convenience helper to build a [RecordWriter] that sends straight to a
/// remote address on a [RawDatagramSocket].
RecordWriter datagramRecordWriter(
  HandshakeContext context,
  RawDatagramSocket socket,
  InternetAddress address,
  int port,
) {
  return RecordWriter(
    context: context,
    sendRaw: (bytes) => socket.send(bytes, address, port),
  );
}
