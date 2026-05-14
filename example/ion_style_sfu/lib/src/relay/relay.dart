// Phase 6 — SFU-to-SFU relay.
//
// Mirrors `pkg/relay/` from pion ion-sfu. A [RelayPeer] represents a
// remote SFU's publisher as a virtual peer in our local [Session]: its
// tracks publish into the session just like a browser-side publisher,
// so every existing [Subscriber] fans them out unchanged.
//
// Signaling moves over a compact JSON envelope instead of full SDP —
// the link pre-agrees the codec set via [RelayStreamDescriptor] and
// skips SDP renegotiation entirely on the relay hop.

import 'dart:async';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart' show MediaKind;

import '../producer_layer.dart';
import '../producer_stream.dart';
import '../receiver.dart';
import '../router.dart';
import '../session.dart';

/// One encoding layer of a relayed stream. Mirrors [ProducerLayer]
/// over the wire.
class RelayLayerDescriptor {
  final String rid;
  final int primarySsrc;
  final int? rtxSsrc;

  const RelayLayerDescriptor({
    required this.rid,
    required this.primarySsrc,
    this.rtxSsrc,
  });

  Map<String, Object?> toJson() => {
        'rid': rid,
        'primarySsrc': primarySsrc,
        if (rtxSsrc != null) 'rtxSsrc': rtxSsrc,
      };

  factory RelayLayerDescriptor.fromJson(Map<String, Object?> j) =>
      RelayLayerDescriptor(
        rid: (j['rid'] as String?) ?? '',
        primarySsrc: (j['primarySsrc'] as num).toInt(),
        rtxSsrc: (j['rtxSsrc'] as num?)?.toInt(),
      );
}

/// Compact stream announcement sent over the relay control channel.
class RelayStreamDescriptor {
  final String mid;
  final String kind; // 'audio' | 'video'
  final List<RelayLayerDescriptor> layers;
  final String cname;
  final String msidStream;
  final String msidTrack;
  final int? ridExtId;
  final int? repairedRidExtId;
  final int? audioLevelExtId;
  final int? twccExtId;

  const RelayStreamDescriptor({
    required this.mid,
    required this.kind,
    required this.layers,
    required this.cname,
    required this.msidStream,
    required this.msidTrack,
    this.ridExtId,
    this.repairedRidExtId,
    this.audioLevelExtId,
    this.twccExtId,
  });

  bool get isSimulcast => layers.length > 1;

  Map<String, Object?> toJson() => {
        'mid': mid,
        'kind': kind,
        'layers': [for (final l in layers) l.toJson()],
        'cname': cname,
        'msidStream': msidStream,
        'msidTrack': msidTrack,
        if (ridExtId != null) 'ridExtId': ridExtId,
        if (repairedRidExtId != null) 'repairedRidExtId': repairedRidExtId,
        if (audioLevelExtId != null) 'audioLevelExtId': audioLevelExtId,
        if (twccExtId != null) 'twccExtId': twccExtId,
      };

  factory RelayStreamDescriptor.fromJson(Map<String, Object?> j) =>
      RelayStreamDescriptor(
        mid: j['mid'] as String,
        kind: j['kind'] as String,
        layers: [
          for (final l in (j['layers'] as List).cast<Map<String, Object?>>())
            RelayLayerDescriptor.fromJson(l),
        ],
        cname: (j['cname'] as String?) ?? '',
        msidStream: (j['msidStream'] as String?) ?? '',
        msidTrack: (j['msidTrack'] as String?) ?? '',
        ridExtId: (j['ridExtId'] as num?)?.toInt(),
        repairedRidExtId: (j['repairedRidExtId'] as num?)?.toInt(),
        audioLevelExtId: (j['audioLevelExtId'] as num?)?.toInt(),
        twccExtId: (j['twccExtId'] as num?)?.toInt(),
      );

