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

/// Sliding-window byte → bps meter. Stores `(timestamp, bytes)` samples
/// inside the configured [window] and reports the current bitrate as
/// `(sum-of-bytes-in-window * 8) / window-seconds`.
///
/// Cheap to update (one append + one prefix-trim per record) and
/// deterministic in tests via the optional `now` parameter.
class RateMeter {
  /// Sliding window length. Larger = smoother, smaller = more reactive.
  final Duration window;

  // Parallel arrays to avoid allocating a sample object per packet.
  final List<DateTime> _times = [];
  final List<int> _bytes = [];
  int _sum = 0;

  RateMeter({this.window = const Duration(seconds: 2)});

  /// Append a measurement of [bytesObserved] at [now] (defaults to
  /// `DateTime.now()`), then drop samples older than [window].
  void record(int bytesObserved, [DateTime? now]) {
    final t = now ?? DateTime.now();
    _times.add(t);
    _bytes.add(bytesObserved);
    _sum += bytesObserved;
    _trim(t);
  }

  /// Bits-per-second over the trailing [window] ending at [now].
  /// Returns 0 when no samples remain after trimming.
  double bitsPerSecond([DateTime? now]) {
    final t = now ?? DateTime.now();
    _trim(t);
    if (_times.isEmpty) return 0;
    return (_sum * 8.0) / window.inMilliseconds * 1000.0;
  }

  void _trim(DateTime now) {
    final cutoff = now.subtract(window);
    var i = 0;
    while (i < _times.length && _times[i].isBefore(cutoff)) {
      _sum -= _bytes[i];
      i++;
    }
    if (i > 0) {
      _times.removeRange(0, i);
      _bytes.removeRange(0, i);
    }
  }
}

/// Per-participant traffic counters. Updated by the SFU on every
/// forwarded packet so callers (e.g. `/stats`) can attribute bandwidth
/// to each connection.
class SfuParticipantStats {
  /// RTP packets received from this participant on the inbound side.
  int rtpReceived = 0;

  /// RTCP packets received from this participant on the inbound side.
  int rtcpReceived = 0;

  /// Bytes received from this participant (RTP + RTCP, post-decrypt).
  int bytesReceived = 0;

  /// RTP packets the SFU sent to this participant on the outbound side.
  int rtpSent = 0;

  /// RTCP packets the SFU sent to this participant on the outbound side.
  int rtcpSent = 0;

  /// Bytes the SFU sent to this participant (RTP + RTCP, pre-encrypt).
  int bytesSent = 0;

  /// Wall-clock timestamp of the last RTP or RTCP packet received from
  /// this participant. `null` means we haven't seen any media yet.
  /// Used by [BasicSfu]'s inactivity sweeper.
  DateTime? lastActivityAt;

  /// Rolling-window inbound bitrate (bps) over the last few seconds.
  final RateMeter recvRate = RateMeter();

  /// Rolling-window outbound bitrate (bps) over the last few seconds.
  final RateMeter sendRate = RateMeter();
}

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

  /// Per-participant traffic counters.
  final SfuParticipantStats stats = SfuParticipantStats();

  /// Bytes currently in-flight on this receiver's outbound queue
  /// (i.e. handed to `transport.sendRtp` but whose Future hasn't yet
  /// completed). Tracked so the SFU can shed load on slow consumers
  /// instead of buffering unboundedly. Reset on every Future resolution.
  int inFlightBytes = 0;

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

  /// PLI requests that were dropped by the rate-limiter because another
  /// PLI for the same `(producer, primarySsrc)` was sent recently.
  int pliSuppressed = 0;

  /// Generic NACK (RTPFB FMT=1) packets the SFU generated and sent to a
  /// producer when an inbound RTP sequence gap was detected.
  int nackSent = 0;

  /// Number of *individual missing sequence numbers* the SFU has asked
  /// to be retransmitted (sum of PIDs + BLP bits across all sent NACKs).
  int nackSeqRequested = 0;
}

/// Tracks the last RTP sequence number seen on a stream and reports any
/// gaps so the caller can request retransmission.
///
/// RTP sequence numbers are 16-bit and wrap at 65535 → 0. We accept
/// packets that look "ahead" of the last seen seq within a forward window
/// of half the seq space; everything else (older / wildly out-of-order)
/// is treated as a probe and ignored for gap purposes.
class SeqGapDetector {
  /// Largest gap (in packets) we will report at once. Bigger inbound jumps
  /// are treated as a stream restart and the detector simply re-anchors
  /// without emitting a NACK.
  final int maxGap;

  int? _lastSeq;

  SeqGapDetector({this.maxGap = 16});

  /// Last in-order sequence number observed (null until the first feed).
  int? get lastSeq => _lastSeq;

