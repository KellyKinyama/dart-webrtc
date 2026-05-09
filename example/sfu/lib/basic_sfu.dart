// A basic Selective Forwarding Unit (SFU).
//
// Each participant gets their own [RTCPeerConnection] bound to its own
// UDP port. The SFU does no transcoding — it just decrypts inbound
// RTP/RTCP from one participant and re-encrypts it for every other
// participant.
//
// Signaling is left to the caller: invoke [addParticipant] to create a
// peer connection, then call [createOffer]/[setRemoteDescription] on the
// returned `RTCPeerConnection` and shuttle the SDP through whatever
// transport you like (websocket, HTTP, etc.). [bin/sfu_server.dart] ships
// a minimal websocket signaling server built on this class.
//
// What this SFU does NOT do (yet):
//   * Simulcast / SVC layer selection (forwards every packet as-is).
//   * Bandwidth estimation.
//   * Authentication (anyone reaching the signaling endpoint can join).
//
// What it DOES do for RTCP feedback (NACK, PLI, REMB, FIR, SLI):
//   * Detects RTPFB (PT=205) and PSFB (PT=206) sub-packets in the inbound
//     compound RTCP, reverse-maps the *media* SSRC field back to the
//     original sender's SSRC, and forwards each feedback packet only to
//     the participant who originally produced that media stream. This
//     keeps NACK/PLI from fanning out to unrelated senders and means key
//     frame requests actually reach the right encoder.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/signal/sdp_v2.dart' show PcmuCodec, Vp8Codec;
import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

/// One connected participant.
class SfuParticipant {
  /// Caller-provided id, unique within the [BasicSfu].
  final String id;

  /// The peer connection for this participant. Use it to drive SDP
  /// negotiation (`createOffer`, `setRemoteDescription`, etc.).
  final RTCPeerConnection pc;

  /// The bound UDP transport (== `pc.transport`). Exposed so callers can
  /// inspect counters or install additional callbacks.
  final RtcUdpTransport transport;

  /// Display name, set when the participant joins. Optional metadata.
  final String? displayName;

  SfuParticipant({
    required this.id,
    required this.pc,
    required this.transport,
    this.displayName,
  });
}

/// Result of a forwarding decision — used by tests and by callers that
/// want to log or rate-limit.
class SfuForwardStats {
  int rtpForwarded = 0;
  int rtcpForwarded = 0;
  int rtpDropped = 0;
  int rtcpDropped = 0;
  int ssrcRewrites = 0;
}

/// Allocates a stable rewritten SSRC for each `(receiver, original-SSRC)`
/// pair. The same input always returns the same output, so packets keep a
/// consistent SSRC across their lifetime on a given outbound stream.
class SsrcAllocator {
  final Random _rng;

  /// receiverId -> originalSsrc -> rewrittenSsrc.
  final Map<String, Map<int, int>> _byReceiver = {};

  /// receiverId -> rewrittenSsrc -> originalSsrc (reverse map for feedback).
  final Map<String, Map<int, int>> _reverse = {};

  /// receiverId -> set of allocated rewritten SSRCs (collision avoidance).
  final Map<String, Set<int>> _allocated = {};

  SsrcAllocator({Random? rng}) : _rng = rng ?? Random.secure();

  /// Get (or allocate) the rewritten SSRC for [originalSsrc] on [receiverId].
  int rewrite(String receiverId, int originalSsrc) {
    final perReceiver = _byReceiver.putIfAbsent(receiverId, () => {});
    final cached = perReceiver[originalSsrc];
    if (cached != null) return cached;

    final used = _allocated.putIfAbsent(receiverId, () => <int>{});
    int candidate;
    do {
      candidate = _rng.nextInt(0xFFFFFFFF);
      if (candidate == 0) continue; // 0 is reserved.
    } while (used.contains(candidate));
    used.add(candidate);
    perReceiver[originalSsrc] = candidate;
    _reverse.putIfAbsent(receiverId, () => {})[candidate] = originalSsrc;
    return candidate;
  }

