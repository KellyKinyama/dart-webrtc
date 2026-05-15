// `RTCPeerConnection` — browser-shaped façade over the lower-level
// DTLS/SRTP/ICE primitives in `lib/src/`.
//
// Mirrors https://www.w3.org/TR/webrtc/#rtcpeerconnection-interface as
// closely as the rest of this codebase allows. The state machines
// (signaling / ICE / connection / ICE-gathering) match the spec verbatim,
// and the offer/answer pipeline delegates to [SdpOfferBuilder] /
// [SdpAnswerBuilder] from `signal/sdp_v2.dart`.
//
// What this class does today:
//   * Generates a self-signed ECDSA cert + ICE ufrag/pwd on first use, so
//     every peer has a stable identity for the SDP fingerprint.
//   * `addTransceiver` / `getTransceivers` book-keeping with mid assignment.
//   * `createOffer` / `createAnswer` / `setLocalDescription` /
//     `setRemoteDescription`, with the spec's signaling-state transitions.
//   * `addIceCandidate`, `localDescription`, `remoteDescription`,
//     `onicecandidate`, `oniceconnectionstatechange`,
//     `onconnectionstatechange`, `onsignalingstatechange`, `ontrack`,
//     `ondatachannel`, `close`.
//   * `bind(address, port)` — starts an [RtcUdpTransport] and emits a real
//     host candidate via `onIceCandidate`; once DTLS completes for a peer,
//     `connectionState` advances to `connected` and decrypted RTP/RTCP is
//     surfaced through the matching `RTCRtpReceiver`.
//   * `RTCRtpSender.send(rtpBytes)` — encrypts and sends an RTP packet
//     to the bound peer.
//   * `createDataChannel` / `onDataChannel` (skeleton; SCTP-over-DTLS not
//     implemented yet — see `rtc_data_channel.dart`).
//   * `getStats()` — returns counters from the bound transport.
//
// What is NOT wired up yet (kept as integration work):
//   * TURN allocation / relay candidates (only host + STUN srflx are
//     gathered; `turn:` URLs in `iceServers` are ignored).
//   * Trickle ICE on the *remote* side (`addIceCandidate` is accepted but
//     not forwarded to the agent).
//   * SCTP framing on data channels.
//
// The shape is what matters: code written against this class can swap in
// the real transport later without changing call sites.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/signal/sdp_v2.dart';
import 'package:pure_dart_webrtc/src/dtls/tests/verify_ecdsa_256_cert1.dart'
    show EcdsaCert, generateSelfSignedCertificate;
import 'package:pure_dart_webrtc/signal/fingerprint.dart' as fp;
import 'package:uuid/v4.dart';

import 'media_stream.dart';
import 'rtc_data_channel.dart';
import 'rtc_ice_candidate.dart';
import 'rtc_rtp_transceiver.dart';
import 'rtc_session_description.dart';
import 'rtc_stats.dart';
import 'rtc_udp_transport.dart';

export 'media_stream.dart';
export 'rtc_data_channel.dart';
export 'rtc_ice_candidate.dart';
export 'rtc_rtp_transceiver.dart';
export 'rtc_session_description.dart';
export 'rtc_stats.dart';
export 'rtc_udp_transport.dart';

/// `RTCSignalingState` — drives the offer/answer state machine.
enum RTCSignalingState {
  stable,
  haveLocalOffer,
  haveRemoteOffer,
  haveLocalPranswer,
  haveRemotePranswer,
  closed,
}

/// `RTCIceConnectionState`.
enum RTCIceConnectionState {
  newState,
  checking,
  connected,
  completed,
  failed,
  disconnected,
  closed,
}

/// `RTCPeerConnectionState`.
enum RTCPeerConnectionState {
  newState,
  connecting,
  connected,
  disconnected,
  failed,
  closed,
}

/// `RTCIceGatheringState`.
enum RTCIceGatheringState { newState, gathering, complete }

/// `RTCIceTransportPolicy`.
enum RTCIceTransportPolicy { all, relay }

/// `RTCBundlePolicy`.
enum RTCBundlePolicy { balanced, maxCompat, maxBundle }

/// One STUN/TURN server entry, matching `RTCIceServer` in the browser.
class RTCIceServer {
  final List<String> urls;
  final String? username;
  final String? credential;

  const RTCIceServer({
    required this.urls,
    this.username,
    this.credential,
  });
}

