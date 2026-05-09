// Browser-shaped `RTCDataChannel` skeleton. The wire protocol (SCTP over
// DTLS) is not implemented; this exists so call sites can be written
// against the W3C surface (`createDataChannel`, `onDataChannel`,
// `onMessage`, `onOpen`, `onClose`, `send`).
//
// Once the SCTP layer lands the data channel will be hooked into the
// shared DTLS transport; the public API stays the same.
//
// https://www.w3.org/TR/webrtc/#rtcdatachannel

import 'dart:async';
import 'dart:typed_data';

/// Lifecycle states.
enum RTCDataChannelState { connecting, open, closing, closed }

/// Init-time options, mirroring `RTCDataChannelInit`.
class RTCDataChannelInit {
  final bool ordered;
  final int? maxPacketLifeTime;
  final int? maxRetransmits;
  final String protocol;
  final bool negotiated;
  final int? id;

  const RTCDataChannelInit({
    this.ordered = true,
    this.maxPacketLifeTime,
    this.maxRetransmits,
    this.protocol = '',
    this.negotiated = false,
    this.id,
  });
}

/// Message flavour passed to [RTCDataChannel.onMessage].
class RTCDataChannelMessage {
  /// Either a `String` (text frame) or a `Uint8List` (binary frame).
  final Object data;
  const RTCDataChannelMessage(this.data);

  bool get isBinary => data is Uint8List;
  String get text => data as String;
  Uint8List get binary => data as Uint8List;
}

/// Browser-shaped data channel. The send path currently buffers locally
/// and replays into [onMessage] on the same channel — useful for testing
/// signaling integrations end-to-end without the SCTP wire format.
class RTCDataChannel {
  final String label;
  final RTCDataChannelInit init;
  RTCDataChannelState _state = RTCDataChannelState.connecting;
  int _bufferedAmount = 0;

  /// Fired when the channel transitions to [RTCDataChannelState.open].
  void Function()? onOpen;

  /// Fired when the channel closes.
  void Function()? onClose;

  /// Fired for each inbound message.
  void Function(RTCDataChannelMessage message)? onMessage;

  /// Fired on transport error.
  void Function(Object error)? onError;

  RTCDataChannel(this.label, [RTCDataChannelInit? init])
      : init = init ?? const RTCDataChannelInit();

  RTCDataChannelState get readyState => _state;
  int get bufferedAmount => _bufferedAmount;

  /// Mark the channel as open. Called by the owning [RTCPeerConnection]
  /// once the underlying transport is ready.
  void markOpen() {
    if (_state == RTCDataChannelState.open ||
        _state == RTCDataChannelState.closed) return;
    _state = RTCDataChannelState.open;
    scheduleMicrotask(() => onOpen?.call());
  }

  /// Send a text frame.
  void send(String text) {
    _checkOpen();
    _deliverLocal(RTCDataChannelMessage(text));
  }

  /// Send a binary frame.
  void sendBinary(Uint8List bytes) {
    _checkOpen();
    _deliverLocal(RTCDataChannelMessage(bytes));
  }

  /// Inject an inbound message (used by the transport).
  void deliver(RTCDataChannelMessage message) {
    if (_state != RTCDataChannelState.open) return;
    scheduleMicrotask(() => onMessage?.call(message));
  }

  void close() {
    if (_state == RTCDataChannelState.closed ||
        _state == RTCDataChannelState.closing) {
      return;
    }
    _state = RTCDataChannelState.closing;
    scheduleMicrotask(() {
      _state = RTCDataChannelState.closed;
      onClose?.call();
    });
  }

  void _deliverLocal(RTCDataChannelMessage m) {
    final size = m.isBinary ? m.binary.length : m.text.length;
    _bufferedAmount += size;
    scheduleMicrotask(() {
      _bufferedAmount -= size;
      // Without SCTP wired up, loop back so paired channels connected via
      // the peer's `onDataChannel` see the message immediately.
      onMessage?.call(m);
    });
  }

  void _checkOpen() {
    if (_state != RTCDataChannelState.open) {
      throw StateError('RTCDataChannel(label=$label) is in $_state');
    }
  }
}