  /// Reverse lookup: given the SSRC the [receiverId] sees, return the
  /// original sender SSRC, or null if no mapping exists.
  int? originalFor(String receiverId, int rewrittenSsrc) =>
      _reverse[receiverId]?[rewrittenSsrc];

  /// Forget every mapping for [receiverId] (called on participant leave).
  void forgetReceiver(String receiverId) {
    _byReceiver.remove(receiverId);
    _reverse.remove(receiverId);
    _allocated.remove(receiverId);
  }
}

/// A minimal multi-party SFU.
///
/// Usage:
/// ```dart
/// final sfu = BasicSfu(address: InternetAddress.anyIPv4, basePort: 50000);
/// final p = await sfu.addParticipant('alice');
/// final offer = await p.pc.createOffer();
/// await p.pc.setLocalDescription(offer);
/// // ship offer.sdp to the browser; receive answer; then:
/// await p.pc.setRemoteDescription(remoteAnswer);
/// ```
class BasicSfu {
  /// Address every participant transport binds to.
  final InternetAddress address;

  /// Base port. Participant N is bound at `basePort + N`.
  final int basePort;

  /// If true, each participant's transceivers default to `sendrecv` so
  /// the SFU both receives and forwards. If false, only audio is enabled.
  final bool video;
  final bool audio;

  /// When true (default), every outbound RTP/RTCP packet has its sender
  /// SSRC rewritten to a per-receiver-allocated SSRC. This prevents SSRC
  /// collisions when multiple participants share the same SSRC space and
  /// gives each receiver a stable identifier per remote stream.
  final bool ssrcRewriting;

  final SsrcAllocator _ssrcAllocator = SsrcAllocator();

  /// Maps an *original* SSRC seen on the wire to the participant id that
  /// produced it. Populated lazily as RTP packets arrive; used to route
  /// reverse-mapped RTCP feedback to the right sender.
  final Map<int, String> _ssrcOwner = {};

  final Map<String, SfuParticipant> _participants = {};
  final SfuForwardStats stats = SfuForwardStats();

  /// Fired when a new participant joins.
  void Function(SfuParticipant participant)? onParticipantJoined;

  /// Fired when a participant's DTLS handshake completes.
  void Function(SfuParticipant participant)? onParticipantConnected;

  /// Fired when a participant leaves (explicit removal or close).
  void Function(SfuParticipant participant)? onParticipantLeft;

  int _nextPortOffset = 0;

  BasicSfu({
    required this.address,
    required this.basePort,
    this.video = true,
    this.audio = true,
    this.ssrcRewriting = true,
  });

  /// Snapshot of all current participants.
  List<SfuParticipant> get participants =>
      List.unmodifiable(_participants.values);

  /// Look up a participant by id.
  SfuParticipant? getParticipant(String id) => _participants[id];

  /// Add a new participant. Allocates a port, creates an
  /// [RTCPeerConnection], binds the transport, and wires the forwarding
  /// callbacks. Caller is responsible for the SDP exchange.
  Future<SfuParticipant> addParticipant(
    String id, {
    String? displayName,
    int? port,
  }) async {
    if (_participants.containsKey(id)) {
      throw StateError('Participant "$id" already exists.');
    }

    final pc = RTCPeerConnection(RTCConfiguration(
      defaultVideoCodecs: [Vp8Codec()],
      defaultAudioCodecs: [PcmuCodec()],
    ));

    if (video) pc.addTransceiver(trackOrKind: MediaKind.video);
    if (audio) pc.addTransceiver(trackOrKind: MediaKind.audio);

    final usePort = port ?? (basePort + _nextPortOffset++);
    final transport = await pc.bind(address, usePort);

    final participant = SfuParticipant(
      id: id,
      pc: pc,
      transport: transport,
      displayName: displayName,
    );
    _participants[id] = participant;

    transport.onRtp = (peer, rtp) => _forwardRtp(id, rtp);
    transport.onRtcp = (peer, rtcp) => _forwardRtcp(id, rtcp);

    pc.onConnectionStateChange = (state) {
      if (state == RTCPeerConnectionState.connected) {
        onParticipantConnected?.call(participant);
      }
    };

    onParticipantJoined?.call(participant);
    return participant;
  }