  /// Feed an inbound RTP sequence number for this stream. Returns the
  /// list of *missing* sequence numbers between the previous and current,
  /// or an empty list if there's no gap (or the packet is a re-order /
  /// duplicate / restart).
  List<int> feed(int seq) {
    seq &= 0xFFFF;
    final last = _lastSeq;
    if (last == null) {
      _lastSeq = seq;
      return const [];
    }
    final diff = (seq - last) & 0xFFFF;
    if (diff == 0) {
      // Duplicate of the last packet — ignore.
      return const [];
    }
    if (diff > 0x8000) {
      // Re-ordering / late retransmission — accept silently, don't
      // advance _lastSeq.
      return const [];
    }
    if (diff > maxGap) {
      // Huge jump (likely a restart or extremely large loss). Re-anchor
      // without flooding the producer with NACKs.
      _lastSeq = seq;
      return const [];
    }
    _lastSeq = seq;
    if (diff == 1) return const [];
    final missing = <int>[];
    for (var i = 1; i < diff; i++) {
      missing.add((last + i) & 0xFFFF);
    }
    return missing;
  }
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

  /// Address advertised in host ICE candidates. When [address] is a
  /// wildcard (e.g. `0.0.0.0`), the bound address is not routable; set
  /// this to the host's reachable IP (LAN, public, or `127.0.0.1` for
  /// local-only testing) so browsers can connect.
  final InternetAddress? announceAddress;

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

  /// `(producerId, primarySsrc) -> last PLI emit time`. Used to debounce
  /// keyframe requests so a burst of joins doesn't produce a PLI storm.
  final Map<String, Map<int, DateTime>> _lastPliAt = {};

  /// `(producerId, primarySsrc) -> SeqGapDetector`. Lazily created the
  /// first time we see a primary RTP packet from a producer. Used by the
  /// server-NACK path to spot dropped packets and ask the producer for a
  /// retransmission via RFC 4585 generic NACK (RTPFB FMT=1).
  final Map<String, Map<int, SeqGapDetector>> _gapDetectors = {};

  /// Minimum spacing between PLIs for the same `(producer, primarySsrc)`.
  /// Defaults to 500ms which is well below typical encoder keyframe
  /// intervals but still bounds inbound PLI rate to <= 2 Hz per stream.
  final Duration pliMinInterval;

  /// If non-null, a participant that has been [RTCPeerConnectionState.connected]
  /// but has not delivered any RTP or RTCP for this long is reported via
  /// [onParticipantTimedOut]. The participant is *not* automatically
  /// removed — the signaling layer decides what to do (close the
  /// websocket, log, etc.).
  final Duration? inactivityTimeout;

  /// How often the inactivity sweeper wakes up. Ignored when
  /// [inactivityTimeout] is null.
  final Duration inactivityCheckInterval;

  /// When true, the SFU watches inbound RTP sequence numbers per
  /// `(producer, primarySsrc)` and fires generic NACKs back to the
  /// producer for any missing packets. Defaults to false so the legacy
  /// behaviour (forward only) is preserved.
  final bool nackEnabled;

  /// Largest in-window gap the gap-detector will request retransmission
  /// for. Bigger jumps are treated as stream restarts.
  final int nackMaxGap;

  /// Maximum number of audio producers whose RTP is forwarded to each
  /// receiver. Selection uses the RFC 6464 `audio-level` RTP header
  /// extension: the K loudest active speakers are forwarded, the rest
  /// are silently dropped on egress. Set to a value >= number of
  /// participants to disable selective forwarding.
  final int maxAudioForwarded;

  /// Maximum number of video producers whose RTP is forwarded to each
  /// receiver. Negative (default) preserves the legacy "forward every
  /// publisher's video to every receiver" behaviour. When set to a
  /// non-negative value the SFU keeps only the K loudest active
  /// speakers' video and drops the rest on egress, mirroring the
  /// audio-level-based active-speaker policy.
  final int maxVideoForwarded;

  /// Audio packets older than this are treated as silence when ranking
  /// active speakers. Prevents a producer that briefly spoke from
  /// monopolising a top-K slot forever.
  final Duration audioActivityWindow;

  /// How often the active-speaker recomputation timer wakes up. The
  /// hot RTP path consults a precomputed `Set<int>` instead of sorting
  /// the audio-level map per packet.
  final Duration activeSpeakerRefreshInterval;

  /// Debounce window for join-time keyframe coalescing. Multiple
  /// participants connecting within this window only cost one PLI per
  /// existing producer, regardless of how many newcomers there are.
  final Duration keyframeCoalesceInterval;

  /// Hard cap on simultaneously-joined participants. [addParticipant]
  /// throws [StateError] when the cap is hit. Defaults to 0 (unbounded).
  /// Production deployments should set this to whatever the host can
  /// realistically sustain (see SCALING.md for capacity rules of thumb)
  /// so a single misbehaving signaler can't OOM the room.
  final int maxParticipants;