/// `RTCConfiguration` (subset).
class RTCConfiguration {
  final List<RTCIceServer> iceServers;
  final RTCIceTransportPolicy iceTransportPolicy;
  final RTCBundlePolicy bundlePolicy;

  /// Pre-built codec preferences; if a transceiver doesn't set its own
  /// codec list, these are used.
  final List<SdpCodec> defaultVideoCodecs;
  final List<SdpCodec> defaultAudioCodecs;

  /// Optional pre-generated DTLS certificate. If null, a fresh self-signed
  /// ECDSA P-256 cert is generated lazily on first `createOffer` /
  /// `createAnswer`.
  final EcdsaCert? certificate;

  const RTCConfiguration({
    this.iceServers = const [],
    this.iceTransportPolicy = RTCIceTransportPolicy.all,
    this.bundlePolicy = RTCBundlePolicy.balanced,
    this.defaultVideoCodecs = const [],
    this.defaultAudioCodecs = const [],
    this.certificate,
  });
}

/// Argument passed to [RTCPeerConnection.onTrack].
class RTCTrackEvent {
  final MediaStreamTrack track;
  final RTCRtpReceiver receiver;
  final RTCRtpTransceiver transceiver;
  final List<MediaStream> streams;

  const RTCTrackEvent({
    required this.track,
    required this.receiver,
    required this.transceiver,
    required this.streams,
  });
}

/// Pure-Dart analogue of the browser's `RTCPeerConnection`.
class RTCPeerConnection {
  RTCConfiguration _config;
  final List<RTCRtpTransceiver> _transceivers = [];
  final String _streamId = UuidV4().generate();

  RTCSessionDescription? _localDescription;
  RTCSessionDescription? _remoteDescription;
  RTCSessionDescription? _pendingLocalDescription;
  RTCSessionDescription? _pendingRemoteDescription;
  RTCSessionDescription? _currentLocalDescription;
  RTCSessionDescription? _currentRemoteDescription;

  RTCSignalingState _signalingState = RTCSignalingState.stable;
  RTCIceConnectionState _iceConnectionState = RTCIceConnectionState.newState;
  RTCPeerConnectionState _connectionState = RTCPeerConnectionState.newState;
  RTCIceGatheringState _iceGatheringState = RTCIceGatheringState.newState;

  EcdsaCert? _certificate;
  String? _iceUfrag;
  String? _icePwd;
  String? _fingerprintHash;

  /// Bound UDP transport. Created by [bind].
  RtcUdpTransport? _transport;

  /// Optional override for the address advertised in host ICE candidates.
  /// When the transport is bound to a wildcard address (`0.0.0.0` / `::`)
  /// the bound address is not routable, so callers can pass an explicit
  /// announce address (e.g. the host's LAN IP, or `127.0.0.1` for local
  /// testing) via [bind].
  InternetAddress? _announceAddress;
  RtcPeerTransport? _activePeer;
  final List<RTCDataChannel> _dataChannels = [];

  bool _closed = false;

  // ---- Browser-style event callbacks. ---------------------------------

  /// Fired with each newly gathered local ICE candidate. The final call
  /// passes `null` to mark the end of gathering (matches the browser).
  void Function(RTCIceCandidate? candidate)? onIceCandidate;

  /// Fired when [iceConnectionState] changes.
  void Function(RTCIceConnectionState state)? onIceConnectionStateChange;

  /// Fired when [connectionState] changes.
  void Function(RTCPeerConnectionState state)? onConnectionStateChange;

  /// Fired when [signalingState] changes.
  void Function(RTCSignalingState state)? onSignalingStateChange;

  /// Fired when [iceGatheringState] changes.
  void Function(RTCIceGatheringState state)? onIceGatheringStateChange;

  /// Fired when the remote description introduces a track. Mirrors
  /// `RTCPeerConnection.ontrack`.
  void Function(RTCTrackEvent event)? onTrack;

  /// Fired when (re)negotiation is required (e.g. after [addTransceiver]).
  void Function()? onNegotiationNeeded;

  /// Fired when the remote peer creates a data channel via
  /// [createDataChannel]. Only relevant once SCTP is wired up.
  void Function(RTCDataChannel channel)? onDataChannel;

  RTCPeerConnection([RTCConfiguration? configuration])
      : _config = configuration ?? const RTCConfiguration();

  // ---- Identity / configuration ---------------------------------------

  RTCConfiguration getConfiguration() => _config;
  void setConfiguration(RTCConfiguration configuration) {
    _checkNotClosed();
    _config = configuration;
  }

