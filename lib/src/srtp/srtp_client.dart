// SRTP client built on top of [SRTPManager] / [SRTPContext].
//
// The repository's existing server example (`bin/srtp_webrtc2.dart`) uses
// `SRTPManager.initCipherSuite` to wire up a single GCM cipher (the client's
// key/salt). That works *for the server's receive direction* because
// inbound (client→server) traffic is encrypted with the client's keys.
//
// A real WebRTC endpoint needs both directions, with opposite key
// assignments depending on whether it acts as the DTLS client or server.
// This file exposes a convenience client that:
//
//   1. Wraps a `RawDatagramSocket`.
//   2. Initializes an [SRTPContext] using
//      [SRTPManager.initCipherSuiteForRole] with [SrtpRole.client]
//      (outbound = client keys, inbound = server keys).
//   3. Provides [sendRtp] (encrypts) and a stream of decrypted inbound
//      packets via [packets].
//
// It is deliberately transport-agnostic about how the DTLS handshake runs:
// the caller is expected to perform the DTLS handshake separately (e.g. via
// the existing DTLS client), then hand the exported keying material to
// [SRTPClient.initialize].

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../dtls/dtls_message.dart' as dtls;
import '../stun3/stun_server8.dart' as stun;
import 'protection_profiles.dart';
import 'rtp2.dart';
import 'srtp_context.dart';
import 'srtp_manager.dart';

/// True if [buf] looks like an RTP packet (PT in 0-35 or 96-127).
bool isRtpPacket(Uint8List buf, int offset, int arrayLen) {
  if (arrayLen < 2) return false;
  final payloadType = buf[offset + 1] & 0x7f;
  return (payloadType <= 35) || (payloadType >= 96 && payloadType <= 127);
}

/// One decrypted RTP packet received from the peer, together with the
/// remote socket address it came from.
class SrtpPacket {
  final InternetAddress remoteAddress;
  final int remotePort;
  final Packet packet;
  SrtpPacket(this.remoteAddress, this.remotePort, this.packet);
}

/// SRTP client wrapping a UDP socket and an [SRTPContext].
///
/// Typical lifecycle:
/// ```
/// final client = await SRTPClient.bind(remote: peer, remotePort: 4444);
/// // ... run DTLS handshake out-of-band, obtain keyingMaterial ...
/// await client.initialize(keyingMaterial);
/// client.packets.listen((p) => print('got ${p.packet}'));
/// await client.sendRtp(myPacket);
/// ```
class SRTPClient {
  final RawDatagramSocket socket;
  final InternetAddress remoteAddress;
  final int remotePort;
  final ProtectionProfile protectionProfile;

  late final SRTPContext context;
  final SRTPManager _manager = SRTPManager();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  final StreamController<SrtpPacket> _packets =
      StreamController<SrtpPacket>.broadcast();

  /// Stream of decrypted RTP packets received from the peer.
  Stream<SrtpPacket> get packets => _packets.stream;

  /// Optional hook for non-RTP datagrams (STUN / DTLS / unknown). Useful if
  /// the caller wants to multiplex DTLS handshake traffic on the same
  /// socket.
  void Function(Datagram datagram)? onNonRtp;

  StreamSubscription<RawSocketEvent>? _subscription;

  SRTPClient._(
    this.socket,
    this.remoteAddress,
    this.remotePort,
    this.protectionProfile, {
    bool subscribeToSocket = true,
  }) {
    context = _manager.newContext(protectionProfile);
    if (subscribeToSocket) {
      _subscription = socket.listen(_onEvent);
    }
  }

  /// Bind a UDP socket and prepare the client. The DTLS handshake is *not*
  /// performed here; call [initialize] once it completes.
  static Future<SRTPClient> bind({
    required InternetAddress remote,
    required int remotePort,
    InternetAddress? localAddress,
    int localPort = 0,
    ProtectionProfile protectionProfile = ProtectionProfile.aes_128_gcm,
  }) async {
    final socket = await RawDatagramSocket.bind(
        localAddress ?? InternetAddress.anyIPv4, localPort);
    return SRTPClient._(socket, remote, remotePort, protectionProfile);
  }

