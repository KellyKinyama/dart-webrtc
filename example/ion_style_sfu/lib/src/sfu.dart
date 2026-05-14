// Top-level SFU engine. Mirrors `pkg/sfu/sfu.go` in shape: holds the
// shared configuration, the session registry, and acts as a
// `SessionProvider` to peers.

import 'dart:async';
import 'dart:io';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

import 'peer.dart';
import 'session.dart';

/// Configuration for the WebRTC transports the SFU creates.
///
/// Phase 1 only honours [bindAddress], [rtpBasePort], and [announceAddress].
/// Later phases will surface ICE timeouts, TURN, simulcast policy, etc.
class WebRTCTransportConfig {
  /// Address every UDP transport binds on.
  final InternetAddress bindAddress;

  /// First UDP port to allocate. Each new peer transport (publisher and
  /// subscriber are separate transports) uses [rtpBasePort] + N.
  final int rtpBasePort;

  /// Optional override for the host candidate address (for NAT / wildcard
  /// binds). Falls back to the host's first non-loopback IPv4.
  final InternetAddress? announceAddress;

  /// Codecs every transceiver defaults to. Matches the codec set the
  /// publisher tracks use.
  final List<SdpCodec> defaultVideoCodecs;
  final List<SdpCodec> defaultAudioCodecs;

  const WebRTCTransportConfig({
    required this.bindAddress,
    required this.rtpBasePort,
    this.announceAddress,
    this.defaultVideoCodecs = const [],
    this.defaultAudioCodecs = const [],
  });
}

/// Top-level SFU engine. One per Dart isolate.
///
/// Equivalent to ion-sfu's `SFU` struct. Holds a session registry; new
/// peers fetch (or auto-create) their session via [getSession].
class Sfu implements SessionProvider {
  final WebRTCTransportConfig config;

  /// sessionId → Session.
  final Map<String, Session> _sessions = {};

  /// Monotonic counter feeding `rtpBasePort + _nextPortOffset`. We use
  /// distinct ports per transport (publisher and subscriber are separate
  /// PeerConnections, each with its own UDP socket).
  int _nextPortOffset = 0;

  Sfu(this.config);

  /// Allocate the next UDP port. Phase 8 (multi-isolate) will switch
  /// this to bind on port 0 and read back the OS-picked port.
  int allocatePort() => config.rtpBasePort + _nextPortOffset++;

  @override
  Session getSession(String sid) =>
      _sessions.putIfAbsent(sid, () => Session(sid, this));

  /// Snapshot of the live sessions (for stats / introspection).
  Iterable<Session> get sessions => _sessions.values;

  /// Forget a session that has gone idle. Called by [Session] when its
  /// peer count drops to zero.
  void removeSession(String sid) {
    _sessions.remove(sid);
  }

  /// Tear every session down.
  Future<void> close() async {
    final all = _sessions.values.toList();
    _sessions.clear();
    await Future.wait(all.map((s) => s.close()));
  }
}

/// Hook exposed by the SFU so peers can resolve their session.
///
/// Mirrors `sfu.SessionProvider`. Tests / wrappers can substitute their
/// own implementation.
abstract class SessionProvider {
  Session getSession(String sid);
}

/// Allocate a [Peer] bound to [sid] inside [provider]'s session
/// registry. Equivalent to `sfu.NewPeer(provider).Join(sid, uid)`.
Future<Peer> joinPeer(
  SessionProvider provider, {
  required String sid,
  required String uid,
  PeerJoinConfig joinConfig = const PeerJoinConfig(),
}) async {
  final peer = Peer(provider);
  await peer.join(sid: sid, uid: uid, joinConfig: joinConfig);
  return peer;
}