  /// Returns the cert in use, generating a fresh self-signed P-256 one on
  /// the first call. Mirrors `RTCPeerConnection.generateCertificate`'s
  /// effect, but is synchronous.
  EcdsaCert get certificate {
    return _certificate ??=
        _config.certificate ?? generateSelfSignedCertificate();
  }

  String get _fingerprint =>
      _fingerprintHash ??= fp.fingerprint(certificate.cert);

  String get _ufrag => _iceUfrag ??= _randomToken(4);
  String get _pwd => _icePwd ??= _randomToken(22);

  IceDtlsParams get _identity => IceDtlsParams(
        iceUfrag: _ufrag,
        icePwd: _pwd,
        fingerprintHash: _fingerprint,
      );

  // ---- State accessors -------------------------------------------------

  RTCSessionDescription? get localDescription => _localDescription;
  RTCSessionDescription? get remoteDescription => _remoteDescription;
  RTCSessionDescription? get pendingLocalDescription =>
      _pendingLocalDescription;
  RTCSessionDescription? get pendingRemoteDescription =>
      _pendingRemoteDescription;
  RTCSessionDescription? get currentLocalDescription =>
      _currentLocalDescription;
  RTCSessionDescription? get currentRemoteDescription =>
      _currentRemoteDescription;

  RTCSignalingState get signalingState => _signalingState;
  RTCIceConnectionState get iceConnectionState => _iceConnectionState;
  RTCPeerConnectionState get connectionState => _connectionState;
  RTCIceGatheringState get iceGatheringState => _iceGatheringState;

  // ---- Transceivers / senders / receivers -----------------------------

  List<RTCRtpTransceiver> getTransceivers() => List.unmodifiable(_transceivers);
  List<RTCRtpSender> getSenders() =>
      _transceivers.map((t) => t.sender).toList(growable: false);
  List<RTCRtpReceiver> getReceivers() =>
      _transceivers.map((t) => t.receiver).toList(growable: false);

  /// Add a transceiver in the same way the browser does.
  ///
  /// [trackOrKind] may be a [MediaStreamTrack] or a [MediaKind].
  RTCRtpTransceiver addTransceiver({
    required Object trackOrKind,
    RTCRtpTransceiverDirection direction = RTCRtpTransceiverDirection.sendrecv,
    List<SdpCodec>? codecs,
  }) {
    _checkNotClosed();
    MediaStreamTrack? track;
    MediaKind kind;
    if (trackOrKind is MediaStreamTrack) {
      track = trackOrKind;
      kind = trackOrKind.kind;
    } else if (trackOrKind is MediaKind) {
      kind = trackOrKind;
    } else {
      throw ArgumentError.value(
          trackOrKind, 'trackOrKind', 'expected MediaStreamTrack or MediaKind');
    }

    final picked = codecs ?? _defaultCodecsFor(kind);
    if (picked.isEmpty) {
      throw StateError(
          'No codecs available for $kind; pass `codecs:` or set them in '
          'RTCConfiguration.default${kind == MediaKind.video ? 'Video' : 'Audio'}Codecs.');
    }

    final t = RTCRtpTransceiver(
      kind: kind,
      codecs: List.unmodifiable(picked),
      direction: direction,
      sendTrack: track,
    );
    _transceivers.add(t);
    _scheduleNegotiationNeeded();
    return t;
  }

  /// Convenience that wraps [addTransceiver] in the browser's `addTrack`
  /// shape. Unlike the browser, every call creates a new transceiver — we
  /// don't try to reuse `recvonly` slots.
  RTCRtpSender addTrack(MediaStreamTrack track, [MediaStream? stream]) {
    return addTransceiver(trackOrKind: track).sender;
  }

  void removeTrack(RTCRtpSender sender) {
    _checkNotClosed();
    for (final t in _transceivers) {
      if (identical(t.sender, sender)) {
        sender.track = null;
        if (t.direction == RTCRtpTransceiverDirection.sendrecv) {
          t.direction = RTCRtpTransceiverDirection.recvonly;
        } else if (t.direction == RTCRtpTransceiverDirection.sendonly) {
          t.direction = RTCRtpTransceiverDirection.inactive;
        }
        _scheduleNegotiationNeeded();
        return;
      }
    }
  }

  // ---- Offer / answer --------------------------------------------------

