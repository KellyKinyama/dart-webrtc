// A small, modular DTLS 1.2 server that supports multiple concurrent peers
// over a single UDP socket. Each remote endpoint gets its own
// [DtlsSession] (and therefore its own handshake state and cipher state).
//
// Example:
//
//   final cert = generateSelfSignedCertificate();
//   final server = await DtlsServer.bind(
//     InternetAddress.loopbackIPv4, 4444, certificate: cert);
//   server.onSession = (session, addr, port) {
//     session.onApplicationData = (data) => print('got: ${utf8.decode(data)}');
//   };
//
// Note: this preserves the existing handshake message types, crypto and
// HandshakeContext. The legacy `HandshakeManager` in
// `handshaker/aes_gcm_128_sha_256.dart` is left in place for backwards
// compatibility.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../tests/verify_ecdsa_256_cert1.dart';

import 'dtls_session.dart';

/// Identifies a remote peer by `(host, port)`.
class PeerKey {
  final String host;
  final int port;
  const PeerKey(this.host, this.port);

  @override
  bool operator ==(Object other) =>
      other is PeerKey && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => '$host:$port';
}

/// Multi-peer DTLS 1.2 server.
class DtlsServer {
  final RawDatagramSocket _socket;
  final EcdsaCert _cert;
  final Map<PeerKey, DtlsSession> _sessions = {};
  late final StreamSubscription<RawSocketEvent> _sub;
  bool _closed = false;

  /// Called for each freshly-created [DtlsSession] (i.e. once per peer).
  /// Use this to attach `onConnected` / `onApplicationData` callbacks.
  void Function(DtlsSession session, InternetAddress address, int port)?
      onSession;

  DtlsServer._(this._socket, this._cert) {
    _sub = _socket.listen(_onEvent);
  }

  /// Binds a UDP socket on [address]:[port] and starts listening for DTLS
  /// peers. Pass [certificate] (an [EcdsaCert]) to control the server
  /// identity; otherwise a fresh self-signed P-256 cert is generated.
  static Future<DtlsServer> bind(
    InternetAddress address,
    int port, {
    EcdsaCert? certificate,
  }) async {
    final socket = await RawDatagramSocket.bind(address, port);
    return DtlsServer._(socket, certificate ?? generateSelfSignedCertificate());
  }

  InternetAddress get address => _socket.address;
  int get port => _socket.port;

  /// Returns the active session for [address]:[port], or null if none.
  DtlsSession? sessionFor(InternetAddress address, int port) =>
      _sessions[PeerKey(address.address, port)];

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub.cancel();
    _socket.close();
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket.receive();
    if (dg == null) return;
    final key = PeerKey(dg.address.address, dg.port);
    final session =
        _sessions.putIfAbsent(key, () => _createSession(dg.address, dg.port));
    // Fire-and-forget: handleDatagram is async (GCM) but datagrams are still
    // processed in arrival order because each call awaits internally.
    unawaited(session.handleDatagram(Uint8List.fromList(dg.data)));
  }

  DtlsSession _createSession(InternetAddress remoteAddr, int remotePort) {
    final session = DtlsSession(
      serverCert: _cert,
      sendRaw: (bytes) => _socket.send(bytes, remoteAddr, remotePort),
    );
    onSession?.call(session, remoteAddr, remotePort);
    return session;
  }
}