  /// Convert to a local [ProducerStream]. Equivalent to what
  /// `parsePublisherOffer` would produce for a browser publisher.
  ProducerStream toProducerStream() {
    final ls = [
      for (final l in layers)
        ProducerLayer(
          rid: l.rid,
          primarySsrc: l.primarySsrc,
          rtxSsrc: l.rtxSsrc,
        ),
    ];
    if (ls.length == 1 && ls.first.rid.isEmpty) {
      return ProducerStream(
        kind: kind,
        mid: mid,
        primarySsrc: ls.first.primarySsrc,
        rtxSsrc: ls.first.rtxSsrc,
        cname: cname,
        msidStream: msidStream,
        msidTrack: msidTrack,
        audioLevelExtId: audioLevelExtId,
        twccExtId: twccExtId,
      );
    }
    return ProducerStream.simulcast(
      kind: kind,
      mid: mid,
      layers: ls,
      cname: cname,
      msidStream: msidStream,
      msidTrack: msidTrack,
      ridExtId: ridExtId,
      repairedRidExtId: repairedRidExtId,
      audioLevelExtId: audioLevelExtId,
      twccExtId: twccExtId,
    );
  }
}

/// Pluggable transport between two SFUs. In production this wraps a
/// UDP socket (optionally tunneled through DTLS); for tests use
/// [InMemoryRelayPipe].
abstract class RelayTransport {
  /// Ship a JSON control envelope to the peer.
  void sendControl(Map<String, Object?> msg);

  /// Ship an RTP packet to the peer.
  void sendRtp(Uint8List pkt);

  /// Ship an RTCP packet to the peer (NACK, PLI, REMB, …).
  void sendRtcp(Uint8List pkt);

  /// Inbound sinks. Owners set these after construction.
  set onControl(void Function(Map<String, Object?> msg) cb);
  set onRtp(void Function(Uint8List pkt) cb);
  set onRtcp(void Function(Uint8List pkt) cb);

  Future<void> close();
}

/// A pair of in-process [RelayTransport]s wired back-to-back. Useful
/// for unit tests and same-process cascades.
class InMemoryRelayPipe {
  late final RelayTransport a;
  late final RelayTransport b;

  InMemoryRelayPipe() {
    final endA = _InMemoryRelayEnd();
    final endB = _InMemoryRelayEnd();
    endA._peer = endB;
    endB._peer = endA;
    a = endA;
    b = endB;
  }
}

class _InMemoryRelayEnd implements RelayTransport {
  _InMemoryRelayEnd? _peer;
  void Function(Map<String, Object?>)? _onControl;
  void Function(Uint8List)? _onRtp;
  void Function(Uint8List)? _onRtcp;
  bool _closed = false;

  @override
  set onControl(void Function(Map<String, Object?>) cb) => _onControl = cb;
  @override
  set onRtp(void Function(Uint8List) cb) => _onRtp = cb;
  @override
  set onRtcp(void Function(Uint8List) cb) => _onRtcp = cb;

  @override
  void sendControl(Map<String, Object?> msg) {
    if (_closed) return;
    _peer?._onControl?.call(msg);
  }

  @override
  void sendRtp(Uint8List pkt) {
    if (_closed) return;
    _peer?._onRtp?.call(pkt);
  }

  @override
  void sendRtcp(Uint8List pkt) {
    if (_closed) return;
    _peer?._onRtcp?.call(pkt);
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}

/// Control-envelope types exchanged on a relay link.
abstract class RelayMsgType {
  static const hello = 'hello';
  static const helloAck = 'hello-ack';
  static const announce = 'announce';
  static const remove = 'remove';
  static const bye = 'bye';
}

/// One half of a relay link.
///
/// Wraps a [RelayTransport]: on the *downstream* side, inbound RTP/RTCP
/// is fed to a local [Router] (which publishes into the local [Session]
/// just like a browser publisher would). On the *origin* side, the same
/// peer can [announce]/[forwardRtp] to export tracks upstream and
/// receives upstream NACK/PLI from the downstream peer over the same
/// transport.
class RelayPeer {
  /// Stable id of the remote peer this relay represents. Becomes the
  /// `peerId` of the virtual publisher when this side is downstream.
  final String remoteId;

  /// Local session this relay publishes into.
  final Session session;

  /// Transport carrying control + media to/from the upstream SFU.
  final RelayTransport transport;

  /// Router owning the relayed receivers. One per relay peer.
  late final Router router;