  /// Build a local offer. Does **not** mutate any state — call
  /// [setLocalDescription] to apply it.
  Future<RTCSessionDescription> createOffer() async {
    _checkNotClosed();
    if (_transceivers.isEmpty) {
      throw StateError(
          'createOffer needs at least one transceiver — call addTransceiver() first.');
    }
    final builder = SdpOfferBuilder(
      identity: _identity,
      streamId: _streamId,
      candidates: _hostCandidates(),
      extensions: const [
        SdpRtpExtension(id: 1, uri: SdpRtpExtension.midUri),
        SdpRtpExtension(id: 2, uri: SdpRtpExtension.absSendTimeUri),
        SdpRtpExtension(id: 3, uri: SdpRtpExtension.transportCcUri),
      ],
    );
    for (var i = 0; i < _transceivers.length; i++) {
      final t = _transceivers[i];
      t.mid ??= '$i';
      final dir = _toSdpDirection(t.direction);
      if (t.kind == MediaKind.video) {
        builder.addVideo(mid: t.mid!, codecs: t.codecs, direction: dir);
      } else {
        builder.addAudio(mid: t.mid!, codecs: t.codecs, direction: dir);
      }
    }
    return RTCSessionDescription(RTCSdpType.offer, builder.toSdp());
  }

  /// Build an answer to the currently-set remote offer.
  Future<RTCSessionDescription> createAnswer() async {
    _checkNotClosed();
    final remote = _remoteDescription;
    if (remote == null || remote.type != RTCSdpType.offer) {
      throw StateError('createAnswer requires a remote offer to be set first.');
    }
    final offerMap = parseSdp(remote.sdp);
    // Transceivers were already aligned in setRemoteDescription, but call
    // it again here to be safe in case the caller mutated state.
    _alignTransceiversWithOffer(offerMap);

    final supported = <SdpCodec>[];
    for (final t in _transceivers) {
      supported.addAll(t.codecs);
    }
    final answer = SdpAnswerBuilder(
      offer: offerMap,
      identity: _identity,
      supportedCodecs: supported,
      candidates: _hostCandidates(),
      streamId: _streamId,
    ).toSdp();
    return RTCSessionDescription(RTCSdpType.answer, answer);
  }

  /// One host candidate per bound interface, or `[]` if [bind] hasn't
  /// been called yet. Browsers can connect immediately to whatever ships
  /// in the SDP and don't need trickle to make ICE succeed.
  List<IceCandidate> _hostCandidates() {
    final t = _transport;
    if (t == null) return const [];
    final addr = (_announceAddress ?? t.address).address;
    // RFC 5245 host-candidate priority for a single component.
    const typePref = 126; // host
    const localPref = 65535;
    const componentId = 1;
    final priority = (typePref << 24) | (localPref << 8) | (256 - componentId);
    return [
      IceCandidate(
        foundation: '1',
        component: componentId,
        transport: 'udp',
        priority: priority,
        address: addr,
        port: t.port,
        type: 'host',
      ),
    ];
  }