  /// Close a participant's transport and remove them.
  Future<void> removeParticipant(String id) async {
    final p = _participants.remove(id);
    if (p == null) return;
    p.pc.close();
    _ssrcAllocator.forgetReceiver(id);
    _ssrcOwner.removeWhere((_, owner) => owner == id);
    onParticipantLeft?.call(p);
  }

  /// Tear everything down.
  Future<void> close() async {
    for (final p in _participants.values.toList()) {
      p.pc.close();
      onParticipantLeft?.call(p);
    }
    _participants.clear();
  }

  // ---- Forwarding ----------------------------------------------------

  Future<void> _forwardRtp(String fromId, Uint8List rtp) async {
    // Learn the (originalSsrc -> participant) ownership the first time we
    // see this SSRC; that lets us reverse-route RTCP feedback later.
    if (rtp.length >= 12) {
      final ssrc = ByteData.sublistView(rtp).getUint32(8, Endian.big);
      _ssrcOwner[ssrc] = fromId;
    }
    for (final p in _participants.values) {
      if (p.id == fromId) continue;
      final peer = p.pc.activePeer;
      if (peer == null || !peer.isSecure) {
        stats.rtpDropped++;
        continue;
      }
      final outbound = ssrcRewriting ? _rewriteRtp(p.id, rtp) : rtp;
      final ok = await p.transport.sendRtp(peer, outbound);
      if (ok) {
        stats.rtpForwarded++;
      } else {
        stats.rtpDropped++;
      }
    }
  }

  Future<void> _forwardRtcp(String fromId, Uint8List rtcp) async {
    if (!ssrcRewriting) {
      // No rewriting at all — broadcast verbatim.
      for (final p in _participants.values) {
        if (p.id == fromId) continue;
        final peer = p.pc.activePeer;
        if (peer == null || !peer.isSecure) {
          stats.rtcpDropped++;
          continue;
        }
        final ok = await p.transport.sendRtcp(peer, rtcp);
        if (ok) {
          stats.rtcpForwarded++;
        } else {
          stats.rtcpDropped++;
        }
      }
      return;
    }

    // Walk the compound RTCP. Split into:
    //   * `broadcastParts`: SR / RR / SDES / BYE / APP — sent to every
    //     other participant with sender-SSRC rewritten per receiver.
    //   * `targeted[ownerId]`: feedback (RTPFB=205, PSFB=206) sub-packets
    //     whose media-SSRC reverse-maps to a known sender; restored to the
    //     original media SSRC and sent only to that sender.
    final broadcastParts = <Uint8List>[];
    final targeted = <String, BytesBuilder>{};
    var offset = 0;
    while (offset + 4 <= rtcp.length) {
      final lengthWords =
          ByteData.sublistView(rtcp, offset + 2, offset + 4).getUint16(0);
      final subLen = (lengthWords + 1) * 4;
      if (subLen <= 0 || offset + subLen > rtcp.length) break;
      final pt = rtcp[offset + 1];
      final sub = Uint8List.sublistView(rtcp, offset, offset + subLen);

      final isFeedback = pt == 205 || pt == 206;
      if (isFeedback && subLen >= 12) {
        final rewrittenMedia =
            ByteData.sublistView(sub).getUint32(8, Endian.big);
        final original = _ssrcAllocator.originalFor(fromId, rewrittenMedia);
        final ownerId = original == null ? null : _ssrcOwner[original];
        if (original != null && ownerId != null && ownerId != fromId) {
          // Restore the media SSRC to the value the owner expects.
          final restored = Uint8List.fromList(sub);
          ByteData.sublistView(restored).setUint32(8, original, Endian.big);
          targeted.putIfAbsent(ownerId, () => BytesBuilder()).add(restored);
        } else {
          // Unmappable feedback (e.g. before the first RTP packet from
          // the targeted sender has been seen). Drop silently.
          stats.rtcpDropped++;
        }
      } else {
        broadcastParts.add(sub);
      }
      offset += subLen;
    }

    // Broadcast the non-feedback parts (with sender-SSRC rewriting).
    if (broadcastParts.isNotEmpty) {
      final compound = _concat(broadcastParts);
      for (final p in _participants.values) {
        if (p.id == fromId) continue;
        final peer = p.pc.activePeer;
        if (peer == null || !peer.isSecure) {
          stats.rtcpDropped++;
          continue;
        }
        final outbound = _rewriteRtcp(p.id, compound);
        final ok = await p.transport.sendRtcp(peer, outbound);
        if (ok) {
          stats.rtcpForwarded++;
        } else {
          stats.rtcpDropped++;
        }
      }
    }

    // Send targeted feedback to the originating sender only.
    for (final entry in targeted.entries) {
      final p = _participants[entry.key];
      if (p == null) continue;
      final peer = p.pc.activePeer;
      if (peer == null || !peer.isSecure) {
        stats.rtcpDropped++;
        continue;
      }
      final ok = await p.transport.sendRtcp(peer, entry.value.toBytes());
      if (ok) {
        stats.rtcpForwarded++;
      } else {
        stats.rtcpDropped++;
      }
    }
  }