  /// Per-receiver outbound queue cap (bytes). When a receiver already
  /// has more than this many bytes in flight, additional RTP packets
  /// are dropped on egress instead of queued. 0 (default) disables the
  /// limiter; pick a value that's a few RTTs of the receiver's link
  /// budget (e.g. 256 * 1024 for ~2 Mbps clients on a 1s window).
  final int maxInFlightBytesPerReceiver;

  Timer? _inactivityTimer;
  Timer? _activeSpeakerTimer;
  Timer? _pendingKeyframeTimer;

  /// Producers that should currently have their audio forwarded.
  /// Recomputed periodically by [_recomputeActiveSpeakers]; consulted on
  /// the hot RTP path via [_isAudioActive]. Empty means "forward every
  /// audio producer" (i.e. selective forwarding disabled).
  Set<int> _activeAudioSet = const <int>{};

  /// Producers that should currently have their video forwarded. Same
  /// semantics as [_activeAudioSet] but for the video kind. Empty means
  /// "forward every video producer".
  Set<int> _activeVideoSet = const <int>{};

  /// Newly-connected participants that have not yet been credited with a
  /// keyframe-request burst. Drained by the coalesced PLI timer.
  final Set<String> _pendingKeyframeRequesters = <String>{};

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

  /// Fired when a participant has been connected but has not delivered
  /// any RTP/RTCP for at least [inactivityTimeout]. Only ever fires when
  /// [inactivityTimeout] is non-null. The SFU does not remove the
  /// participant — the caller decides.
  void Function(SfuParticipant participant, Duration idleFor)?
      onParticipantTimedOut;

  /// Fired for every inbound *primary* (non-RTX) video RTP packet, after
  /// the SFU has identified its producer. Hook this to drive auxiliary
  /// pipelines like the snapshot recorder. The packet bytes are the
  /// already-decrypted RTP wire format (header + payload). Throwing or
  /// blocking inside the hook directly stalls forwarding — keep it
  /// fast and `unawaited(...)` any async work.
  void Function(String producerId, int primarySsrc, Uint8List rtp)? onVideoRtp;

  int _nextPortOffset = 0;

  BasicSfu({
    required this.address,
    required this.basePort,
    this.announceAddress,
    this.video = true,
    this.audio = true,
    this.ssrcRewriting = true,
    this.pliMinInterval = const Duration(milliseconds: 500),
    this.inactivityTimeout,
    this.inactivityCheckInterval = const Duration(seconds: 5),
    this.nackEnabled = false,
    this.nackMaxGap = 16,
    this.maxAudioForwarded = 3,
    this.maxVideoForwarded = -1,
    this.audioActivityWindow = const Duration(seconds: 1),
    Duration? activeSpeakerRefreshInterval,
    this.keyframeCoalesceInterval = const Duration(milliseconds: 50),
    this.maxParticipants = 0,
    this.maxInFlightBytesPerReceiver = 0,
  }) : activeSpeakerRefreshInterval = activeSpeakerRefreshInterval ??
            Duration(
                microseconds: (audioActivityWindow.inMicroseconds ~/ 4)
                    .clamp(50000, 1000000)) {
    if (inactivityTimeout != null) {
      _inactivityTimer =
          Timer.periodic(inactivityCheckInterval, (_) => runInactivitySweep());
    }
    _activeSpeakerTimer = Timer.periodic(
        this.activeSpeakerRefreshInterval, (_) => _recomputeActiveSpeakers());
  }

  /// `participantId -> RFC 5285 extmap id of the audio-level extension`,
  /// learned from the producer's offer SDP. Absent if the producer did
  /// not negotiate the extension (in which case its audio is treated as
  /// always-active level 0).
  final Map<String, int> _audioLevelExtId = {};

  /// `primarySsrc -> latest (level, timestampMicros)` audio-level sample.
  /// Lower level = louder; 127 is silence per RFC 6464.
  final Map<int, (int level, int atMicros)> _audioLevelByPrimarySsrc = {};

  /// Notify-only sweep: fires [onParticipantTimedOut] for every connected
  /// participant whose last inbound RTP/RTCP timestamp is older than
  /// [inactivityTimeout]. Refires every [inactivityCheckInterval] until
  /// the participant is removed by the caller.
  ///
  /// Set [requireConnected] to false to also sweep participants that
  /// haven't yet completed DTLS (used by tests that don't run a real
  /// handshake).
  void runInactivitySweep({bool requireConnected = true}) {
    final timeout = inactivityTimeout;
    if (timeout == null) return;
    final cb = onParticipantTimedOut;
    if (cb == null) return;
    final now = DateTime.now();
    for (final p in _participants.values.toList()) {
      if (requireConnected &&
          p.pc.connectionState != RTCPeerConnectionState.connected) {
        continue;
      }
      final last = p.stats.lastActivityAt;
      if (last == null) continue;
      final idle = now.difference(last);
      if (idle >= timeout) cb(p, idle);
    }
  }

  /// Snapshot of all current participants.
  List<SfuParticipant> get participants =>
      List.unmodifiable(_participants.values);

