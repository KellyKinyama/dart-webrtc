// Builders that produce WebRTC offer / answer session maps in the
// `sdp_transform` shape. Use `writeSdp(map)` to serialize.

import 'sdp_codec.dart';
import 'sdp_session.dart';

/// One ICE candidate in `a=candidate:...`.
class IceCandidate {
  final String foundation;
  final int component; // 1 = RTP, 2 = RTCP (unused with rtcp-mux)
  final String transport; // 'udp' / 'tcp'
  final int priority;
  final String address;
  final int port;
  final String type; // 'host' / 'srflx' / 'relay'

  const IceCandidate({
    required this.foundation,
    this.component = 1,
    this.transport = 'udp',
    this.priority = 2113937151,
    required this.address,
    required this.port,
    this.type = 'host',
  });

  Map<String, dynamic> toMap() => {
        'foundation': foundation,
        'component': component,
        'transport': transport,
        'priority': priority,
        'ip': address,
        'port': port,
        'type': type,
      };
}

/// DTLS setup attribute (`a=setup:`).
enum DtlsSetup { actpass, active, passive }

extension on DtlsSetup {
  String get attr => name;
}

/// Identity material the server contributes to every media section.
class IceDtlsParams {
  final String iceUfrag;
  final String icePwd;

  /// Hex fingerprint with `:` separators.
  final String fingerprintHash;
  final String fingerprintAlg; // e.g. 'sha-256'

  const IceDtlsParams({
    required this.iceUfrag,
    required this.icePwd,
    required this.fingerprintHash,
    this.fingerprintAlg = 'sha-256',
  });
}

/// Builds a complete WebRTC offer.
class SdpOfferBuilder {
  final IceDtlsParams identity;
  final List<IceCandidate> candidates;
  final String streamId;
  final String sessionId;

  final List<Map<String, dynamic>> _media = [];

  SdpOfferBuilder({
    required this.identity,
    this.candidates = const [],
    String? streamId,
    String? sessionId,
  })  : streamId = streamId ?? _newId(),
        sessionId = sessionId ?? _newSessionId();

  /// Add a video section.
  void addVideo({
    required String mid,
    required List<SdpCodec> codecs,
    SdpDirection direction = SdpDirection.sendrecv,
    DtlsSetup setup = DtlsSetup.actpass,
    String? trackId,
  }) {
    if (codecs.isEmpty) {
      throw ArgumentError('addVideo requires at least one codec');
    }
    final m = _newMedia('video', mid, direction, setup, trackId);
    for (final c in codecs) {
      c.applyTo(m);
    }
    _media.add(m);
  }

  /// Add an audio section.
  void addAudio({
    required String mid,
    required List<SdpCodec> codecs,
    SdpDirection direction = SdpDirection.sendrecv,
    DtlsSetup setup = DtlsSetup.actpass,
    String? trackId,
  }) {
    if (codecs.isEmpty) {
      throw ArgumentError('addAudio requires at least one codec');
    }
    final m = _newMedia('audio', mid, direction, setup, trackId);
    for (final c in codecs) {
      c.applyTo(m);
    }
    _media.add(m);
  }

  Map<String, dynamic> _newMedia(String type, String mid, SdpDirection dir,
      DtlsSetup setup, String? trackId) {
    final tid = trackId ?? _newId();
    return <String, dynamic>{
      'type': type,
      'port': 9,
      'protocol': 'UDP/TLS/RTP/SAVPF',
      'payloads': '',
      'connection': {'version': 4, 'ip': '0.0.0.0'},
      'rtcp': {'port': 9, 'netType': 'IN', 'ipVer': 4, 'address': '0.0.0.0'},
      'iceUfrag': identity.iceUfrag,
      'icePwd': identity.icePwd,
      'iceOptions': 'trickle',
      'fingerprint': {
        'type': identity.fingerprintAlg,
        'hash': identity.fingerprintHash,
      },
      'setup': setup.attr,
      'mid': mid,
      'direction': dir.attr,
      'rtcpMux': 'rtcp-mux',
      'rtcpRsize': 'rtcp-rsize',
      'msid': '$streamId $tid',
      'candidates': candidates.map((c) => c.toMap()).toList(),
    };
  }

  /// Produce the final session map.
  Map<String, dynamic> build() {
    final mids = _media
        .map((m) => m['mid']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();

    return <String, dynamic>{
      'version': 0,
      'origin': {
        'username': '-',
        'sessionId': sessionId,
        'sessionVersion': 2,
        'netType': 'IN',
        'ipVer': 4,
        'address': '127.0.0.1',
      },
      'name': '-',
      'timing': {'start': 0, 'stop': 0},
      if (mids.isNotEmpty)
        'groups': [
          {'type': 'BUNDLE', 'mids': mids.join(' ')},
        ],
      // Marker consumed by `writeSdp` (sdp_transform 0.3.2 has no formatter
      // for `a=extmap-allow-mixed`).
      'extmapAllowMixed': true,
      'msidSemantic': {'semantic': 'WMS', 'token': streamId},
      'media': _media,
    };
  }

  /// Convenience: build and serialize in one call.
  String toSdp() => writeSdp(build());
}

/// Builds an answer SDP that mirrors a remote offer.
///
/// For each section in the offer this picks **one** payload type whose
/// rtpmap matches the first compatible entry in [supportedCodecs]. Sections
/// with no compatible codec are echoed back with `port=0`, signalling
/// rejection per RFC 3264.
class SdpAnswerBuilder {
  final Map<String, dynamic> offer;
  final IceDtlsParams identity;
  final List<IceCandidate> candidates;