  /// Apply a *local* description, advancing the signaling state machine
  /// per https://www.w3.org/TR/webrtc/#set-the-rtcsessiondescription.
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    _checkNotClosed();
    switch (description.type) {
      case RTCSdpType.offer:
        _expectSignalingIn({
          RTCSignalingState.stable,
          RTCSignalingState.haveLocalOffer,
        });
        _pendingLocalDescription = description;
        _setSignalingState(RTCSignalingState.haveLocalOffer);
        break;
      case RTCSdpType.answer:
        _expectSignalingIn({
          RTCSignalingState.haveRemoteOffer,
          RTCSignalingState.haveLocalPranswer,
        });
        _currentLocalDescription = description;
        _currentRemoteDescription = _remoteDescription;
        _pendingLocalDescription = null;
        _pendingRemoteDescription = null;
        _setSignalingState(RTCSignalingState.stable);
        break;
      case RTCSdpType.pranswer:
        _expectSignalingIn({
          RTCSignalingState.haveRemoteOffer,
          RTCSignalingState.haveLocalPranswer,
        });
        _pendingLocalDescription = description;
        _setSignalingState(RTCSignalingState.haveLocalPranswer);
        break;
      case RTCSdpType.rollback:
        _rollback(local: true);
        return;
    }
    _localDescription = description;
    _bumpIceGatheringStarted();
  }

  /// Apply a *remote* description.
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    _checkNotClosed();
    switch (description.type) {
      case RTCSdpType.offer:
        _expectSignalingIn({
          RTCSignalingState.stable,
          RTCSignalingState.haveRemoteOffer,
        });
        _pendingRemoteDescription = description;
        // Synthesize matching transceivers for unknown remote sections so
        // ontrack fires correctly below.
        _alignTransceiversWithOffer(parseSdp(description.sdp));
        _setSignalingState(RTCSignalingState.haveRemoteOffer);
        break;
      case RTCSdpType.answer:
        _expectSignalingIn({
          RTCSignalingState.haveLocalOffer,
          RTCSignalingState.haveRemotePranswer,
        });
        _currentRemoteDescription = description;
        _currentLocalDescription = _localDescription;
        _pendingLocalDescription = null;
        _pendingRemoteDescription = null;
        _setSignalingState(RTCSignalingState.stable);
        _setIceConnectionState(RTCIceConnectionState.checking);
        _setConnectionState(RTCPeerConnectionState.connecting);
        break;
      case RTCSdpType.pranswer:
        _expectSignalingIn({
          RTCSignalingState.haveLocalOffer,
          RTCSignalingState.haveRemotePranswer,
        });
        _pendingRemoteDescription = description;
        _setSignalingState(RTCSignalingState.haveRemotePranswer);
        break;
      case RTCSdpType.rollback:
        _rollback(local: false);
        return;
    }
    _remoteDescription = description;
    _fireTrackEventsForRemote(description);
  }

  /// Add a remote ICE candidate. Passing null marks "no more candidates".
  Future<void> addIceCandidate(RTCIceCandidate? candidate) async {
    _checkNotClosed();
    if (candidate == null) {
      // End-of-candidates marker. Real implementations would forward this
      // to the ICE agent.
      return;
    }
    if (_remoteDescription == null) {
      throw StateError('addIceCandidate requires a remote description.');
    }
    // No-op until ICE is wired through; the candidate is accepted so call
    // sites match browser behaviour.
  }

  // ---- Transport binding ---------------------------------------------

  /// Bind the local UDP socket on [address]:[port] and start the
  /// ICE/DTLS/SRTP transport. Emits a real `host` candidate via
  /// [onIceCandidate] and advances [connectionState] to `connected` when
  /// DTLS completes for the first peer.
  ///
  /// [stunPassword] is the ICE pwd used by the embedded STUN server to
  /// validate inbound binding requests. Defaults to the local [_pwd].
  Future<RtcUdpTransport> bind(
    InternetAddress address,
    int port, {
    String? stunPassword,
    InternetAddress? announceAddress,
  }) async {
    _checkNotClosed();
    if (_transport != null) {
      throw StateError('RTCPeerConnection is already bound.');
    }
    final transport = await RtcUdpTransport.bind(
      address,
      port,
      certificate: certificate,
      stunPassword: stunPassword ?? _pwd,
    );
    _transport = transport;
    _announceAddress = announceAddress;

    transport
      ..onPeer = _onTransportPeer
      ..onSecure = _onTransportSecure
      ..onRtp = _onTransportRtp
      ..onRtcp = _onTransportRtcp;

    // Emit one host candidate for the bound socket. Real ICE would gather
    // every interface; here we surface only what we actually bound to.
    final advertisedAddr = (_announceAddress ?? transport.address).address;
    final hostMid =
        _transceivers.isNotEmpty ? (_transceivers.first.mid ?? '0') : '0';
    final hostCand = RTCIceCandidate(
      candidate: 'candidate:1 1 udp 2113937151 $advertisedAddr '
          '${transport.port} typ host',
      sdpMid: hostMid,
      sdpMLineIndex: 0,
      usernameFragment: _ufrag,
    );
    _setIceGatheringState(RTCIceGatheringState.gathering);
    scheduleMicrotask(() {
      if (_closed) return;
      onIceCandidate?.call(hostCand);
      // Continue gathering server-reflexive candidates from the configured
      // STUN servers; emit end-of-candidates once they all settle.
      unawaited(_gatherStunReflexive(transport, hostMid));
    });

    return transport;
  }

  /// Iterate every `stun:` URL in [_config.iceServers], send a Binding
  /// Request from the bound media socket, and emit a server-reflexive
  /// `RTCIceCandidate` for each successful response. Always emits the
  /// `null` end-of-candidates sentinel and advances [iceGatheringState] to
  /// `complete` when finished, even if every query fails.
  Future<void> _gatherStunReflexive(
    RtcUdpTransport transport,
    String mid,
  ) async {
    final servers = <_StunServerEndpoint>[];
    for (final s in _config.iceServers) {
      for (final url in s.urls) {
        final ep = _StunServerEndpoint.parse(url);
        if (ep != null) servers.add(ep);
      }
    }

    // RFC 5245 srflx priority for component 1.
    const typePref = 100; // srflx
    const localPref = 65535;
    const componentId = 1;
    final priority = (typePref << 24) | (localPref << 8) | (256 - componentId);

    var foundation = 2;
    final futures = <Future<void>>[];
    for (final ep in servers) {
      futures.add(() async {
        try {
          final addresses = await InternetAddress.lookup(ep.host);
          if (addresses.isEmpty) return;
          final mapped =
              await transport.queryStunBinding(addresses.first, ep.port);
          if (_closed) return;
          final relAddr = (_announceAddress ?? transport.address).address;
          final cand = RTCIceCandidate(
            candidate: 'candidate:${foundation++} $componentId udp $priority '
                '${mapped.ip.address} ${mapped.port} typ srflx '
                'raddr $relAddr rport ${transport.port}',
            sdpMid: mid,
            sdpMLineIndex: 0,
            usernameFragment: _ufrag,
          );
          onIceCandidate?.call(cand);
        } catch (_) {
          // Swallow per-server errors; one bad STUN shouldn't block the
          // rest of gathering.
        }
      }());
    }

    await Future.wait(futures);
    if (_closed) return;
    onIceCandidate?.call(null);
    _setIceGatheringState(RTCIceGatheringState.complete);
  }

  /// Returns the currently bound transport, or null.
  RtcUdpTransport? get transport => _transport;

  /// First successfully-secured remote peer. Currently the only peer
  /// surfaced — multi-peer broadcast lives at the [RtcUdpTransport] layer.
  RtcPeerTransport? get activePeer => _activePeer;

  // ---- Data channels --------------------------------------------------

  /// Create a data channel. Returns immediately; the channel transitions
  /// to `open` once the underlying DTLS transport is connected.
  RTCDataChannel createDataChannel(String label, [RTCDataChannelInit? init]) {
    _checkNotClosed();
    final ch = RTCDataChannel(label, init);
    _dataChannels.add(ch);
    if (_connectionState == RTCPeerConnectionState.connected) {
      ch.markOpen();
    }
    _scheduleNegotiationNeeded();
    return ch;
  }

  /// Snapshot of the data channels created on this connection.
  List<RTCDataChannel> get dataChannels => List.unmodifiable(_dataChannels);

  // ---- Stats ----------------------------------------------------------

  /// Returns a stats report covering the active peer + sender/receiver
  /// byte counters. The shape mirrors the W3C `RTCStatsReport`.
  Future<RTCStatsReport> getStats() async {
    final stats = <String, RTCStats>{};
    final pc = RTCStats(
      type: 'peer-connection',
      id: 'pc',
      values: {
        'connectionState': _connectionState.name,
        'iceConnectionState': _iceConnectionState.name,
        'signalingState': _signalingState.name,
        'dataChannelsOpened': _dataChannels
            .where((c) => c.readyState == RTCDataChannelState.open)
            .length,
        'dataChannelsClosed': _dataChannels
            .where((c) => c.readyState == RTCDataChannelState.closed)
            .length,
      },
    );
    stats[pc.id] = pc;

    final peer = _activePeer;
    if (peer != null) {
      stats['outbound-rtp'] = RTCStats(
        type: 'outbound-rtp',
        id: 'outbound-rtp',
        values: {
          'packetsSent': peer.packetsSent,
          'bytesSent': peer.bytesSent,
        },
      );
      stats['inbound-rtp'] = RTCStats(
        type: 'inbound-rtp',
        id: 'inbound-rtp',
        values: {
          'packetsReceived': peer.packetsReceived,
          'bytesReceived': peer.bytesReceived,
        },
      );
      stats['transport'] = RTCStats(
        type: 'transport',
        id: 'transport',
        values: {
          'remoteAddress': peer.remoteAddress.address,
          'remotePort': peer.remotePort,
          'dtlsState': peer.isSecure ? 'connected' : 'connecting',
        },
      );
    }
    return RTCStatsReport(stats);
  }

  /// Fully tear the connection down. After this, every method throws.
  void close() {
    if (_closed) return;
    _closed = true;
    for (final t in _transceivers) {
      t.stop();
    }
    for (final ch in _dataChannels) {
      ch.close();
    }
    unawaited(_transport?.close());
    _transport = null;
    _activePeer = null;
    _setSignalingState(RTCSignalingState.closed);
    _setIceConnectionState(RTCIceConnectionState.closed);
    _setConnectionState(RTCPeerConnectionState.closed);
  }

  // ---- Internals -------------------------------------------------------

  List<SdpCodec> _defaultCodecsFor(MediaKind k) => k == MediaKind.video
      ? _config.defaultVideoCodecs
      : _config.defaultAudioCodecs;

  SdpDirection _toSdpDirection(RTCRtpTransceiverDirection d) {
    switch (d) {
      case RTCRtpTransceiverDirection.sendrecv:
        return SdpDirection.sendrecv;
      case RTCRtpTransceiverDirection.sendonly:
        return SdpDirection.sendonly;
      case RTCRtpTransceiverDirection.recvonly:
        return SdpDirection.recvonly;
      case RTCRtpTransceiverDirection.inactive:
      case RTCRtpTransceiverDirection.stopped:
        return SdpDirection.inactive;
    }
  }

  void _alignTransceiversWithOffer(Map<String, dynamic> offerMap) {
    final remoteMedia = offerMap.mediaList;
    for (var i = 0; i < remoteMedia.length; i++) {
      final m = remoteMedia[i];
      final type = (m['type'] as String?) ?? '';
      final mid = m['mid']?.toString() ?? '$i';
      final kind = type == 'video' ? MediaKind.video : MediaKind.audio;

      RTCRtpTransceiver? match;
      for (final t in _transceivers) {
        if (t.mid == mid) {
          match = t;
          break;
        }
      }
      match ??= _firstUnmatchedFor(kind);

      if (match == null) {
        // No local transceiver — synthesize a recvonly one so the answer
        // can mirror the section.
        final defaults = _defaultCodecsFor(kind);
        match = RTCRtpTransceiver(
          kind: kind,
          codecs: List.unmodifiable(
              defaults.isEmpty ? [_fallbackCodec(kind)] : defaults),
          direction: RTCRtpTransceiverDirection.recvonly,
        );
        _transceivers.add(match);
      }
      match.mid ??= mid;
    }
  }

  RTCRtpTransceiver? _firstUnmatchedFor(MediaKind kind) {
    for (final t in _transceivers) {
      if (t.kind == kind && t.mid == null) return t;
    }
    return null;
  }

  SdpCodec _fallbackCodec(MediaKind kind) =>
      kind == MediaKind.video ? Vp8Codec() : PcmuCodec();

  void _fireTrackEventsForRemote(RTCSessionDescription description) {
    if (description.type == RTCSdpType.rollback) return;
    final cb = onTrack;
    if (cb == null) return;
    final stream = MediaStream(id: _streamId);
    for (final t in _transceivers) {
      if (t.direction == RTCRtpTransceiverDirection.sendonly ||
          t.direction == RTCRtpTransceiverDirection.inactive ||
          t.direction == RTCRtpTransceiverDirection.stopped) {
        continue;
      }
      // The receiver track is created on first arrival of remote media in
      // a real impl; we synthesize it here so call sites receive an event.
      t.receiver.track ??= MediaStreamTrack(kind: t.kind);
      cb(RTCTrackEvent(
        track: t.receiver.track!,
        receiver: t.receiver,
        transceiver: t,
        streams: [stream],
      ));
    }
  }

  void _rollback({required bool local}) {
    if (local) {
      _pendingLocalDescription = null;
    } else {
      _pendingRemoteDescription = null;
    }
    _setSignalingState(RTCSignalingState.stable);
  }

  void _expectSignalingIn(Set<RTCSignalingState> allowed) {
    if (!allowed.contains(_signalingState)) {
      throw StateError('Invalid signaling state $_signalingState; '
          'expected one of $allowed');
    }
  }

  void _setSignalingState(RTCSignalingState s) {
    if (_signalingState == s) return;
    _signalingState = s;
    onSignalingStateChange?.call(s);
  }

  void _setIceConnectionState(RTCIceConnectionState s) {
    if (_iceConnectionState == s) return;
    _iceConnectionState = s;
    onIceConnectionStateChange?.call(s);
  }

  void _setConnectionState(RTCPeerConnectionState s) {
    if (_connectionState == s) return;
    _connectionState = s;
    onConnectionStateChange?.call(s);
  }

  void _setIceGatheringState(RTCIceGatheringState s) {
    if (_iceGatheringState == s) return;
    _iceGatheringState = s;
    onIceGatheringStateChange?.call(s);
  }

  void _bumpIceGatheringStarted() {
    // If a transport is bound, [bind] handles candidate emission.
    if (_transport != null) return;
    if (_iceGatheringState == RTCIceGatheringState.newState) {
      _setIceGatheringState(RTCIceGatheringState.gathering);
      // Fire the end-of-candidates sentinel asynchronously so call sites
      // see at least one onIceCandidate(null) callback even before real
      // gathering is wired up.
      scheduleMicrotask(() {
        if (_closed) return;
        onIceCandidate?.call(null);
        _setIceGatheringState(RTCIceGatheringState.complete);
      });
    }
  }

  // ---- Transport callbacks -------------------------------------------

  void _onTransportPeer(RtcPeerTransport peer) {
    _setIceConnectionState(RTCIceConnectionState.checking);
    _setConnectionState(RTCPeerConnectionState.connecting);
  }

  void _onTransportSecure(RtcPeerTransport peer) {
    _activePeer ??= peer;
    // Install the per-sender hook so RTCRtpSender.send actually flows.
    final p = _activePeer!;
    for (final t in _transceivers) {
      t.sender.sendHook = (Uint8List rtp) => _transport!.sendRtp(p, rtp);
    }
    _setIceConnectionState(RTCIceConnectionState.connected);
    _setConnectionState(RTCPeerConnectionState.connected);
    for (final ch in _dataChannels) {
      ch.markOpen();
    }
  }

  void _onTransportRtp(RtcPeerTransport peer, Uint8List rtp) {
    // Without per-SSRC routing yet, broadcast to every receiver — they
    // can filter by header inspection. Most apps with a single transceiver
    // will see the right packet.
    for (final t in _transceivers) {
      t.receiver.deliverRtp(rtp);
    }
  }

  void _onTransportRtcp(RtcPeerTransport peer, Uint8List rtcp) {
    for (final t in _transceivers) {
      t.receiver.deliverRtcp(rtcp);
    }
  }

  bool _negotiationScheduled = false;
  void _scheduleNegotiationNeeded() {
    if (_negotiationScheduled || onNegotiationNeeded == null) return;
    _negotiationScheduled = true;
    scheduleMicrotask(() {
      _negotiationScheduled = false;
      if (_closed) return;
      onNegotiationNeeded?.call();
    });
  }

  void _checkNotClosed() {
    if (_closed) throw StateError('RTCPeerConnection is closed.');
  }

  static String _randomToken(int length) {
    // ICE ufrag/pwd alphabet from RFC 5245 §15.4.
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final uuid = UuidV4().generate().replaceAll('-', '');
    final bytes = uuid.codeUnits;
    final buf = StringBuffer();
    for (var i = 0; i < length; i++) {
      buf.writeCharCode(alphabet.codeUnitAt(bytes[i % bytes.length] % 64));
    }
    return buf.toString();
  }
}