  /// Look up a participant by id.
  SfuParticipant? getParticipant(String id) => _participants[id];

  /// Set of producer primary audio SSRCs the SFU is currently forwarding
  /// (the cached top-K active speakers). Empty when there are not yet
  /// enough samples or [maxAudioForwarded] is non-positive (forward
  /// every audio producer).
  Set<int> get activeAudioSet => Set.unmodifiable(_activeAudioSet);

  /// Set of producer primary video SSRCs the SFU is currently
  /// forwarding. Always empty when [maxVideoForwarded] is negative
  /// (forward every video producer).
  Set<int> get activeVideoSet => Set.unmodifiable(_activeVideoSet);

  /// Force an immediate recomputation of the active-speaker sets,
  /// bypassing the periodic refresh timer. Exposed for tests.
  void recomputeActiveSpeakersNow() => _recomputeActiveSpeakers();

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
    if (maxParticipants > 0 && _participants.length >= maxParticipants) {
      throw StateError(
          'BasicSfu participant cap ($maxParticipants) reached; rejecting "$id".');
    }

    final pc = RTCPeerConnection(RTCConfiguration(
      defaultVideoCodecs: [Vp8Codec()],
      defaultAudioCodecs: [PcmuCodec()],
    ));

    if (video) pc.addTransceiver(trackOrKind: MediaKind.video);
    if (audio) pc.addTransceiver(trackOrKind: MediaKind.audio);

