// Encoding and sending of DTLS records (handshake / change_cipher_spec /
// application_data) for the server side.
//
// Supports DTLS handshake-message fragmentation (RFC 6347 §4.2.3): when a
// handshake message body exceeds [maxHandshakeFragmentLength], the body is
// split across multiple records that share the same `message_seq` and
// `length`, each carrying a different `fragment_offset` / `fragment_length`.
// The transcript map (`HandshakeMessagesSent`) always stores the canonical
// *un-fragmented* form (header with `fragment_offset=0`, full body), so
// the verify_data PRF input matches what the peer sees once it
// reassembles.

import 'dart:io';
import 'dart:typed_data';

import '../handshake/handshake.dart';
import '../handshake/handshake_context.dart';
import '../handshake/handshake_header.dart';
import '../record_layer_header.dart';

/// Default maximum number of handshake-body bytes per DTLS record.
///
/// Sized to leave headroom for the IP (20 / 40), UDP (8) and DTLS record
/// (13) headers plus the AEAD overhead (8-byte explicit nonce + 16-byte
/// tag) under a typical 1500-byte Ethernet MTU.
const int defaultMaxHandshakeFragmentLength = 1200;

/// Encapsulates the per-peer record I/O state for the server.
///
/// Owns the epoch / sequence-number bookkeeping and AEAD encryption call
/// for one DTLS association. The actual UDP send is delegated to a
/// [_sendRaw] callback so the same class can be used over different
/// transports / mocks.
class RecordWriter {
  final HandshakeContext context;
  final void Function(List<int> bytes) _sendRaw;

  /// Maximum number of handshake-body bytes per outgoing record. Larger
  /// handshake messages will be split into multiple fragmented records.
  int maxHandshakeFragmentLength;

  RecordWriter({
    required this.context,
    required void Function(List<int>) sendRaw,
    this.maxHandshakeFragmentLength = defaultMaxHandshakeFragmentLength,
  }) : _sendRaw = sendRaw;

  /// Marshals [message] (any DTLS message that exposes
  /// `marshal()`, `getContentType()` and — for handshake messages —
  /// `getHandshakeType()`), wraps it in the DTLS record layer, encrypts if
  /// required, and dispatches it to the peer.
  ///
  /// For handshake messages whose body exceeds
  /// [maxHandshakeFragmentLength], the message is sent as multiple
  /// fragmented DTLS records.
  Future<void> send(dynamic message) async {
    final Uint8List body = message.marshal();
    final ContentType contentType = message.getContentType();

    if (contentType == ContentType.content_handshake) {
      await _sendHandshake(message, body);
      return;
    }

    // Non-handshake records: always single, never fragmented.
    await _sendRecord(contentType, body);
  }

  Future<void> _sendHandshake(dynamic message, Uint8List body) async {
    final hsType = message.getHandshakeType();
    final messageSeq = context.serverHandshakeSequenceNumber;

    // Always store the canonical (un-fragmented) handshake bytes in the
    // transcript map, regardless of how many fragments we end up sending.
    final canonicalHeader = HandshakeHeader(
      handshakeType: hsType,
      length: Uint24.fromUInt32(body.length),
      messageSequence: messageSeq,
      fragmentOffset: Uint24.fromUInt32(0),
      fragmentLength: Uint24.fromUInt32(body.length),
    );
    final canonical = BytesBuilder()
      ..add(canonicalHeader.marshal())
      ..add(body);
    context.HandshakeMessagesSent[hsType] = canonical.toBytes();

    // The handshake message_seq advances exactly once per logical message,
    // not per fragment.
    context.increaseServerHandshakeSequence();

    // Single-record fast path.
    if (body.length <= maxHandshakeFragmentLength) {
      await _sendRecord(
        ContentType.content_handshake,
        Uint8List.fromList(canonicalHeader.marshal() + body),
      );
      return;
    }

    // Fragment the body across multiple records.
    var offset = 0;
    while (offset < body.length) {
      final remaining = body.length - offset;
      final fragLen = remaining < maxHandshakeFragmentLength
          ? remaining
          : maxHandshakeFragmentLength;
      final fragHeader = HandshakeHeader(
        handshakeType: hsType,
        length: Uint24.fromUInt32(body.length),
        messageSequence: messageSeq,
        fragmentOffset: Uint24.fromUInt32(offset),
        fragmentLength: Uint24.fromUInt32(fragLen),
      );
      final payload = BytesBuilder()
        ..add(fragHeader.marshal())
        ..add(body.sublist(offset, offset + fragLen));
      await _sendRecord(ContentType.content_handshake, payload.toBytes());
      // Yield to the event loop between fragments. On loopback, sending
      // many UDP datagrams back-to-back without yielding can overrun the
      // kernel receive buffer on the peer before its read callback runs.
      // A 1ms delay (rather than Duration.zero) ensures the I/O event
      // loop actually services pending receives.
      await Future<void>.delayed(const Duration(milliseconds: 1));
      offset += fragLen;
    }
  }

  Future<void> _sendRecord(ContentType contentType, Uint8List payload) async {
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
  int port, {
  int maxHandshakeFragmentLength = defaultMaxHandshakeFragmentLength,
}) {
  return RecordWriter(
    context: context,
    sendRaw: (bytes) => socket.send(bytes, address, port),
    maxHandshakeFragmentLength: maxHandshakeFragmentLength,
  );
}