/// Parsed `stun:` / `stuns:` URL used for srflx candidate gathering.
///
/// Accepted forms (per RFC 7064):
///   `stun:host`          — defaults to port 3478
///   `stun:host:port`
///   `stuns:host[:port]`  — also recognised; transport is still UDP here
///                          since [RtcUdpTransport] is UDP-only.
///
/// `turn:` / `turns:` URLs are ignored — TURN allocation is not wired up
/// in this build.
class _StunServerEndpoint {
  final String host;
  final int port;
  const _StunServerEndpoint(this.host, this.port);

  static _StunServerEndpoint? parse(String url) {
    final colon = url.indexOf(':');
    if (colon <= 0) return null;
    final scheme = url.substring(0, colon).toLowerCase();
    if (scheme != 'stun' && scheme != 'stuns') return null;
    var rest = url.substring(colon + 1);
    // Strip any `?transport=...` query suffix.
    final q = rest.indexOf('?');
    if (q >= 0) rest = rest.substring(0, q);
    if (rest.isEmpty) return null;
    String host;
    int port;
    if (rest.startsWith('[')) {
      // IPv6 literal: [::1]:3478
      final close = rest.indexOf(']');
      if (close < 0) return null;
      host = rest.substring(1, close);
      final tail = rest.substring(close + 1);
      port = tail.startsWith(':')
          ? (int.tryParse(tail.substring(1)) ?? 3478)
          : 3478;
    } else {
      final hp = rest.split(':');
      host = hp[0];
      port = hp.length > 1 ? (int.tryParse(hp[1]) ?? 3478) : 3478;
    }
    if (host.isEmpty) return null;
    return _StunServerEndpoint(host, port);
  }
}