  /// True once the hello handshake has completed.
  bool established = false;

  /// mid → Receiver for relayed streams currently published locally.
  final Map<String, Receiver> _byMid = {};

  /// Fired when the handshake completes.
  void Function()? onEstablished;

  /// Fired for each stream announced by the remote SFU (downstream
  /// side).
  void Function(Receiver receiver)? onRelayedStream;

  /// Fired when the remote SFU sends an RTCP packet back upstream
  /// (typically NACK or PLI). Origin-side users hook this to feed the
  /// feedback into their local publisher.
  void Function(Uint8List rtcp)? onUpstreamRtcp;

  /// Fired exactly once when this relay peer transitions to the
  /// closed state — either because [close] was called locally or
  /// because the remote sent a `bye` control frame.
  void Function()? onClosed;

  bool _closed = false;

  RelayPeer._({
    required this.remoteId,
    required this.session,
    required this.transport,
  }) {
    router = Router(peerId: remoteId, session: session);
    // Upstream NACK/PLI generated by the local router → forward over
    // the link so the origin SFU can NACK/PLI its real publisher.
    router.onUpstreamFeedback = (pkt) {
      if (_closed) return;
      transport.sendRtcp(pkt);
    };
    transport.onControl = _onControl;
    transport.onRtp = _onRtp;
    transport.onRtcp = _onRtcp;
  }

  /// Build a relay peer bound to [transport].
  factory RelayPeer.over({
    required String remoteId,
    required Session session,
    required RelayTransport transport,
  }) =>
      RelayPeer._(
        remoteId: remoteId,
        session: session,
        transport: transport,
      );

  bool get isClosed => _closed;

  /// All receivers currently published into the local session by this
  /// relay peer.
  Iterable<Receiver> get relayedReceivers => _byMid.values;

  /// Send the initial 'hello' envelope. The responder replies with
  /// 'hello-ack' and either side may begin announcing.
  void start() {
    if (_closed) return;
    transport.sendControl({
      'type': RelayMsgType.hello,
      'remoteId': remoteId,
    });
  }

  /// Announce one of this SFU's tracks to the upstream peer. Used on
  /// the *origin* side when this SFU is exporting media.
  void announce(RelayStreamDescriptor desc) {
    if (_closed) return;
    transport.sendControl({
      'type': RelayMsgType.announce,
      'stream': desc.toJson(),
    });
  }

  /// Tell the peer that [mid] is gone.
  void unannounce(String mid) {
    if (_closed) return;
    transport.sendControl({
      'type': RelayMsgType.remove,
      'mid': mid,
    });
  }

  /// Forward an RTP packet over the link (origin side).
  void forwardRtp(Uint8List pkt) {
    if (_closed) return;
    transport.sendRtp(pkt);
  }

  /// Forward an RTCP packet over the link (origin side).
  void forwardRtcp(Uint8List pkt) {
    if (_closed) return;
    transport.sendRtcp(pkt);
  }

  /// Phase 6b — tap [receiver], announce it to the peer, and forward
  /// every inbound RTP/RTCP packet up the link. Returns a handle the
  /// caller can use to stop exporting (which also sends an
  /// `unannounce`).
  ///
  /// The relayed stream is announced with the receiver's *upstream*
  /// SSRCs untouched, so the downstream SFU's [Router] will index the
  /// same SSRC space as the publisher.
  RelayExport exportReceiver(Receiver receiver, {String? mid}) {
    final exportMid = mid ?? receiver.stream.mid;
    final desc = RelayStreamDescriptor(
      mid: exportMid,
      kind: receiver.kind.name,
      layers: [
        for (final l in receiver.stream.layers)
          RelayLayerDescriptor(
            rid: l.rid,
            primarySsrc: l.primarySsrc,
            rtxSsrc: l.rtxSsrc,
          ),
      ],
      cname: receiver.stream.cname,
      msidStream: receiver.stream.msidStream,
      msidTrack: receiver.stream.msidTrack,
      ridExtId: receiver.stream.ridExtId,
      repairedRidExtId: receiver.stream.repairedRidExtId,
      audioLevelExtId: receiver.stream.audioLevelExtId,
      twccExtId: receiver.stream.twccExtId,
    );
    announce(desc);
    final removeRtp = receiver.addRtpTap(forwardRtp);
    final removeRtcp = receiver.addRtcpTap(forwardRtcp);
    final exp = RelayExport._(
      relay: this,
      mid: exportMid,
      receiver: receiver,
      removeRtpTap: removeRtp,
      removeRtcpTap: removeRtcp,
    );
    _exports[exportMid] = exp;
    return exp;
  }

