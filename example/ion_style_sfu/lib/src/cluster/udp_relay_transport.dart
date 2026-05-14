// Phase 10 — production UDP transport for SFU-to-SFU relay traffic.
//
// Frames a single UDP datagram per RTP/RTCP/control message. Each
// datagram is prefixed with a 12-byte header:
//
//   bytes 0..3   magic 'i','o','n','r'  (0x696f6e72)
//   byte  4      version  (0x01)
//   byte  5      message type  (0=control, 1=rtp, 2=rtcp)
//   byte  6..7   reserved (0)
//   byte  8..11  payload-length (big-endian, sanity check)
//
// Followed by [payload]. When [secret] is non-null, an HMAC-SHA256
// (truncated to 16 bytes) of `header || payload` is appended as a
// trailing tag — the receiver verifies it before passing anything to
// the relay. Replay protection is intentionally light (no per-packet
// nonce); rely on a unique secret per cluster and an external network
// boundary for stronger guarantees.
//
// The transport multiplexes many remote relays on a single UDP socket
// keyed by `InternetAddress + port`. Each remote address pairs with
// one [_UdpRelayEndpoint] (a [RelayTransport] facade).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../relay/relay.dart';

/// Magic prefix `'ionr'` (ion-relay). Cheap mis-routed packet filter.
const int _frameMagic = 0x696f6e72;
const int _frameVersion = 0x01;

const int _typeControl = 0;
const int _typeRtp = 1;
const int _typeRtcp = 2;

const int _headerLen = 12;
const int _hmacLen = 16;

/// Multiplexed UDP socket carrying one or more [_UdpRelayEndpoint]s.
/// Construct one per SFU; spawn endpoints with [endpointTo] for each
/// remote SFU we cascade with.
class UdpRelayHub {
  final RawDatagramSocket _socket;
  final List<int>? _secret;
  final void Function(Object error, StackTrace stack)? onError;

  /// remote `host:port` → endpoint. Endpoints are created on demand.
  final Map<String, _UdpRelayEndpoint> _endpoints = {};

  /// Optional callback fired when a packet arrives from a peer we have
  /// no endpoint for. The orchestrator uses this to lazily create
  /// endpoints for inbound cascades.
  void Function(InternetAddress addr, int port, int type, Uint8List payload)?
      onUnknownPeer;

  bool _closed = false;

  UdpRelayHub._(this._socket, this._secret, this.onError) {
    _socket.listen(_onEvent, onError: (e, st) {
      onError?.call(e, st as StackTrace);
    });
  }

  /// Bind a hub on [bindAddress]:[port]. [secret] enables HMAC
  /// authentication; recommended in any deployment where the relay
  /// network is not strictly private.
  static Future<UdpRelayHub> bind({
    required InternetAddress bindAddress,
    required int port,
    String? secret,
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    final sock = await RawDatagramSocket.bind(bindAddress, port);
    return UdpRelayHub._(
      sock,
      secret == null ? null : utf8.encode(secret),
      onError,
    );
  }

  /// Local UDP port the hub is bound to.
  int get port => _socket.port;

  /// Get-or-create the endpoint for [host]:[port].
  RelayTransport endpointTo(InternetAddress host, int port) {
    final key = '${host.address}:$port';
    return _endpoints.putIfAbsent(
      key,
      () => _UdpRelayEndpoint(this, host, port),
    );
  }

  /// Drop the endpoint for [host]:[port] (if any). Idempotent.
  Future<void> closeEndpoint(InternetAddress host, int port) async {
    final key = '${host.address}:$port';
    final ep = _endpoints.remove(key);
    if (ep != null) await ep._closeInternal();
  }

  /// Live endpoints (snapshot).
  Iterable<RelayTransport> get endpoints => _endpoints.values;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final all = _endpoints.values.toList();
    _endpoints.clear();
    for (final ep in all) {
      await ep._closeInternal();
    }
    _socket.close();
  }

