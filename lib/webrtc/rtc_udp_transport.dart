// UDP transport that demultiplexes WebRTC packet types over a single
// socket: STUN, DTLS, SRTP, and SRTCP, per RFC 7983.
//
// Wires together [DtlsServer] (DTLS handshake → SRTP keying material),
// [SRTPContext] (SRTP/SRTCP encrypt/decrypt) and the project's STUN server,
// exposing a small browser-style callback surface so an `RTCPeerConnection`
// can plug it in as its ICE/DTLS transport.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/src/dtls/dtls_message.dart' as dtls;
import 'package:pure_dart_webrtc/src/dtls/server/dtls_session.dart';
import 'package:pure_dart_webrtc/src/dtls/tests/verify_ecdsa_256_cert1.dart'
    show EcdsaCert;
import 'package:pure_dart_webrtc/src/srtp/protection_profiles.dart';
import 'package:pure_dart_webrtc/src/srtp/rtp2.dart' as rtp;
import 'package:pure_dart_webrtc/src/srtp/srtp_context.dart';
import 'package:pure_dart_webrtc/src/srtp/srtp_manager.dart';
import 'package:pure_dart_webrtc/src/stun/stun_server.dart' as stun;

/// Returns true if [buf] looks like an RTP packet (PT in 0..35 or 96..127).
bool isRtpPacket(Uint8List buf) {
  if (buf.length < 2) return false;
  final pt = buf[1] & 0x7f;
  return pt <= 35 || (pt >= 96 && pt <= 127);
}

/// Returns true if [buf] looks like an RTCP packet (PT in 64..95).
bool isRtcpPacket(Uint8List buf) {
  if (buf.length < 2) return false;
  final pt = buf[1] & 0x7f;
  return pt >= 64 && pt <= 95;
}

/// Per-peer remote endpoint key.
class _PeerKey {
  final String host;
  final int port;
  const _PeerKey(this.host, this.port);
  @override
  bool operator ==(Object o) =>
      o is _PeerKey && o.host == host && o.port == port;
  @override
  int get hashCode => Object.hash(host, port);
}

/// Per-peer state: DTLS session + lazily-initialized SRTP context.
class RtcPeerTransport {
  final InternetAddress remoteAddress;
  final int remotePort;
  final DtlsSession dtlsSession;
  SRTPContext? srtp;

  /// SRTP packet/byte counters (for `RTCPeerConnection.getStats()`).
  int packetsSent = 0;
  int bytesSent = 0;
  int packetsReceived = 0;
  int bytesReceived = 0;
  int rtcpPacketsSent = 0;
  int rtcpPacketsReceived = 0;

  RtcPeerTransport({
    required this.remoteAddress,
    required this.remotePort,
    required this.dtlsSession,
  });

  bool get isSecure => srtp != null;
}

/// Single-socket UDP transport for a WebRTC server endpoint.
class RtcUdpTransport {
  final RawDatagramSocket _socket;
  final EcdsaCert _certificate;
  final String _stunPassword;
  final ProtectionProfile _protectionProfile;
  final Map<_PeerKey, RtcPeerTransport> _peers = {};
  StreamSubscription<RawSocketEvent>? _sub;
  bool _closed = false;

  /// Fired when a brand-new peer is observed (first packet received).
  void Function(RtcPeerTransport peer)? onPeer;

  /// Fired when DTLS completes for a peer and SRTP is keyed.
  void Function(RtcPeerTransport peer)? onSecure;

  /// Fired with each successfully decrypted RTP packet body.
  void Function(RtcPeerTransport peer, Uint8List rtp)? onRtp;

  /// Fired with each successfully decrypted RTCP compound packet.
  void Function(RtcPeerTransport peer, Uint8List rtcp)? onRtcp;

  /// Fired for a packet that didn't match STUN/DTLS/SRTP/SRTCP.
  void Function(RtcPeerTransport? peer, Uint8List data)? onUnknown;

  RtcUdpTransport._(
    this._socket,
    this._certificate,
    this._stunPassword,
    this._protectionProfile,
  );

  /// Bind a UDP socket on [address]:[port] and start dispatching packets.
  static Future<RtcUdpTransport> bind(
    InternetAddress address,
    int port, {
    required EcdsaCert certificate,
    required String stunPassword,
    ProtectionProfile protectionProfile = ProtectionProfile.aes_128_gcm,
  }) async {
    final socket = await RawDatagramSocket.bind(address, port);
    final t =
        RtcUdpTransport._(socket, certificate, stunPassword, protectionProfile);
    t._sub = socket.listen(t._onSocketEvent);
    return t;
  }