  /// Wrap an already-bound socket. Use this when the same UDP socket is
  /// shared with a DTLS client.
  ///
  /// Set [subscribeToSocket] to `false` if some other component (e.g. a
  /// DTLS client) already holds the only allowed listener on the socket;
  /// in that case feed inbound datagrams via [handleDatagram].
  static SRTPClient wrap({
    required RawDatagramSocket socket,
    required InternetAddress remote,
    required int remotePort,
    ProtectionProfile protectionProfile = ProtectionProfile.aes_128_gcm,
    bool subscribeToSocket = true,
  }) =>
      SRTPClient._(socket, remote, remotePort, protectionProfile,
          subscribeToSocket: subscribeToSocket);

  /// Feed a datagram received on the shared socket. Same logic as the
  /// internal listener, exposed for callers that own the only stream
  /// subscription on the socket.
  void handleDatagram(Datagram datagram) => _handle(datagram);

  /// Derive SRTP cipher state from the DTLS-exported keying material.
  ///
  /// [keyingMaterial] must contain
  ///   `2 * keyLength + 2 * saltLength` bytes (32 + 24 = 56 for AES-128-GCM)
  /// in the standard `clientKey || serverKey || clientSalt || serverSalt`
  /// order, exactly as produced by `HandshakeContext.exportKeyingMaterial`.
  Future<void> initialize(Uint8List keyingMaterial) async {
    final keyLength = protectionProfile.keyLength();
    final saltLength = protectionProfile.saltLength();
    final expected = 2 * keyLength + 2 * saltLength;
    if (keyingMaterial.length != expected) {
      throw ArgumentError(
          'keyingMaterial length ${keyingMaterial.length} != expected $expected');
    }
    await _manager.initCipherSuiteForRole(
        context, keyingMaterial, SrtpRole.client);
    _initialized = true;
  }

  /// Encrypt [packet] and send it to the peer. Throws if the SRTP context
  /// has not been initialized.
  Future<int> sendRtp(Packet packet) async {
    if (!_initialized) {
      throw StateError('SRTPClient.initialize() has not been called');
    }
    final encrypted = await context.encryptRtpPacket(packet);
    return socket.send(encrypted, remoteAddress, remotePort);
  }

  /// Convenience: send a raw RTP byte buffer (will be parsed first).
  Future<int> sendRtpBytes(Uint8List rtpBytes) =>
      sendRtp(Packet.unmarshal(rtpBytes));

  /// Close the underlying socket and the packet stream.
  Future<void> close() async {
    await _subscription?.cancel();
    socket.close();
    await _packets.close();
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = socket.receive();
    if (datagram == null) return;
    _handle(datagram);
  }

  void _handle(Datagram datagram) {
    final data = datagram.data;
    if (data.isEmpty) return;

    if (stun.StunMessage.isStunMessage(data) ||
        dtls.isDtlsPacket(data, 0, data.length)) {
      onNonRtp?.call(datagram);
      return;
    }

    if (!isRtpPacket(data, 0, data.length)) {
      onNonRtp?.call(datagram);
      return;
    }

    if (!_initialized) {
      // RTP arrived before keys are ready; drop and let the caller deal
      // with it via onNonRtp if needed.
      onNonRtp?.call(datagram);
      return;
    }

    () async {
      try {
        final pkt = Packet.unmarshal(data);
        final decrypted = await context.decryptRtpPacket(pkt);
        final decryptedPacket = Packet.unmarshal(decrypted);
        _packets
            .add(SrtpPacket(datagram.address, datagram.port, decryptedPacket));
      } catch (e, st) {
        _packets.addError(e, st);
      }
    }();
  }
}
