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

import 'package:pure_dart_webrtc/signal/sdp_v2.dart'
    show PcmuCodec, Vp8Codec, parseSdp, writeSdp, SdpMediaMap, SdpSessionMap;
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

/// One stream a participant is producing, learned from their offer SDP.
class SfuProducerStream {
  /// `'video'` or `'audio'`.
  final String kind;

  /// Primary RTP SSRC (the one carrying media).
  final int primarySsrc;

  /// Paired RTX SSRC, or null if no FID group was declared.
  final int? rtxSsrc;

  /// `a=ssrc:<id> cname:<value>` value, defaults to the participant id
  /// if the offer didn't declare one.
  final String cname;

  /// Producer's mid (used purely for diagnostics).
  final String mid;

  /// MediaStream id (the first token of `a=ssrc:<id> msid:<s> <t>`). Lets
  /// receiving browsers group all of one producer's tracks under the same
  /// `MediaStream`. Defaults to the producer participant id when the
  /// offer didn't declare an msid.
  final String msidStream;

  /// MediaStream track id (the second token of msid). Defaults to
  /// `<participantId>-<kind>-<mid>` so each track is unique.
  final String msidTrack;

  const SfuProducerStream({
    required this.kind,
    required this.primarySsrc,
    required this.rtxSsrc,
    required this.cname,
    required this.mid,
    required this.msidStream,
    required this.msidTrack,
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

  /// Subset of [rtpForwarded] that were RTX retransmissions (RFC 4588).
  int rtxForwarded = 0;

  /// PLI (Picture Loss Indication, PSFB FMT=1) packets the SFU
  /// generated and sent to a producer.
  int pliSent = 0;
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

  /// Allocate a rewritten SSRC for [originalRtxSsrc] that is *paired* with
  /// the rewritten SSRC of [primaryOriginalSsrc] on [receiverId]. The
  /// pairing is guaranteed to be stable: if the primary's rewritten value
  /// is `P`, the RTX's rewritten value will be allocated such that the
  /// allocator can reproduce both halves of the FID group on demand.
  ///
  /// Returns the rewritten RTX SSRC.
  int rewriteRtx(
      String receiverId, int primaryOriginalSsrc, int originalRtxSsrc) {
    // Force the primary to be allocated first so callers can recover the
    // pair via [rewrite(receiverId, primaryOriginalSsrc)] later.
    rewrite(receiverId, primaryOriginalSsrc);
    return rewrite(receiverId, originalRtxSsrc);
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

  /// `producerId -> rtxSsrc -> primarySsrc`, learned from each
  /// participant's offer SDP via `a=ssrc-group:FID`. Lets the forwarder
  /// recognize an inbound RTX packet and pair it with its primary on the
  /// receiver side.
  final Map<String, Map<int, int>> _rtxToPrimary = {};

  /// `producerId -> producing streams`, learned from each participant's
  /// offer SDP. Used by [augmentAnswerSdp] to declare per-receiver SSRCs
  /// (and FID groups) up-front in the answer, so browsers can pair primary
  /// and RTX SSRCs before the first packet arrives.
  final Map<String, List<SfuProducerStream>> _producers = {};

  final Map<String, SfuParticipant> _participants = {};
  final SfuForwardStats stats = SfuForwardStats();

  /// Fired when a new participant joins.
  void Function(SfuParticipant participant)? onParticipantJoined;

  /// Fired when a participant's DTLS handshake completes.
  void Function(SfuParticipant participant)? onParticipantConnected;

  /// Fired when a participant leaves (explicit removal or close).
  void Function(SfuParticipant participant)? onParticipantLeft;

  /// Fired after [learnSsrcMappingFromOffer] discovers one or more *new*
  /// producer streams for a participant. Signaling layers use this to
  /// trigger a renegotiation on every other participant so their answer
  /// SDPs pick up the new producer's FID/msid lines.
  void Function(String producerId, List<SfuProducerStream> newStreams)?
      onProducersChanged;

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
        // Ask every other producer for an immediate keyframe so this
        // newly-connected participant starts decoding without waiting
        // for the next natural keyframe interval.
        for (final otherId in _producers.keys) {
          if (otherId == id) continue;
          requestKeyframe(otherId);
        }
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
    _rtxToPrimary.remove(id);
    _producers.remove(id);
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

  /// Send a Picture Loss Indication (PSFB, PT=206, FMT=1, RFC 4585) to
  /// every video stream that [producerId] is producing. The producer's
  /// encoder responds by emitting a keyframe on its next frame.
  ///
  /// Returns the number of PLI packets actually sent (zero if the
  /// producer has no DTLS-secure peer yet, or has no video producers).
  Future<int> requestKeyframe(String producerId) async {
    final p = _participants[producerId];
    if (p == null) return 0;
    final peer = p.pc.activePeer;
    if (peer == null || !peer.isSecure) return 0;
    final streams = _producers[producerId];
    if (streams == null) return 0;
    var sent = 0;
    // Sender SSRC of the PLI is arbitrary (the spec lets it be 0); use
    // 1 to make wireshark happy.
    const senderSsrc = 1;
    for (final s in streams) {
      if (s.kind != 'video') continue;
      final pli = _buildPli(senderSsrc, s.primarySsrc);
      final ok = await p.transport.sendRtcp(peer, pli);
      if (ok) {
        sent++;
        stats.pliSent++;
      } else {
        stats.rtcpDropped++;
      }
    }
    return sent;
  }

  /// Build one RTCP PLI sub-packet:
  ///   V=2, P=0, FMT=1, PT=206, length=2, sender-SSRC, media-SSRC.
  static Uint8List _buildPli(int senderSsrc, int mediaSsrc) {
    final out = Uint8List(12);
    final bd = ByteData.sublistView(out);
    out[0] = 0x80 | 1; // V=2, P=0, FMT=1
    out[1] = 206; // PSFB
    bd.setUint16(2, 2, Endian.big); // length=2 → 12 bytes total
    bd.setUint32(4, senderSsrc, Endian.big);
    bd.setUint32(8, mediaSsrc, Endian.big);
    return out;
  }

  /// Parse a participant's offer SDP and learn its `a=ssrc-group:FID`
  /// entries, so the forwarder can recognize that participant's RTX
  /// retransmissions and keep the FID pairing on every receiver.
  ///
  /// Also records the participant's producing streams (primary + paired
  /// RTX SSRC, cname, kind) so that [augmentAnswerSdp] can declare them
  /// in every other participant's answer.
  ///
  /// Safe to call multiple times — mappings accumulate. No-op if the SDP
  /// has no FID groups.
  void learnSsrcMappingFromOffer(String participantId, String offerSdp) {
    final session = parseSdp(offerSdp);
    final perPart = _rtxToPrimary.putIfAbsent(participantId, () => {});
    final producers = _producers.putIfAbsent(participantId, () => []);
    final seen = {for (final s in producers) s.primarySsrc};
    final addedAcross = <SfuProducerStream>[];
    for (final m in session.mediaList) {
      perPart.addAll(m.rtxToPrimarySsrc);
      final kind = (m['type'] as String?) ?? '';
      if (kind != 'video' && kind != 'audio') continue;
      final mid = m['mid']?.toString() ?? '';
      final rtxToPrimary = m.rtxToPrimarySsrc;
      final primaryToRtx = <int, int>{
        for (final e in rtxToPrimary.entries) e.value: e.key,
      };
      final cnames = <int, String>{};
      final msids = <int, String>{}; // raw `<stream> <track>` per ssrc.
      for (final s in (m['ssrcs'] as List?)?.cast<Map>() ?? const []) {
        final id = s['id'];
        final val = s['value']?.toString();
        final attr = s['attribute'];
        int? n;
        if (id is int) {
          n = id;
        } else if (id is String) {
          n = int.tryParse(id);
        }
        if (n == null || val == null) continue;
        if (attr == 'cname') cnames[n] = val;
        if (attr == 'msid') msids[n] = val;
      }
      // Primary SSRCs are everything in the section's ssrc set that
      // *isn't* on the RTX side of an FID group.
      final rtxSsrcs = rtxToPrimary.keys.toSet();
      final added = <SfuProducerStream>[];
      for (final ssrc in m.ssrcSet) {
        if (rtxSsrcs.contains(ssrc)) continue;
        if (seen.contains(ssrc)) continue;
        // Parse msid into stream + track if declared, else synthesize.
        String streamId = participantId;
        String trackId = '$participantId-$kind-$mid';
        final raw = msids[ssrc];
        if (raw != null) {
          final parts = raw.split(RegExp(r'\s+'));
          if (parts.isNotEmpty && parts[0].isNotEmpty) streamId = parts[0];
          if (parts.length > 1 && parts[1].isNotEmpty) trackId = parts[1];
        }
        final stream = SfuProducerStream(
          kind: kind,
          primarySsrc: ssrc,
          rtxSsrc: primaryToRtx[ssrc],
          cname: cnames[ssrc] ?? participantId,
          mid: mid,
          msidStream: streamId,
          msidTrack: trackId,
        );
        producers.add(stream);
        added.add(stream);
        seen.add(ssrc);
      }
      addedAcross.addAll(added);
    }
    if (addedAcross.isNotEmpty) {
      onProducersChanged?.call(participantId, List.unmodifiable(addedAcross));
      // Producer just (re)declared one or more streams. Ask them for an
      // immediate keyframe so any *already-connected* peer can decode
      // without waiting for the next natural keyframe interval. Safe
      // no-op when the producer's DTLS isn't up yet.
      // ignore: discarded_futures
      requestKeyframe(participantId);
    }
  }

  /// Snapshot of the streams [participantId] is producing, as learned
  /// from their offer SDP.
  List<SfuProducerStream> producersOf(String participantId) =>
      List.unmodifiable(_producers[participantId] ?? const []);

  /// Returns [answerSdp] augmented with `a=ssrc-group:FID` and `a=ssrc:`
  /// lines describing every other participant's streams as they will be
  /// rewritten for [receiverId]. Browsers parse these to pair primary and
  /// RTX SSRCs before any RTP arrives.
  ///
  /// If the SDP has no media sections or no other producers exist, the
  /// returned SDP is unchanged.
  String augmentAnswerSdp(String receiverId, String answerSdp) {
    final session = parseSdp(answerSdp);
    final media = session.mediaList;
    if (media.isEmpty) return answerSdp;

    var changed = false;
    for (final m in media) {
      final kind = (m['type'] as String?) ?? '';
      if (kind != 'video' && kind != 'audio') continue;
      // PT=0 means we rejected this section; skip.
      if (m['port'] == 0) continue;

      final ssrcs = (m['ssrcs'] as List?) ?? <Map<String, dynamic>>[];
      final groups = (m['ssrcGroups'] as List?) ?? <Map<String, dynamic>>[];

      for (final entry in _producers.entries) {
        if (entry.key == receiverId) continue;
        for (final stream in entry.value) {
          if (stream.kind != kind) continue;
          final rwPrimary =
              _ssrcAllocator.rewrite(receiverId, stream.primarySsrc);
          int? rwRtx;
          if (stream.rtxSsrc != null) {
            rwRtx = _ssrcAllocator.rewriteRtx(
              receiverId,
              stream.primarySsrc,
              stream.rtxSsrc!,
            );
          }
          ssrcs.add({
            'id': rwPrimary,
            'attribute': 'cname',
            'value': stream.cname,
          });
          ssrcs.add({
            'id': rwPrimary,
            'attribute': 'msid',
            'value': '${stream.msidStream} ${stream.msidTrack}',
          });
          if (rwRtx != null) {
            ssrcs.add({
              'id': rwRtx,
              'attribute': 'cname',
              'value': stream.cname,
            });
            ssrcs.add({
              'id': rwRtx,
              'attribute': 'msid',
              'value': '${stream.msidStream} ${stream.msidTrack}',
            });
            groups.add({
              'semantics': 'FID',
              'ssrcs': '$rwPrimary $rwRtx',
            });
          }
          changed = true;
        }
      }

      if (ssrcs.isNotEmpty) m['ssrcs'] = ssrcs;
      if (groups.isNotEmpty) m['ssrcGroups'] = groups;
    }

    if (!changed) return answerSdp;
    return writeSdp(session);
  }

  // ---- Forwarding ----------------------------------------------------

  Future<void> _forwardRtp(String fromId, Uint8List rtp) async {
    // Learn the (originalSsrc -> participant) ownership the first time we
    // see this SSRC; that lets us reverse-route RTCP feedback later.
    int? originalSsrc;
    if (rtp.length >= 12) {
      originalSsrc = ByteData.sublistView(rtp).getUint32(8, Endian.big);
      _ssrcOwner[originalSsrc] = fromId;
    }
    // Is this an RTX retransmission? We know iff the sender's offer
    // declared an FID group naming this SSRC as the RTX half.
    final primarySsrc =
        originalSsrc == null ? null : _rtxToPrimary[fromId]?[originalSsrc];
    final isRtx = primarySsrc != null;

    for (final p in _participants.values) {
      if (p.id == fromId) continue;
      final peer = p.pc.activePeer;
      if (peer == null || !peer.isSecure) {
        stats.rtpDropped++;
        continue;
      }
      Uint8List outbound;
      if (!ssrcRewriting) {
        outbound = rtp;
      } else if (isRtx) {
        outbound = _rewriteRtxRtp(p.id, primarySsrc, originalSsrc!, rtp);
      } else {
        outbound = _rewriteRtp(p.id, rtp);
      }
      final ok = await p.transport.sendRtp(peer, outbound);
      if (ok) {
        stats.rtpForwarded++;
        if (isRtx) stats.rtxForwarded++;
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

  /// Like [_rewriteRtp] but for RTX retransmissions: the rewritten RTX
  /// SSRC is allocated *after* the primary's rewritten SSRC, so the
  /// per-receiver FID pair `(rewrittenPrimary, rewrittenRtx)` is stable.
  Uint8List _rewriteRtxRtp(
      String receiverId, int originalPrimary, int originalRtx, Uint8List rtp) {
    if (rtp.length < 12) return rtp;
    final rewrittenRtx =
        _ssrcAllocator.rewriteRtx(receiverId, originalPrimary, originalRtx);
    if (rewrittenRtx == originalRtx) return rtp;
    final out = Uint8List.fromList(rtp);
    ByteData.sublistView(out).setUint32(8, rewrittenRtx, Endian.big);
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