    // basePort == 0 is "let the OS pick a free port for every
    // participant". Without this guard, the second participant would
    // try to bind to port 1 (privileged), which fails or is
    // unreachable, leaving DTLS stuck.
    final int usePort;
    if (port != null) {
      usePort = port;
    } else if (basePort == 0) {
      usePort = 0;
    } else {
      usePort = basePort + _nextPortOffset++;
    }
    final transport =
        await pc.bind(address, usePort, announceAddress: announceAddress);

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
        // Schedule a single coalesced PLI burst so a flock of joining
        // peers only costs one keyframe request per existing producer.
        _scheduleCoalescedKeyframeBurst(id);
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
    // Drop every audio-level sample for SSRCs this participant produced
    // before we forget the ownership map, otherwise the activity-window
    // sweep can't tell whose samples to evict.
    final leaverSsrcs = <int>[
      for (final entry in _ssrcOwner.entries)
        if (entry.value == id) entry.key,
    ];
    for (final s in leaverSsrcs) {
      _audioLevelByPrimarySsrc.remove(s);
      _activeAudioSet = _activeAudioSet.where((x) => x != s).toSet();
      _activeVideoSet = _activeVideoSet.where((x) => x != s).toSet();
    }
    _ssrcOwner.removeWhere((_, owner) => owner == id);
    _audioLevelExtId.remove(id);
    _rtxToPrimary.remove(id);
    _producers.remove(id);
    _lastPliAt.remove(id);
    _gapDetectors.remove(id);
    _pendingKeyframeRequesters.remove(id);
    onParticipantLeft?.call(p);
  }

  /// Tear everything down.
  Future<void> close() async {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    _activeSpeakerTimer?.cancel();
    _activeSpeakerTimer = null;
    _pendingKeyframeTimer?.cancel();
    _pendingKeyframeTimer = null;
    _pendingKeyframeRequesters.clear();
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
  /// Rate-limited to one PLI per `(producer, primarySsrc)` every
  /// [pliMinInterval] (default 500ms). Set [force] to bypass the limit.
  ///
  /// Returns the number of PLI packets actually sent (zero if the
  /// producer has no DTLS-secure peer yet, has no video producers, or
  /// every stream was suppressed by the rate-limiter).
  Future<int> requestKeyframe(String producerId, {bool force = false}) async {
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
    final perProducer = _lastPliAt.putIfAbsent(producerId, () => {});
    final now = DateTime.now();
    for (final s in streams) {
      if (s.kind != 'video') continue;
      if (!force) {
        final last = perProducer[s.primarySsrc];
        if (last != null && now.difference(last) < pliMinInterval) {
          stats.pliSuppressed++;
          continue;
        }
      }
      final pli = _buildPli(senderSsrc, s.primarySsrc);
      final ok = await p.transport.sendRtcp(peer, pli);
      if (ok) {
        sent++;
        stats.pliSent++;
        perProducer[s.primarySsrc] = now;
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

  /// Send a generic NACK (RFC 4585 RTPFB FMT=1) to [producerId] for the
  /// given [missing] sequence numbers on the primary stream [mediaSsrc].
  /// No-ops if the producer has no DTLS-secure peer.
  Future<void> _sendNack(
      String producerId, int mediaSsrc, List<int> missing) async {
    if (missing.isEmpty) return;
    final p = _participants[producerId];
    if (p == null) return;
    final peer = p.pc.activePeer;
    if (peer == null || !peer.isSecure) return;
    final pkt = buildNack(1, mediaSsrc, missing);
    final ok = await p.transport.sendRtcp(peer, pkt);
    if (ok) {
      stats.nackSent++;
      stats.nackSeqRequested += missing.length;
      p.stats.rtcpSent++;
      p.stats.bytesSent += pkt.length;
      p.stats.sendRate.record(pkt.length);
    } else {
      stats.rtcpDropped++;
    }
  }

  /// Build one RTCP generic-NACK (RFC 4585) sub-packet:
  ///   V=2, P=0, FMT=1, PT=205, length=2+N, sender-SSRC, media-SSRC,
  ///   then N x (PID:16, BLP:16) FCI words.
  ///
  /// Each FCI word covers a base sequence number `pid` and the next 16
  /// sequence numbers via the bitmap `blp`. Adjacent missing seqs are
  /// folded into one FCI when possible, so a 4-packet burst loss costs
  /// 4 bytes on the wire instead of 16.
  ///
  /// Public for testing; production callers should use [_sendNack].
  static Uint8List buildNack(int senderSsrc, int mediaSsrc, List<int> missing) {
    // Group adjacent missing seqs into (PID, BLP) FCIs.
    final fcis = <int>[]; // packed 32-bit words
    final sorted = [...missing]..sort();
    var i = 0;
    while (i < sorted.length) {
      final pid = sorted[i] & 0xFFFF;
      var blp = 0;
      var j = i + 1;
      while (j < sorted.length) {
        final delta = (sorted[j] - pid) & 0xFFFF;
        if (delta < 1 || delta > 16) break;
        blp |= 1 << (delta - 1);
        j++;
      }
      fcis.add((pid << 16) | (blp & 0xFFFF));
      i = j;
    }

    final length = 12 + fcis.length * 4;
    final out = Uint8List(length);
    final bd = ByteData.sublistView(out);
    out[0] = 0x80 | 1; // V=2, P=0, FMT=1 (generic NACK)
    out[1] = 205; // RTPFB
    // length in 32-bit words, minus 1.
    bd.setUint16(2, (length ~/ 4) - 1, Endian.big);
    bd.setUint32(4, senderSsrc, Endian.big);
    bd.setUint32(8, mediaSsrc, Endian.big);
    for (var k = 0; k < fcis.length; k++) {
      bd.setUint32(12 + k * 4, fcis[k], Endian.big);
    }
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
      // Learn the RFC 6464 audio-level extmap id (per producer; per spec
      // BUNDLE forces the same id across sections, so first one wins).
      if (kind == 'audio' && !_audioLevelExtId.containsKey(participantId)) {
        for (final ext in (m['ext'] as List?)?.cast<Map>() ?? const []) {
          final uri = ext['uri']?.toString();
          if (uri == 'urn:ietf:params:rtp-hdrext:ssrc-audio-level') {
            final v = ext['value'];
            final id = v is int ? v : int.tryParse(v?.toString() ?? '');
            if (id != null) _audioLevelExtId[participantId] = id;
            break;
          }
        }
      }
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

    // Collect other participants' producer streams in deterministic
    // (sorted) order so the same producer always lands on the same m=
    // section across renegotiations.
    final otherIds = _producers.keys.where((id) => id != receiverId).toList()
      ..sort();
    final pendingByKind = <String, List<SfuProducerStream>>{
      'video': [],
      'audio': [],
    };
    for (final id in otherIds) {
      for (final s in _producers[id]!) {
        pendingByKind[s.kind]?.add(s);
      }
    }

    var changed = false;
    for (final m in media) {
      final kind = (m['type'] as String?) ?? '';
      if (kind != 'video' && kind != 'audio') continue;
      // PT=0 means we rejected this section; skip.
      if (m['port'] == 0) continue;

      // Only m= sections that the *server* will send on can carry
      // forwarded SSRCs. In an answer that's `sendrecv` (legacy 2-peer
      // mode where the receiver's own media slot doubles as the
      // forwarding slot) and `sendonly` (mirrored from the browser's
      // `recvonly` recv-only transceivers added per remote peer).
      final dir = (m['direction'] as String?) ?? 'sendrecv';
      if (dir != 'sendrecv' && dir != 'sendonly') continue;

      final pending = pendingByKind[kind]!;
      if (pending.isEmpty) continue;
      final stream = pending.removeAt(0);

      final ssrcs = (m['ssrcs'] as List?) ?? <Map<String, dynamic>>[];
      final groups = (m['ssrcGroups'] as List?) ?? <Map<String, dynamic>>[];

      final rwPrimary = _ssrcAllocator.rewrite(receiverId, stream.primarySsrc);
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

      if (ssrcs.isNotEmpty) m['ssrcs'] = ssrcs;
      if (groups.isNotEmpty) m['ssrcGroups'] = groups;
      // Section-level msid wins over per-ssrc msid in Chrome's
      // grouping logic. Without overriding it, every forwarded SSRC
      // would land on the same MediaStream (the receiver's local
      // streamId emitted by SdpAnswerBuilder) and `pc.ontrack` would
      // only fire once per kind regardless of how many producers we
      // route into separate m= sections.
      m['msid'] = '${stream.msidStream} ${stream.msidTrack}';
    }

    if (!changed) return answerSdp;
    return writeSdp(session);
  }

  // ---- Forwarding ----------------------------------------------------

  Future<void> _forwardRtp(String fromId, Uint8List rtp) async {
    // One clock read per inbound packet: shared between source-stats,
    // audio-level timestamping, and any downstream consumer.
    final now = DateTime.now();
    final nowMicros = now.microsecondsSinceEpoch;
    // Per-source receive counters (count even unmappable packets so the
    // operator sees inbound activity).
    final source = _participants[fromId];
    if (source != null) {
      source.stats.rtpReceived++;
      source.stats.bytesReceived += rtp.length;
      source.stats.lastActivityAt = now;
      source.stats.recvRate.record(rtp.length, now);
    }
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

    // Determine the kind (audio/video) of this packet from the producer's
    // declared streams. Used both for the active-speaker logic and as a
    // cheap filter so we never apply audio policy to video packets.
    final effectiveSsrc = isRtx ? primarySsrc : originalSsrc;
    String? kind;
    if (effectiveSsrc != null) {
      for (final s in _producers[fromId] ?? const <SfuProducerStream>[]) {
        if (s.primarySsrc == effectiveSsrc) {
          kind = s.kind;
          break;
        }
      }
    }

    // RFC 6464 audio-level extension parsing. Drop a sample for the
    // primary SSRC so the active-speaker ranker can pick the loudest K.
    if (kind == 'audio' && !isRtx && originalSsrc != null) {
      final extId = _audioLevelExtId[fromId];
      if (extId != null) {
        final level = _readAudioLevelExtension(rtp, extId);
        if (level != null) {
          _audioLevelByPrimarySsrc[originalSsrc] = (level, nowMicros);
        }
      } else {
        // Producer didn't negotiate the extension — treat as always-on
        // so its audio is still eligible for forwarding.
        _audioLevelByPrimarySsrc[originalSsrc] = (0, nowMicros);
      }
    }

    // If audio is being selectively forwarded and this producer isn't
    // among the current top-K active speakers, drop on egress (still
    // counted as received for stats).
    final shouldDropAudio = kind == 'audio' &&
        !isRtx &&
        originalSsrc != null &&
        !_isAudioActive(originalSsrc);

    // Same idea for video when [maxVideoForwarded] is non-negative:
    // forward video only for producers in the active set. RTX packets
    // for an inactive primary are likewise dropped — they would arrive
    // on a stream the receiver isn't getting in the first place.
    final videoSsrcForPolicy = isRtx ? primarySsrc : originalSsrc;
    final shouldDropVideo = kind == 'video' &&
        videoSsrcForPolicy != null &&
        !_isVideoActive(videoSsrcForPolicy);

    // Server-originated NACK: only run on primary RTP (skip RTX so the
    // retransmission itself doesn't trip the detector). Sequence number
    // is bytes [2..4] big-endian.
    if (nackEnabled && !isRtx && originalSsrc != null && rtp.length >= 12) {
      final seq = ByteData.sublistView(rtp).getUint16(2, Endian.big);
      final detector = _gapDetectors
          .putIfAbsent(fromId, () => {})
          .putIfAbsent(originalSsrc, () => SeqGapDetector(maxGap: nackMaxGap));
      final missing = detector.feed(seq);
      if (missing.isNotEmpty) {
        unawaited(_sendNack(fromId, originalSsrc, missing));
      }
    }

    if (shouldDropAudio || shouldDropVideo) {
      stats.rtpDropped++;
      return;
    }

    // Notify any video observer (e.g. the snapshot recorder) before we
    // start the SSRC-rewriting fan-out so they see the original packet.
    if (kind == 'video' && !isRtx && originalSsrc != null) {
      try {
        onVideoRtp?.call(fromId, originalSsrc, rtp);
      } catch (_) {}
    }

    // Snapshot the receiver list once so concurrent join/leave can't
    // perturb the iteration, then issue all sends in parallel. SRTP
    // encrypt is async; awaiting serially would serialise N receivers'
    // CPU + UDP work behind each other.
    final receivers = _receiversSnapshotExcluding(fromId);
    if (receivers.isEmpty) return;
    final futures = <Future<void>>[];
    for (final p in receivers) {
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
      futures.add(_sendRtpAndAccount(p, peer, outbound, isRtx: isRtx));
    }
    if (futures.isNotEmpty) await Future.wait(futures);
  }

  Future<void> _sendRtpAndAccount(
    SfuParticipant p,
    RtcPeerTransport peer,
    Uint8List outbound, {
    required bool isRtx,
  }) async {
    // Egress backpressure: a stalled receiver must not pile up unbounded
    // pending Futures. Drop newest packets when the in-flight byte
    // counter exceeds the configured cap. Receiver-side NACK / PLI will
    // recover anything important.
    if (maxInFlightBytesPerReceiver > 0 &&
        p.inFlightBytes > maxInFlightBytesPerReceiver) {
      stats.rtpDropped++;
      return;
    }
    final size = outbound.length;
    p.inFlightBytes += size;
    try {
      final ok = await p.transport.sendRtp(peer, outbound);
      if (ok) {
        stats.rtpForwarded++;
        if (isRtx) stats.rtxForwarded++;
        p.stats.rtpSent++;
        p.stats.bytesSent += size;
        p.stats.sendRate.record(size);
      } else {
        stats.rtpDropped++;
      }
    } finally {
      p.inFlightBytes -= size;
    }
  }

  /// Returns a freshly-allocated list of every participant except
  /// [excludeId]. Used by the fan-out paths so the iteration is stable
  /// across concurrent joins/leaves and so the awaited send futures
  /// don't observe a partially-mutated map.
  List<SfuParticipant> _receiversSnapshotExcluding(String excludeId) {
    final out = <SfuParticipant>[];
    for (final p in _participants.values) {
      if (p.id == excludeId) continue;
      out.add(p);
    }
    return out;
  }

  Future<void> _forwardRtcp(String fromId, Uint8List rtcp) async {
    final now = DateTime.now();
    final source = _participants[fromId];
    if (source != null) {
      source.stats.rtcpReceived++;
      source.stats.bytesReceived += rtcp.length;
      source.stats.lastActivityAt = now;
      source.stats.recvRate.record(rtcp.length, now);
    }
    if (!ssrcRewriting) {
      // No rewriting at all — broadcast verbatim, in parallel.
      final receivers = _receiversSnapshotExcluding(fromId);
      final futures = <Future<void>>[];
      for (final p in receivers) {
        final peer = p.pc.activePeer;
        if (peer == null || !peer.isSecure) {
          stats.rtcpDropped++;
          continue;
        }
        futures.add(_sendRtcpAndAccount(p, peer, rtcp));
      }
      if (futures.isNotEmpty) await Future.wait(futures);
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
    final allFutures = <Future<void>>[];
    if (broadcastParts.isNotEmpty) {
      final compound = _concat(broadcastParts);
      final receivers = _receiversSnapshotExcluding(fromId);
      for (final p in receivers) {
        final peer = p.pc.activePeer;
        if (peer == null || !peer.isSecure) {
          stats.rtcpDropped++;
          continue;
        }
        final outbound = _rewriteRtcp(p.id, compound);
        allFutures.add(_sendRtcpAndAccount(p, peer, outbound));
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
      final payload = entry.value.toBytes();
      allFutures.add(_sendRtcpAndAccount(p, peer, payload));
    }
    if (allFutures.isNotEmpty) await Future.wait(allFutures);
  }

  Future<void> _sendRtcpAndAccount(
      SfuParticipant p, RtcPeerTransport peer, Uint8List payload) async {
    final ok = await p.transport.sendRtcp(peer, payload);
    if (ok) {
      stats.rtcpForwarded++;
      p.stats.rtcpSent++;
      p.stats.bytesSent += payload.length;
      p.stats.sendRate.record(payload.length);
    } else {
      stats.rtcpDropped++;
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

  // ---- Active speaker selection -------------------------------------

  /// True if [primarySsrc] should currently have its audio forwarded.
  /// Backed by the cached active-speaker set, populated by
  /// [_recomputeActiveSpeakers].
  bool _isAudioActive(int primarySsrc) {
    if (maxAudioForwarded <= 0) return true;
    final set = _activeAudioSet;
    if (set.isEmpty) return true; // Not enough samples yet -> forward.
    return set.contains(primarySsrc);
  }

  /// True if [primarySsrc] should currently have its video forwarded.
  /// Negative [maxVideoForwarded] disables the policy entirely.
  bool _isVideoActive(int primarySsrc) {
    if (maxVideoForwarded < 0) return true;
    if (maxVideoForwarded == 0) return false;
    final set = _activeVideoSet;
    if (set.isEmpty) return true;
    return set.contains(primarySsrc);
  }

  /// Recompute [_activeAudioSet] and [_activeVideoSet] from the latest
  /// audio-level samples. Runs on a timer so the hot RTP path doesn't
  /// pay sort cost per packet. Also drives selective video forwarding:
  /// the K loudest *audio* producers are also the K whose *video* is
  /// forwarded, so the visible feed always tracks the audible feed.
  ///
  /// When the active-video set changes, every producer that newly
  /// entered the set is asked for an immediate keyframe so receivers
  /// don't have to wait for the next natural keyframe interval.
  void _recomputeActiveSpeakers() {
    final cutoffMicros = DateTime.now().microsecondsSinceEpoch -
        audioActivityWindow.inMicroseconds;
    // Gather active samples: (ssrc, level). Lower level = louder.
    final active = <List<int>>[];
    _audioLevelByPrimarySsrc.forEach((ssrc, sample) {
      final atMicros = sample.$2;
      if (atMicros < cutoffMicros) return;
      active.add([ssrc, sample.$1]);
    });
    active.sort((a, b) => a[1].compareTo(b[1]));

    Set<int> nextAudio;
    if (maxAudioForwarded <= 0 || active.length <= maxAudioForwarded) {
      nextAudio = {for (final s in active) s[0]};
    } else {
      nextAudio = <int>{
        for (var i = 0; i < maxAudioForwarded; i++) active[i][0],
      };
    }

    Set<int> nextVideo;
    if (maxVideoForwarded < 0) {
      nextVideo = const <int>{};
    } else if (maxVideoForwarded == 0) {
      nextVideo = const <int>{};
    } else {
      // Map the audio-active producers (by primary audio SSRC) back to
      // their participant ids, then forward the *video* SSRCs of the
      // same participants.
      final activeIds = <String>{};
      final limit =
          maxVideoForwarded < active.length ? maxVideoForwarded : active.length;
      for (var i = 0; i < limit; i++) {
        final ownerId = _ssrcOwner[active[i][0]];
        if (ownerId != null) activeIds.add(ownerId);
      }
      nextVideo = <int>{};
      for (final id in activeIds) {
        for (final s in _producers[id] ?? const <SfuProducerStream>[]) {
          if (s.kind == 'video') nextVideo.add(s.primarySsrc);
        }
      }
    }

    final added = nextVideo.difference(_activeVideoSet);
    _activeAudioSet = nextAudio;
    _activeVideoSet = nextVideo;

    // Newly-active video producers: request a keyframe so receivers
    // start decoding immediately on switch.
    if (added.isNotEmpty) {
      final byOwner = <String>{};
      for (final ssrc in added) {
        final owner = _ssrcOwner[ssrc];
        if (owner != null) byOwner.add(owner);
      }
      for (final id in byOwner) {
        // ignore: discarded_futures
        requestKeyframe(id);
      }
    }
  }

  /// Schedule a coalesced PLI burst: when [newcomerId] joins, ensure
  /// every existing producer is asked for *one* keyframe within the
  /// next [keyframeCoalesceInterval]. Subsequent newcomers within the
  /// same window piggy-back on the same burst.
  void _scheduleCoalescedKeyframeBurst(String newcomerId) {
    _pendingKeyframeRequesters.add(newcomerId);
    _pendingKeyframeTimer ??=
        Timer(keyframeCoalesceInterval, _flushCoalescedKeyframes);
  }

  void _flushCoalescedKeyframes() {
    _pendingKeyframeTimer = null;
    if (_pendingKeyframeRequesters.isEmpty) return;
    // Snapshot then clear so producers added during the await don't get
    // skipped on the next burst.
    final newcomers = Set<String>.from(_pendingKeyframeRequesters);
    _pendingKeyframeRequesters.clear();
    for (final producerId in _producers.keys) {
      if (newcomers.contains(producerId)) continue;
      // ignore: discarded_futures
      requestKeyframe(producerId);
    }
  }

  /// Parse RFC 5285 RTP header extensions and return the RFC 6464
  /// audio-level value (0..127) for [extId], or null if the packet has no
  /// extension block, the extension id isn't present, or the format is
  /// malformed. Supports both the one-byte (profile=0xBEDE) and two-byte
  /// (profile top 12 bits = 0x100) header forms.
  static int? _readAudioLevelExtension(Uint8List rtp, int extId) {
    if (rtp.length < 12) return null;
    final hasExt = (rtp[0] & 0x10) != 0;
    if (!hasExt) return null;
    final cc = rtp[0] & 0x0F;
    var off = 12 + cc * 4;
    if (off + 4 > rtp.length) return null;
    final bd = ByteData.sublistView(rtp);
    final profile = bd.getUint16(off, Endian.big);
    final lengthWords = bd.getUint16(off + 2, Endian.big);
    off += 4;
    final extEnd = off + lengthWords * 4;
    if (extEnd > rtp.length) return null;
    if (profile == 0xBEDE) {
      while (off < extEnd) {
        final b = rtp[off++];
        if (b == 0) continue; // padding
        final id = (b >> 4) & 0x0F;
        final len = (b & 0x0F) + 1;
        if (id == 15) break; // reserved terminator
        if (off + len > extEnd) return null;
        if (id == extId && len >= 1) {
          return rtp[off] & 0x7F;
        }
        off += len;
      }
    } else if ((profile & 0xFFF0) == 0x1000) {
      while (off + 1 < extEnd) {
        final id = rtp[off++];
        final len = rtp[off++];
        if (id == 0) continue; // padding
        if (off + len > extEnd) return null;
        if (id == extId && len >= 1) {
          return rtp[off] & 0x7F;
        }
        off += len;
      }
    }
    return null;
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