  /// Codecs this endpoint accepts. Order is preference.
  final List<SdpCodec> supportedCodecs;

  final String streamId;
  final String sessionId;

  SdpAnswerBuilder({
    required this.offer,
    required this.identity,
    required this.supportedCodecs,
    this.candidates = const [],
    String? streamId,
    String? sessionId,
  })  : streamId = streamId ?? _newId(),
        sessionId = sessionId ?? _newSessionId();

  Map<String, dynamic> build() {
    final answeredMids = <String>[];
    final answerMedia = <Map<String, dynamic>>[];

    for (final om in offer.mediaList) {
      final picked = _pickCodec(om);
      if (picked == null) {
        answerMedia.add(<String, dynamic>{
          'type': om['type'],
          'port': 0,
          'protocol': om['protocol'] ?? 'UDP/TLS/RTP/SAVPF',
          'payloads': om['payloads']?.toString().split(' ').first ?? '0',
          if (om['mid'] != null) 'mid': om['mid'],
        });
        continue;
      }
      final mid = om['mid']?.toString() ?? '0';
      answeredMids.add(mid);
      final am = <String, dynamic>{
        'type': om['type'],
        'port': 9,
        'protocol': om['protocol'] ?? 'UDP/TLS/RTP/SAVPF',
        'payloads': '',
        'connection': {'version': 4, 'ip': '0.0.0.0'},
        'rtcp': {'port': 9, 'netType': 'IN', 'ipVer': 4, 'address': '0.0.0.0'},
        'iceUfrag': identity.iceUfrag,
        'icePwd': identity.icePwd,
        'iceOptions': 'trickle',
        'fingerprint': {
          'type': identity.fingerprintAlg,
          'hash': identity.fingerprintHash,
        },
        'setup': _answerSetupFor(om).attr,
        'mid': mid,
        'direction': _mirrorDirection(om).attr,
        'rtcpMux': 'rtcp-mux',
        'rtcpRsize': 'rtcp-rsize',
        'msid': '$streamId ${_newId()}',
        'candidates': candidates.map((c) => c.toMap()).toList(),
      };
      picked.applyTo(am);
      answerMedia.add(am);
    }

    return <String, dynamic>{
      'version': 0,
      'origin': {
        'username': '-',
        'sessionId': sessionId,
        'sessionVersion': 2,
        'netType': 'IN',
        'ipVer': 4,
        'address': '127.0.0.1',
      },
      'name': '-',
      'timing': {'start': 0, 'stop': 0},
      if (answeredMids.isNotEmpty)
        'groups': [
          {'type': 'BUNDLE', 'mids': answeredMids.join(' ')},
        ],
      'extmapAllowMixed': true,
      'msidSemantic': {'semantic': 'WMS', 'token': streamId},
      'media': answerMedia,
    };
  }

  /// Convenience: build and serialize in one call.
  String toSdp() => writeSdp(build());

  SdpCodec? _pickCodec(Map<String, dynamic> om) {
    for (final cand in supportedCodecs) {
      for (final pt in om.payloadTypeList) {
        final r = om.rtpmapFor(pt);
        if (r == null) continue;
        final codec = (r['codec'] as String? ?? '').toUpperCase();
        final rate = r['rate'] is int
            ? r['rate'] as int
            : int.tryParse('${r['rate']}') ?? 0;
        if (codec == cand.name.toUpperCase() && rate == cand.clockRate) {
          // Reuse the offer's PT so PT mappings stay aligned.
          return _withPayloadType(cand, pt);
        }
      }
    }
    return null;
  }

  SdpCodec _withPayloadType(SdpCodec cand, int pt) {
    if (cand is Vp8Codec) return Vp8Codec(payloadType: pt);
    if (cand is Vp9Codec) {
      return Vp9Codec(payloadType: pt, profileId: cand.profileId);
    }
    if (cand is PcmaCodec) return PcmaCodec(payloadType: pt);
    if (cand is PcmuCodec) return PcmuCodec(payloadType: pt);
    if (cand is TelephoneEventCodec) {
      return TelephoneEventCodec(payloadType: pt, clockRate: cand.clockRate);
    }
    return cand;
  }

  DtlsSetup _answerSetupFor(Map<String, dynamic> om) {
    final s = om['setup'];
    if (s == 'actpass' || s == 'passive' || s == null) return DtlsSetup.active;
    if (s == 'active') return DtlsSetup.passive;
    return DtlsSetup.active;
  }

  SdpDirection _mirrorDirection(Map<String, dynamic> om) {
    final d = om['direction'];
    if (d == 'sendonly') return SdpDirection.recvonly;
    if (d == 'recvonly') return SdpDirection.sendonly;
    if (d == 'inactive') return SdpDirection.inactive;
    return SdpDirection.sendrecv;
  }
}

String _newId() {
  final sb = StringBuffer();
  for (var i = 0; i < 16; i++) {
    sb.write(_rand.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

String _newSessionId() {
  final n = _rand.nextInt(0x7fffffff);
  return '${DateTime.now().microsecondsSinceEpoch}$n';
}

final _rand = _SeededRandom();

/// Tiny xorshift PRNG to avoid `Random.secure()` (which can throw on some
/// embedded VMs without a CSPRNG).
class _SeededRandom {
  int _state = DateTime.now().microsecondsSinceEpoch ^ 0xdeadbeef;
  int nextInt(int max) {
    _state ^= _state << 13;
    _state ^= _state >> 7;
    _state ^= _state << 17;
    _state &= 0x7fffffffffffffff;
    return _state % max;
  }
}