  // ----- I/O ---------------------------------------------------------

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket.receive();
    if (dg == null) return;
    final type = _decode(dg.data);
    if (type == null) return;
    final key = '${dg.address.address}:${dg.port}';
    final ep = _endpoints[key];
    if (ep != null) {
      ep._dispatch(type.$1, type.$2);
      return;
    }
    final cb = onUnknownPeer;
    if (cb != null) {
      cb(dg.address, dg.port, type.$1, type.$2);
    }
  }

  /// Decodes [data] into (type, payload). Returns null on framing /
  /// HMAC failure.
  (int, Uint8List)? _decode(Uint8List data) {
    if (data.length < _headerLen) return null;
    final magic = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
    if (magic != _frameMagic) return null;
    if (data[4] != _frameVersion) return null;
    final type = data[5];
    if (type != _typeControl && type != _typeRtp && type != _typeRtcp) {
      return null;
    }
    final declaredLen =
        (data[8] << 24) | (data[9] << 16) | (data[10] << 8) | data[11];
    final secret = _secret;
    final payloadEnd = secret == null ? data.length : data.length - _hmacLen;
    if (payloadEnd < _headerLen) return null;
    final actualLen = payloadEnd - _headerLen;
    if (actualLen != declaredLen) return null;
    if (secret != null) {
      final mac = Hmac(sha256, secret)
          .convert(data.sublist(0, payloadEnd))
          .bytes
          .sublist(0, _hmacLen);
      final got = data.sublist(payloadEnd, payloadEnd + _hmacLen);
      if (!_constantTimeEq(mac, got)) return null;
    }
    final payload = Uint8List.sublistView(data, _headerLen, payloadEnd);
    return (type, Uint8List.fromList(payload));
  }

  void _send(InternetAddress host, int port, int type, Uint8List payload) {
    if (_closed) return;
    final secret = _secret;
    final totalLen =
        _headerLen + payload.length + (secret == null ? 0 : _hmacLen);
    final out = Uint8List(totalLen);
    out[0] = (_frameMagic >> 24) & 0xff;
    out[1] = (_frameMagic >> 16) & 0xff;
    out[2] = (_frameMagic >> 8) & 0xff;
    out[3] = _frameMagic & 0xff;
    out[4] = _frameVersion;
    out[5] = type;
    final pl = payload.length;
    out[8] = (pl >> 24) & 0xff;
    out[9] = (pl >> 16) & 0xff;
    out[10] = (pl >> 8) & 0xff;
    out[11] = pl & 0xff;
    out.setRange(_headerLen, _headerLen + pl, payload);
    if (secret != null) {
      final macInput = Uint8List.sublistView(out, 0, _headerLen + pl);
      final mac = Hmac(sha256, secret).convert(macInput).bytes;
      out.setRange(_headerLen + pl, totalLen, mac.sublist(0, _hmacLen));
    }
    _socket.send(out, host, port);
  }

  static bool _constantTimeEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

class _UdpRelayEndpoint implements RelayTransport {
  final UdpRelayHub _hub;
  final InternetAddress _host;
  final int _port;

  void Function(Map<String, Object?>)? _onControl;
  void Function(Uint8List)? _onRtp;
  void Function(Uint8List)? _onRtcp;
  bool _closed = false;

  _UdpRelayEndpoint(this._hub, this._host, this._port);

  @override
  set onControl(void Function(Map<String, Object?>) cb) => _onControl = cb;
  @override
  set onRtp(void Function(Uint8List) cb) => _onRtp = cb;
  @override
  set onRtcp(void Function(Uint8List) cb) => _onRtcp = cb;

  @override
  void sendControl(Map<String, Object?> msg) {
    if (_closed) return;
    final body = utf8.encode(jsonEncode(msg));
    _hub._send(_host, _port, _typeControl, Uint8List.fromList(body));
  }

  @override
  void sendRtp(Uint8List pkt) {
    if (_closed) return;
    _hub._send(_host, _port, _typeRtp, pkt);
  }

  @override
  void sendRtcp(Uint8List pkt) {
    if (_closed) return;
    _hub._send(_host, _port, _typeRtcp, pkt);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final key = '${_host.address}:$_port';
    _hub._endpoints.remove(key);
  }

  Future<void> _closeInternal() async {
    _closed = true;
  }

  void _dispatch(int type, Uint8List payload) {
    if (_closed) return;
    switch (type) {
      case _typeControl:
        try {
          final m = jsonDecode(utf8.decode(payload)) as Map<String, Object?>;
          _onControl?.call(m);
        } catch (_) {
          // malformed control — drop silently
        }
        break;
      case _typeRtp:
        _onRtp?.call(payload);
        break;
      case _typeRtcp:
        _onRtcp?.call(payload);
        break;
    }
  }
}