  InternetAddress get address => _socket.address;
  int get port => _socket.port;

  /// Send a raw datagram to [remote].
  void sendTo(Uint8List data, InternetAddress remote, int remotePort) {
    if (_closed) return;
    _socket.send(data, remote, remotePort);
  }

  /// Encrypt and send an RTP packet to [peer]. Returns false if SRTP isn't
  /// keyed yet.
  Future<bool> sendRtp(RtcPeerTransport peer, Uint8List rtpBytes) async {
    final ctx = peer.srtp;
    if (ctx == null || ctx.gcm == null) return false;
    final pkt = rtp.Packet.unmarshal(rtpBytes);
    final encrypted = await ctx.encryptRtpPacket(pkt);
    sendTo(encrypted, peer.remoteAddress, peer.remotePort);
    peer.packetsSent++;
    peer.bytesSent += encrypted.length;
    return true;
  }

  /// Encrypt and send an RTCP compound packet to [peer].
  Future<bool> sendRtcp(RtcPeerTransport peer, Uint8List rtcpBytes) async {
    final ctx = peer.srtp;
    if (ctx == null || ctx.gcm == null) return false;
    final encrypted = await ctx.encryptRtcpPacket(rtcpBytes);
    sendTo(encrypted, peer.remoteAddress, peer.remotePort);
    peer.rtcpPacketsSent++;
    return true;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    _socket.close();
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket.receive();
    if (dg == null) return;
    final data = Uint8List.fromList(dg.data);
    final key = _PeerKey(dg.address.address, dg.port);
    final peer = _peers.putIfAbsent(key, () => _newPeer(dg.address, dg.port));

    if (stun.StunMessage.isStunMessage(data)) {
      stun.StunServer.handleDatagram(
        Datagram(data, dg.address, dg.port),
        socket: _socket,
        serverPassword: _stunPassword,
      );
      return;
    }

    if (dtls.isDtlsPacket(data, 0, data.length)) {
      // Feed DTLS into the per-peer session. After the handshake completes
      // the session callback wires up SRTP for this peer.
      unawaited(peer.dtlsSession.handleDatagram(data));
      return;
    }

    if (isRtcpPacket(data)) {
      final ctx = peer.srtp;
      if (ctx != null && ctx.gcm != null) {
        ctx.decryptRtcpPacket(data).then((decoded) {
          peer.rtcpPacketsReceived++;
          onRtcp?.call(peer, decoded);
        }).catchError((Object e) {
          // Decryption failed (replay, bad tag, etc.); drop silently.
        });
      }
      return;
    }

    if (isRtpPacket(data)) {
      final ctx = peer.srtp;
      if (ctx != null && ctx.gcm != null) {
        try {
          final pkt = rtp.Packet.unmarshal(data);
          ctx.decryptRtpPacket(pkt).then((decoded) {
            peer.packetsReceived++;
            peer.bytesReceived += data.length;
            onRtp?.call(peer, decoded);
          }).catchError((Object e) {
            // Drop on decrypt failure.
          });
        } catch (_) {
          // Malformed RTP; ignore.
        }
      }
      return;
    }

    onUnknown?.call(peer, data);
  }

  RtcPeerTransport _newPeer(InternetAddress addr, int port) {
    final session = DtlsSession(
      serverCert: _certificate,
      sendRaw: (bytes) => _socket.send(bytes, addr, port),
    );
    final peer = RtcPeerTransport(
      remoteAddress: addr,
      remotePort: port,
      dtlsSession: session,
    );

    session.onConnected = () {
      _initSrtpForPeer(peer);
      onSecure?.call(peer);
    };

    onPeer?.call(peer);
    return peer;
  }

  void _initSrtpForPeer(RtcPeerTransport peer) {
    final keyLen = _protectionProfile.keyLength();
    final saltLen = _protectionProfile.saltLength();
    final keyingMaterial =
        peer.dtlsSession.context.exportKeyingMaterial(keyLen * 2 + saltLen * 2);
    final ctx = SRTPContext(protectionProfile: _protectionProfile);
    SRTPManager().initCipherSuiteForRole(ctx, keyingMaterial, SrtpRole.server);
    peer.srtp = ctx;
  }
}
