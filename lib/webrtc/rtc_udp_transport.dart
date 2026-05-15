// UDP transport that demultiplexes WebRTC packet types over a single
// socket: STUN, DTLS, SRTP, and SRTCP, per RFC 7983.
//
// Wires together [DtlsServer] (DTLS handshake → SRTP keying material),
// [SRTPContext] (SRTP/SRTCP encrypt/decrypt) and the project's STUN server,
// exposing a small browser-style callback surface so an `RTCPeerConnection`
// can plug it in as its ICE/DTLS transport.

import 'dart:async';
import 'dart:io';
import 'dart:math';
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

/// When true, prints a line for every STUN / DTLS / SRTP packet that
/// crosses the socket. Off by default (very noisy under media). Enable by
/// running the SFU with the env var `WEBRTC_DEBUG=1`.
final bool _verbose = (() {
  final v = Platform.environment['WEBRTC_DEBUG'];
  return v != null && v.isNotEmpty && v != '0' && v.toLowerCase() != 'false';
})();

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

  /// How this peer's address first became known to the transport.
  ///
  /// * `'host'` — the very first packet from this (host, port) was a
  ///   DTLS record (e.g. raw DTLS clients, non-ICE flows, tests).
  /// * `'prflx'` — peer-reflexive: the first packet was an
  ///   authenticated STUN binding request from a source address we
  ///   hadn't seen advertised in any prior candidate list. This is
  ///   what happens to NAT'd browser peers — the public-side host:port
  ///   is only learnable from the connectivity check itself.
  ///
  /// Surfaced for stats / debugging; the transport currently treats
  /// both kinds the same once they've been admitted.
  final String discoveryMethod;

  /// Number of valid (passing MESSAGE-INTEGRITY) STUN binding requests
  /// received from this peer. Bumped by [RtcUdpTransport] in
  /// [_onSocketEvent] only after the embedded STUN server has accepted
  /// the request, so a flood of forged binding requests can't inflate
  /// this counter.
  int bindingRequestsReceived = 0;

  /// Set true the first time a binding request from this peer carries
  /// the USE-CANDIDATE attribute (RFC 8445 §7.1.2 — the controlling
  /// agent's signal that this pair should be nominated for media).
  /// Pure-Dart-WebRTC operates as the controlled side, so we treat
  /// USE-CANDIDATE as authoritative the moment we see it on a check
  /// that already passed the integrity gate. This matches the
  /// "aggressive nomination" model browsers use in practice — they
  /// stamp USE-CANDIDATE on every check and expect the controlled
  /// side to accept the highest-priority pair that ever arrives.
  bool nominated = false;
  DateTime? nominatedAt;


  RtcPeerTransport({
    required this.remoteAddress,
    required this.remotePort,
    required this.dtlsSession,
    this.discoveryMethod = 'host',
  }) : lastPacketAt = DateTime.now();

  /// Wall-clock of the last datagram observed from this peer. Used by
  /// [RtcUdpTransport]'s periodic eviction sweep to garbage-collect
  /// orphan peers (e.g. clients that DTLS-failed and never came back,
  /// or browsers that disconnected without sending close_notify).
  DateTime lastPacketAt;

  bool get isSecure => srtp != null;

  /// Drop any SRTP keying material this peer was holding. Idempotent.
  /// Called when the owning [RtcUdpTransport] evicts the peer or when
  /// the transport itself is torn down, so the GCM keys don't sit in
  /// memory after we stop talking to the peer.
  void disposeSrtp() {
    final ctx = srtp;
    srtp = null;
    ctx?.close();
  }
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

  /// Periodic sweep that evicts orphan/idle peers from [_peers] so the
  /// map can't grow unbounded across reconnects. Started lazily on the
  /// first bound socket, cancelled in [close].
  Timer? _evictionTimer;

  /// Idle TTL for unsecured peers (DTLS never completed). Anything
  /// over this is almost certainly orphan handshake noise.
  static const Duration _unsecuredPeerTtl = Duration(seconds: 30);

  /// Idle TTL for unsecured *and* never-nominated peers — i.e. (host,
  /// port) pairs that sent some valid STUN binding requests but have
  /// never been promoted by the controlling agent (no USE-CANDIDATE)
  /// and never completed DTLS. These are typical "losing" ICE
  /// candidates: trickle-in alternates that never won the check, or
  /// flooded STUN sources from a misbehaving probe. Evict aggressively
  /// to keep [_maxPeers] headroom for the real winner.
  static const Duration _unnominatedUnsecuredPeerTtl = Duration(seconds: 8);

  /// Idle TTL for secured peers. Long enough to tolerate audio-only
  /// pauses and brief network blips, short enough to release memory
  /// from gone-for-good clients.
  static const Duration _securedPeerTtl = Duration(minutes: 5);

  /// Hard cap on total tracked peers. Even with periodic eviction an
  /// attacker could otherwise spam STUN binding requests from a
  /// rotating source-port pool to fill `_peers` with `RtcPeerTransport`
  /// + `DtlsSession` allocations. Once we hit this cap we stop
  /// admitting new (host, port) pairs entirely; existing peers and
  /// the eviction sweep continue to make progress.
  static const int _maxPeers = 256;

  /// Outstanding outbound STUN binding requests keyed by hex(transactionId).
  /// Completed by [_onSocketEvent] when a matching success/error response
  /// arrives, so callers of [queryStunBinding] can `await` the reflexive
  /// address discovered by a STUN server.
  final Map<String, Completer<stun.MappedAddress>> _pendingStunQueries = {};

  /// Per-(server) throttle and per-(local,server) cache for outbound
  /// STUN binding queries. Without this, an SFU that spawns N
  /// `RTCPeerConnection`s with M configured STUN URLs would burst N*M
  /// requests at the same public reflector (e.g. stun.l.google.com)
  /// every time a client connects. That earns a rate-limit from
  /// Google and silent dropped responses for everyone else on the
  /// same egress IP. The cache TTL is conservative — NAT mappings
  /// for a given local UDP socket are stable for as long as the
  /// socket is bound, so we can reuse a result for minutes.
  static final Map<String, _StunServerThrottle> _stunThrottles = {};
  final Map<String, _CachedSrflx> _srflxCache = {};
  static const Duration _srflxCacheTtl = Duration(minutes: 1);

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
    t._evictionTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => t._evictStalePeers());
    return t;
  }

  InternetAddress get address => _socket.address;
  int get port => _socket.port;

  /// Send a raw datagram to [remote].
  void sendTo(Uint8List data, InternetAddress remote, int remotePort) {
    if (_closed) return;
    _socket.send(data, remote, remotePort);
  }

  /// Send a STUN Binding Request to [serverHost]:[serverPort] from the
  /// bound media socket and resolve with the server-reported reflexive
  /// address (XOR-MAPPED-ADDRESS).
  ///
  /// Used for ICE server-reflexive (`srflx`) candidate gathering. Because
  /// the request is sent from the same socket that carries SRTP/DTLS, the
  /// returned port reflects the actual NAT mapping for media — making the
  /// candidate usable for connectivity checks.
  ///
  /// Throws [TimeoutException] if no response arrives within [timeout].
  Future<stun.MappedAddress> queryStunBinding(
    InternetAddress serverHost,
    int serverPort, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (_closed) {
      throw StateError('RtcUdpTransport is closed.');
    }

    final serverKey = '${serverHost.address}:$serverPort';

    // 1. Per-(local-socket, server) cache. Keeps repeat gathering on the
    //    same transport from re-querying the reflector.
    final cached = _srflxCache[serverKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.address;
    }

    // 2. Process-wide per-server throttle. Coalesces concurrent queries
    //    from multiple PCs and rate-limits bursts so we don't get
    //    blacklisted by public STUN servers.
    final throttle =
        _stunThrottles.putIfAbsent(serverKey, _StunServerThrottle.new);
    await throttle.acquire();

    // Re-check the cache after waiting — a sibling query may have
    // populated it while we were queued.
    final cached2 = _srflxCache[serverKey];
    if (cached2 != null && cached2.expiresAt.isAfter(DateTime.now())) {
      return cached2.address;
    }

    final txId = _generateTransactionId();
    final txKey = _hex(txId);
    final request = stun.StunMessage(
      messageType: stun.StunMessageType.bindingRequest,
      transactionId: txId,
    );
    final completer = Completer<stun.MappedAddress>();
    _pendingStunQueries[txKey] = completer;
    try {
      _socket.send(request.encode(), serverHost, serverPort);
      final result = await completer.future.timeout(timeout);
      throttle.recordSuccess();
      _srflxCache[serverKey] =
          _CachedSrflx(result, DateTime.now().add(_srflxCacheTtl));
      return result;
    } on TimeoutException {
      throttle.recordFailure();
      rethrow;
    } finally {
      _pendingStunQueries.remove(txKey);
    }
  }

  static Uint8List _generateTransactionId() {
    final r = Random.secure();
    final out = Uint8List(stun.stunTransactionIdSize);
    for (var i = 0; i < out.length; i++) {
      out[i] = r.nextInt(256);
    }
    return out;
  }

  static String _hex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
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

  /// Snapshot of every currently tracked peer. Useful for stats /
  /// diagnostics — exposes ICE attributes (`nominated`,
  /// `discoveryMethod`, `bindingRequestsReceived`) without granting
  /// callers write access to the internal map.
  List<RtcPeerTransport> get peers => List.unmodifiable(_peers.values);

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _evictionTimer?.cancel();
    _evictionTimer = null;
    await _sub?.cancel();
    // Drop SRTP keys for every peer; if the caller releases its
    // reference next we don't want stale GCM state lingering.
    for (final p in _peers.values) {
      p.disposeSrtp();
    }
    _peers.clear();
    _socket.close();
  }

  void _evictStalePeers() {
    if (_closed || _peers.isEmpty) return;
    final now = DateTime.now();
    final stale = <_PeerKey>[];
    _peers.forEach((key, peer) {
      final idle = now.difference(peer.lastPacketAt);
      Duration ttl;
      if (peer.isSecure) {
        ttl = _securedPeerTtl;
      } else if (peer.nominated) {
        ttl = _unsecuredPeerTtl;
      } else {
        ttl = _unnominatedUnsecuredPeerTtl;
      }
      if (idle > ttl) stale.add(key);
    });
    for (final k in stale) {
      final peer = _peers.remove(k);
      if (peer != null) {
        // Drop SRTP keying material so it doesn't sit in memory after
        // we've decided we're done with this peer.
        peer.disposeSrtp();
        if (_verbose) {
          // ignore: avoid_print
          print('[udp ${_socket.address.address}:${_socket.port}] '
              'evicting idle peer ${k.host}:${k.port} '
              '(secure=${peer.isSecure}, nominated=${peer.nominated}, '
              'discovery=${peer.discoveryMethod})');
        }
      }
    }
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket.receive();
    if (dg == null) return;
    final data = Uint8List.fromList(dg.data);
    final key = _PeerKey(dg.address.address, dg.port);

    // Look up the existing peer; do NOT auto-create yet. Auto-creation
    // is deferred until we have a reason to trust the sender (an
    // authenticated STUN binding request, or a DTLS/RTP/RTCP packet
    // from a peer we already know about). This blocks an attacker who
    // would otherwise allocate a `RtcPeerTransport` + `DtlsSession`
    // per spoofed source port just by sending bare STUN requests.
    var peer = _peers[key];

    if (stun.StunMessage.isStunMessage(data)) {
      if (_verbose) {
        // ignore: avoid_print
        print('[udp ${_socket.address.address}:${_socket.port}] STUN '
            '${data.length}B from ${dg.address.address}:${dg.port}');
      }
      // If this is a response to one of our outbound binding queries
      // (srflx gathering), consume it locally instead of forwarding to the
      // embedded STUN server (which only handles inbound requests).
      if (_tryCompleteStunQuery(data)) return;

      // Pre-decode + integrity-check the inbound binding request so
      // that (a) bad-credential requests never even allocate a peer
      // entry (defends [_maxPeers] against forged-source-port floods)
      // and (b) we can extract ICE attributes (USE-CANDIDATE → nominated,
      // discoveryMethod = 'prflx') in the same pass.
      stun.StunMessage? parsed;
      try {
        parsed = stun.StunMessage.decode(data);
      } catch (_) {
        // Malformed STUN — drop without touching the peer map.
        return;
      }
      if (parsed.messageType.method == stun.StunMessageMethod.binding &&
          parsed.messageType.messageClass == stun.StunMessageClass.request) {
        if (!parsed.validateAsResponse(passwordForIntegrity: _stunPassword)) {
          if (_verbose) {
            // ignore: avoid_print
            print('[udp ${_socket.address.address}:${_socket.port}] '
                'STUN binding from ${dg.address.address}:${dg.port} '
                'failed MESSAGE-INTEGRITY; not creating peer');
          }
          return;
        }
      }

      if (peer == null) {
        if (_peers.length >= _maxPeers) {
          if (_verbose) {
            // ignore: avoid_print
            print('[udp ${_socket.address.address}:${_socket.port}] '
                'peer cap ($_maxPeers) reached; dropping STUN from '
                '${dg.address.address}:${dg.port}');
          }
          return;
        }
        // First packet from this (host, port) is a signed STUN binding
        // request → peer-reflexive (RFC 8445 §7.3). Tag it so callers
        // can distinguish browser/NAT-mediated peers from raw-DTLS
        // ones in stats / logs.
        peer = _peers.putIfAbsent(
          key,
          () => _newPeer(dg.address, dg.port, discoveryMethod: 'prflx'),
        );
      }
      peer.lastPacketAt = DateTime.now();
      stun.StunServer.handleDatagram(
        Datagram(data, dg.address, dg.port),
        socket: _socket,
        serverPassword: _stunPassword,
        // ICE mode — a real WebRTC peer always signs binding requests
        // with the short-term password from the SDP. Drop anything
        // without a valid MESSAGE-INTEGRITY.
        requireMessageIntegrity: true,
      );
      // Update ICE attributes from the already-validated request.
      _applyIceAttributes(parsed, peer);
      return;
    }

    // DTLS may legitimately arrive before any STUN check (raw DTLS
    // clients, non-ICE flows, tests). Allow eager peer creation here —
    // still gated by the same capacity cap. SRTP/RTCP without a peer
    // are nonsensical and stay dropped below.
    if (peer == null && dtls.isDtlsPacket(data, 0, data.length)) {
      if (_peers.length >= _maxPeers) {
        if (_verbose) {
          // ignore: avoid_print
          print('[udp ${_socket.address.address}:${_socket.port}] '
              'peer cap ($_maxPeers) reached; dropping DTLS from '
              '${dg.address.address}:${dg.port}');
        }
        return;
      }
      peer = _peers.putIfAbsent(key, () => _newPeer(dg.address, dg.port));
    }

    // Past this point we require a known peer. RTP/RTCP from an unknown
    // source port without a prior STUN check-in or DTLS handshake is
    // dropped — there's no decryption context for such traffic anyway.
    if (peer == null) {
      if (_verbose) {
        // ignore: avoid_print
        print('[udp ${_socket.address.address}:${_socket.port}] '
            'non-STUN ${data.length}B from unknown peer '
            '${dg.address.address}:${dg.port}; dropping');
      }
      return;
    }
    // Capture as a non-nullable local so closures below (catchError /
    // .then) don't lose the type promotion that the early-return gave us.
    final p = peer;
    p.lastPacketAt = DateTime.now();

    if (dtls.isDtlsPacket(data, 0, data.length)) {
      if (_verbose) {
        // ignore: avoid_print
        print('[udp ${_socket.address.address}:${_socket.port}] DTLS '
            '${data.length}B from ${dg.address.address}:${dg.port} '
            '(ct=${data[0]})');
      }
      // Feed DTLS into the per-peer session. After the handshake completes
      // the session callback wires up SRTP for this peer.
      unawaited(p.dtlsSession.handleDatagram(data).catchError((e, st) {
        // ignore: avoid_print
        print('[dtls] handleDatagram threw: $e\n$st');
      }));
      return;
    }

    if (isRtcpPacket(data)) {
      final ctx = p.srtp;
      if (ctx != null && ctx.gcm != null) {
        ctx.decryptRtcpPacket(data).then((decoded) {
          p.rtcpPacketsReceived++;
          onRtcp?.call(p, decoded);
        }).catchError((Object e) {
          // Decryption failed (replay, bad tag, etc.); drop silently.
        });
      }
      return;
    }

    if (isRtpPacket(data)) {
      final ctx = p.srtp;
      if (ctx != null && ctx.gcm != null) {
        try {
          final pkt = rtp.Packet.unmarshal(data);
          ctx.decryptRtpPacket(pkt).then((decoded) {
            p.packetsReceived++;
            p.bytesReceived += data.length;
            onRtp?.call(p, decoded);
          }).catchError((Object e) {
            // Drop on decrypt failure.
          });
        } catch (_) {
          // Malformed RTP; ignore.
        }
      }
      return;
    }

    onUnknown?.call(p, data);
  }

  RtcPeerTransport _newPeer(InternetAddress addr, int port,
      {String discoveryMethod = 'host'}) {
    final session = DtlsSession(
      serverCert: _certificate,
      sendRaw: (bytes) {
        if (_verbose) {
          // ignore: avoid_print
          print('[udp ${_socket.address.address}:${_socket.port}] DTLS-> '
              '${bytes.length}B to ${addr.address}:$port '
              '(ct=${bytes.isNotEmpty ? bytes[0] : -1})');
        }
        _socket.send(bytes, addr, port);
      },
    );
    final peer = RtcPeerTransport(
      remoteAddress: addr,
      remotePort: port,
      dtlsSession: session,
      discoveryMethod: discoveryMethod,
    );

    session.onConnected = () {
      _initSrtpForPeer(peer);
      onSecure?.call(peer);
    };

    onPeer?.call(peer);
    return peer;
  }

  /// Update ICE-related fields on [peer] from a STUN binding request
  /// that has already been parsed and integrity-validated by the
  /// caller:
  ///
  ///   * `bindingRequestsReceived++`
  ///   * `nominated = true` when USE-CANDIDATE is present (RFC 8445
  ///     §7.1.2; aggressive nomination — browsers stamp it on every
  ///     check, controlled side accepts immediately).
  void _applyIceAttributes(stun.StunMessage msg, RtcPeerTransport peer) {
    peer.bindingRequestsReceived++;
    if (msg.attributes.containsKey(stun.StunAttributeType.useCandidate)) {
      if (!peer.nominated) {
        peer.nominated = true;
        peer.nominatedAt = DateTime.now();
        if (_verbose) {
          // ignore: avoid_print
          print('[udp ${_socket.address.address}:${_socket.port}] '
              'peer ${peer.remoteAddress.address}:${peer.remotePort} '
              'nominated (USE-CANDIDATE, discovery=${peer.discoveryMethod})');
        }
      }
    }
  }

  /// Returns true if [data] was consumed as a response to a pending
  /// outbound STUN binding query.
  bool _tryCompleteStunQuery(Uint8List data) {
    if (_pendingStunQueries.isEmpty) return false;
    final stun.StunMessage msg;
    try {
      msg = stun.StunMessage.decode(data);
    } catch (_) {
      return false;
    }
    if (msg.messageType.method != stun.StunMessageMethod.binding) {
      return false;
    }
    final cls = msg.messageType.messageClass;
    if (cls != stun.StunMessageClass.successResponse &&
        cls != stun.StunMessageClass.errorResponse) {
      return false;
    }
    final completer = _pendingStunQueries.remove(_hex(msg.transactionId));
    if (completer == null) return false;
    if (cls == stun.StunMessageClass.errorResponse) {
      completer.completeError(
          StateError('STUN Binding Request returned error response'));
      return true;
    }
    final attr = msg.attributes[stun.StunAttributeType.xorMappedAddress];
    if (attr == null) {
      completer.completeError(
          StateError('STUN Binding Response missing XOR-MAPPED-ADDRESS'));
      return true;
    }
    try {
      final mapped =
          stun.decodeXorMappedAddressAttribute(attr, msg.transactionId);
      completer.complete(mapped);
    } catch (e) {
      completer.completeError(e);
    }
    return true;
  }

  void _initSrtpForPeer(RtcPeerTransport peer) {
    // Defensive: an already-keyed peer means DTLS fired onConnected
    // twice (e.g. a duplicate Finished slipped past the new server-side
    // _flight6Sent guard). Re-deriving keys would silently swap the
    // ciphers under the running RTP loop and break authentication on
    // every subsequent packet. Keep the original keys.
    if (peer.srtp != null) {
      if (_verbose) {
        // ignore: avoid_print
        print('[udp ${_socket.address.address}:${_socket.port}] '
            'SRTP already initialized for '
            '${peer.remoteAddress.address}:${peer.remotePort}; skipping');
      }
      return;
    }
    final keyLen = _protectionProfile.keyLength();
    final saltLen = _protectionProfile.saltLength();
    final keyingMaterial =
        peer.dtlsSession.context.exportKeyingMaterial(keyLen * 2 + saltLen * 2);
    final ctx = SRTPContext(protectionProfile: _protectionProfile);
    SRTPManager().initCipherSuiteForRole(ctx, keyingMaterial, SrtpRole.server);
    peer.srtp = ctx;
  }
}