  static Uint8List _concat(List<Uint8List> parts) {
    var total = 0;
    for (final p in parts) {
      total += p.length;
    }
    final out = Uint8List(total);
    var pos = 0;
    for (final p in parts) {
      out.setRange(pos, pos + p.length, p);
      pos += p.length;
    }
    return out;
  }

  // ---- SSRC rewriting ------------------------------------------------

  /// Rewrites the SSRC field (bytes 8..12, big-endian) of an RTP packet so
  /// that [receiverId] sees a stable per-stream SSRC instead of the
  /// original sender's SSRC.
  Uint8List _rewriteRtp(String receiverId, Uint8List rtp) {
    if (rtp.length < 12) return rtp;
    final original = ByteData.sublistView(rtp).getUint32(8, Endian.big);
    final rewritten = _ssrcAllocator.rewrite(receiverId, original);
    if (rewritten == original) return rtp;
    final out = Uint8List.fromList(rtp);
    ByteData.sublistView(out).setUint32(8, rewritten, Endian.big);
    stats.ssrcRewrites++;
    return out;
  }

  /// Rewrites the sender SSRC (bytes 4..8) of every sub-packet in a
  /// compound RTCP packet. Each sub-packet's length is its `length` field
  /// (bytes 2..3, in 32-bit words minus 1) so we can walk the whole
  /// compound deterministically.
  Uint8List _rewriteRtcp(String receiverId, Uint8List rtcp) {
    if (rtcp.length < 8) return rtcp;
    final out = Uint8List.fromList(rtcp);
    final view = ByteData.sublistView(out);
    var offset = 0;
    var rewroteAny = false;
    while (offset + 8 <= out.length) {
      final lengthWords = view.getUint16(offset + 2, Endian.big);
      final subLen = (lengthWords + 1) * 4;
      if (subLen <= 0 || offset + subLen > out.length) break;
      final original = view.getUint32(offset + 4, Endian.big);
      if (original != 0) {
        final rewritten = _ssrcAllocator.rewrite(receiverId, original);
        if (rewritten != original) {
          view.setUint32(offset + 4, rewritten, Endian.big);
          rewroteAny = true;
        }
      }
      offset += subLen;
    }
    if (rewroteAny) stats.ssrcRewrites++;
    return out;
  }
}