  /// Active exports keyed by mid (origin side).
  final Map<String, RelayExport> _exports = {};

  /// Snapshot of active exports on this side.
  Iterable<RelayExport> get exports => _exports.values;

  // ---------------------------------------------------------------- inbound

  void _onControl(Map<String, Object?> msg) {
    if (_closed) return;
    final type = msg['type'] as String?;
    switch (type) {
      case RelayMsgType.hello:
        transport.sendControl({
          'type': RelayMsgType.helloAck,
          'remoteId': remoteId,
        });
        if (!established) {
          established = true;
          onEstablished?.call();
        }
        break;
      case RelayMsgType.helloAck:
        if (!established) {
          established = true;
          onEstablished?.call();
        }
        break;
      case RelayMsgType.announce:
        final stream = msg['stream'] as Map<String, Object?>?;
        if (stream == null) return;
        _ingestAnnounce(RelayStreamDescriptor.fromJson(stream));
        break;
      case RelayMsgType.remove:
        final mid = msg['mid'] as String?;
        if (mid != null) _ingestRemove(mid);
        break;
      case RelayMsgType.bye:
        close();
        break;
    }
  }

  void _ingestAnnounce(RelayStreamDescriptor desc) {
    if (_byMid.containsKey(desc.mid)) return; // idempotent
    final stream = desc.toProducerStream();
    final receiver = router.publishRelayedStream(
      kind: desc.kind == 'video' ? MediaKind.video : MediaKind.audio,
      stream: stream,
    );
    _byMid[desc.mid] = receiver;
    onRelayedStream?.call(receiver);
  }

  void _ingestRemove(String mid) {
    final receiver = _byMid.remove(mid);
    if (receiver == null) return;
    router.removeReceiver(receiver);
  }

  void _onRtp(Uint8List pkt) {
    if (_closed) return;
    router.routeRtp(pkt);
  }

  void _onRtcp(Uint8List pkt) {
    if (_closed) return;
    // Inbound RTCP on this side is either (a) sender reports / REMB
    // from upstream — feed into router, or (b) NACK/PLI from
    // downstream — surface to the user via [onUpstreamRtcp].
    onUpstreamRtcp?.call(pkt);
    router.routeRtcp(pkt);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final e in _exports.values.toList()) {
      e._teardownLocal();
    }
    _exports.clear();
    try {
      transport.sendControl({'type': RelayMsgType.bye});
    } catch (_) {
      // ignore — transport may already be down
    }
    router.close();
    await transport.close();
    try {
      onClosed?.call();
    } catch (_) {}
  }
}

/// Handle returned by [RelayPeer.exportReceiver]. Calling [stop]
/// detaches the taps and sends an `unannounce` to the peer.
class RelayExport {
  final RelayPeer relay;
  final String mid;
  final Receiver receiver;
  final void Function() _removeRtpTap;
  final void Function() _removeRtcpTap;
  bool _stopped = false;

  RelayExport._({
    required this.relay,
    required this.mid,
    required this.receiver,
    required void Function() removeRtpTap,
    required void Function() removeRtcpTap,
  })  : _removeRtpTap = removeRtpTap,
        _removeRtcpTap = removeRtcpTap;

  bool get isStopped => _stopped;

  /// Detach the taps and unannounce the stream.
  void stop() {
    if (_stopped) return;
    _teardownLocal();
    if (!relay.isClosed) {
      relay.unannounce(mid);
      relay._exports.remove(mid);
    }
  }

  void _teardownLocal() {
    if (_stopped) return;
    _stopped = true;
    _removeRtpTap();
    _removeRtcpTap();
  }
}