/// Cached server-reflexive address for a (local socket, STUN server)
/// pair, with an absolute expiry time. NAT mappings on a bound UDP
/// socket are stable for the life of the socket on every common
/// gateway, so a minute of caching is conservative.
class _CachedSrflx {
  _CachedSrflx(this.address, this.expiresAt);
  final stun.MappedAddress address;
  final DateTime expiresAt;
}

/// Process-wide rate limiter + circuit breaker for outbound STUN
/// queries against a single server endpoint (e.g. `stun.l.google.com:
/// 19302`). Public reflectors actively rate-limit and will silently
/// black-hole responses to a noisy egress IP, which manifests as
/// every PC's `srflx` gathering timing out at once. Slowing ourselves
/// down keeps us in good standing.
class _StunServerThrottle {
  /// Minimum interval between two outbound queries to the same server.
  /// 200 ms == 5 req/s, well under the documented limits of every
  /// public STUN reflector we know of.
  static const Duration _minInterval = Duration(milliseconds: 200);

  /// Maximum back-off after repeated timeouts (the server is almost
  /// certainly rate-limiting us; back all the way off).
  static const Duration _maxBackoff = Duration(minutes: 5);

  DateTime _nextAvailable = DateTime.fromMillisecondsSinceEpoch(0);
  int _consecutiveFailures = 0;
  Future<void> _tail = Future<void>.value();

  /// Serializes callers and returns once it's safe to send the next
  /// request to this server. Each acquirer extends the queue by at
  /// least [_minInterval], so concurrent gatherings are spaced out
  /// instead of bursting.
  Future<void> acquire() {
    final prev = _tail;
    final c = Completer<void>();
    _tail = c.future;
    return prev.then((_) async {
      final now = DateTime.now();
      if (_nextAvailable.isAfter(now)) {
        await Future<void>.delayed(_nextAvailable.difference(now));
      }
      _nextAvailable = DateTime.now().add(_minInterval);
      c.complete();
    });
  }

  void recordSuccess() {
    _consecutiveFailures = 0;
  }

  /// Exponential back-off on failure: 1s, 2s, 4s, ..., capped.
  void recordFailure() {
    _consecutiveFailures++;
    final backoffMs = (1000 << (_consecutiveFailures - 1).clamp(0, 10));
    final backoff = Duration(milliseconds: backoffMs) > _maxBackoff
        ? _maxBackoff
        : Duration(milliseconds: backoffMs);
    final until = DateTime.now().add(backoff);
    if (until.isAfter(_nextAvailable)) {
      _nextAvailable = until;
    }
  }
}
