// High-level builder for WebRTC offer / answer SDPs.
//
// `SdpOfferBuilder` produces a session with one media section per
// `addVideo(...)` / `addAudio(...)` call, automatically wiring up the
// session-level `a=group:BUNDLE` line and the per-section ICE / DTLS /
// rtcp-mux / mid attributes that browsers require.
//
// `SdpAnswerBuilder.fromOffer(offer)` mirrors an incoming offer: it picks
// the first compatible codec for each media section, copies the BUNDLE
// group, and sets the right `a=setup:` value (offer `actpass` -> answer
// `active`).

import 'sdp_codec.dart';
import 'sdp_session.dart';

/// One ICE candidate to advertise in `a=candidate:...`.
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

  String toAttrValue() => '$foundation $component $transport $priority '
      '$address $port typ $type';
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

  /// Hex fingerprint, lower or upper case, with `:` separators.
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

  /// Stream id used in `a=msid:<stream> <track>` and `a=msid-semantic:`.
  final String streamId;
  final String sessionId;

  final List<SdpMedia> _media = [];

  SdpOfferBuilder({
    required this.identity,
    this.candidates = const [],
    String? streamId,
    String? sessionId,
  })  : streamId = streamId ?? _newId(),
        sessionId = sessionId ?? _newSessionId();

  /// Add a video section with the given codecs (offer order is preference).
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

  SdpMedia _newMedia(String type, String mid, SdpDirection dir, DtlsSetup setup,
      String? trackId) {
    final m = SdpMedia(type: type)
      ..connection =
          SdpConnection(netType: 'IN', addrType: 'IP4', address: '0.0.0.0');
    m.attributes.add(SdpAttribute('rtcp', '9 IN IP4 0.0.0.0'));
    for (final c in candidates) {
      m.attributes.add(SdpAttribute('candidate', c.toAttrValue()));
    }
    m.attributes.add(SdpAttribute('ice-ufrag', identity.iceUfrag));
    m.attributes.add(SdpAttribute('ice-pwd', identity.icePwd));
    m.attributes.add(SdpAttribute('ice-options', 'trickle'));
    m.attributes.add(SdpAttribute('fingerprint',
        '${identity.fingerprintAlg} ${identity.fingerprintHash}'));
    m.attributes.add(SdpAttribute('setup', setup.attr));
    m.attributes.add(SdpAttribute('mid', mid));
    m.attributes.add(SdpAttribute(dir.attr));
    m.attributes.add(const SdpAttribute('rtcp-mux'));
    m.attributes.add(const SdpAttribute('rtcp-rsize'));
    final tid = trackId ?? _newId();
    m.attributes.add(SdpAttribute('msid', '$streamId $tid'));
    return m;
  }

  /// Produce the final session.
  SdpSession build() {
    final session = SdpSession(
      origin: SdpOrigin(
        username: '-',
        sessionId: sessionId,
        sessionVersion: 2,
        netType: 'IN',
        addrType: 'IP4',
        address: '127.0.0.1',
      ),
      sessionName: '-',
      timing: '0 0',
    );
    final mids =
        _media.map((m) => m.mid ?? '').where((s) => s.isNotEmpty).toList();
    if (mids.isNotEmpty) {
      session.attributes.add(SdpAttribute('group', 'BUNDLE ${mids.join(' ')}'));
    }
    session.attributes.add(const SdpAttribute('extmap-allow-mixed'));
    session.attributes.add(SdpAttribute('msid-semantic', ' WMS $streamId'));
    session.media.addAll(_media);
    return session;
  }
}

/// Builds an answer SDP that mirrors a remote offer.
///
/// For each media section in the offer this picks **one** payload type out
/// of [supportedCodecs] (the first codec whose `name`+`clockRate` matches
/// any of the offer's payload types) and emits a clean answer section with
/// `a=setup:active` (assuming the offer was `actpass`).
///
/// Sections that have no compatible codec are echoed back with `port=0`,
/// which signals rejection in offer/answer.
class SdpAnswerBuilder {
  final SdpSession offer;
  final IceDtlsParams identity;
  final List<IceCandidate> candidates;

  /// Codecs this endpoint is willing to use. Order is preference.
  final List<SdpCodec> supportedCodecs;

  /// Stream id used for outgoing tracks (`a=msid:<stream> <track>`).
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

  SdpSession build() {
    final answer = SdpSession(
      origin: SdpOrigin(
        username: '-',
        sessionId: sessionId,
        sessionVersion: 2,
        address: '127.0.0.1',
      ),
      sessionName: '-',
      timing: '0 0',
    );
    final answeredMids = <String>[];

    for (final om in offer.media) {
      final picked = _pickCodec(om);
      if (picked == null) {
        // Reject this section.
        answer.media.add(SdpMedia(
          type: om.type,
          port: 0,
          protocol: om.protocol,
          payloadTypes: om.payloadTypes.isEmpty ? [0] : [om.payloadTypes.first],
          attributes: [
            if (om.mid != null) SdpAttribute('mid', om.mid!),
          ],
        ));
        continue;
      }
      final mid = om.mid ?? '0';
      answeredMids.add(mid);
      final am = SdpMedia(type: om.type, protocol: om.protocol)
        ..connection =
            SdpConnection(netType: 'IN', addrType: 'IP4', address: '0.0.0.0');
      am.attributes.add(SdpAttribute('rtcp', '9 IN IP4 0.0.0.0'));
      for (final c in candidates) {
        am.attributes.add(SdpAttribute('candidate', c.toAttrValue()));
      }
      am.attributes.add(SdpAttribute('ice-ufrag', identity.iceUfrag));
      am.attributes.add(SdpAttribute('ice-pwd', identity.icePwd));
      am.attributes.add(SdpAttribute('ice-options', 'trickle'));
      am.attributes.add(SdpAttribute('fingerprint',
          '${identity.fingerprintAlg} ${identity.fingerprintHash}'));
      am.attributes.add(SdpAttribute('setup', _answerSetupFor(om).attr));
      am.attributes.add(SdpAttribute('mid', mid));
      am.attributes.add(SdpAttribute(_mirrorDirection(om).attr));
      am.attributes.add(const SdpAttribute('rtcp-mux'));
      am.attributes.add(const SdpAttribute('rtcp-rsize'));
      am.attributes.add(SdpAttribute('msid', '$streamId ${_newId()}'));
      // Apply the chosen codec's lines after the meta-attrs so payloadTypes
      // ends up with exactly one PT and rtpmap/fmtp/rtcp-fb appear together.
      picked.applyTo(am);
      answer.media.add(am);
    }

    if (answeredMids.isNotEmpty) {
      answer.attributes
          .add(SdpAttribute('group', 'BUNDLE ${answeredMids.join(' ')}'));
    }
    answer.attributes.add(const SdpAttribute('extmap-allow-mixed'));
    answer.attributes.add(SdpAttribute('msid-semantic', ' WMS $streamId'));
    return answer;
  }

  SdpCodec? _pickCodec(SdpMedia om) {
    for (final cand in supportedCodecs) {
      for (final pt in om.payloadTypes) {
        final m = om.rtpmapFor(pt);
        if (m == null) continue;
        if (m.encoding.toUpperCase() == cand.name.toUpperCase() &&
            m.clockRate == cand.clockRate) {
          // Reuse the offer's PT so PT mappings stay in sync.
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
    return cand; // unknown subclass: keep original PT
  }

  DtlsSetup _answerSetupFor(SdpMedia om) {
    final s = om.setup;
    if (s == 'actpass' || s == 'passive' || s == null) return DtlsSetup.active;
    if (s == 'active') return DtlsSetup.passive;
    return DtlsSetup.active;
  }

  SdpDirection _mirrorDirection(SdpMedia om) {
    if (om.attr('sendonly') != null) return SdpDirection.recvonly;
    if (om.attr('recvonly') != null) return SdpDirection.sendonly;
    if (om.attr('inactive') != null) return SdpDirection.inactive;
    return SdpDirection.sendrecv;
  }
}

/// 16-byte URL-safe random token (used as msid track id).
String _newId() {
  final bytes = List<int>.generate(16, (_) => _rand.nextInt(256));
  // Hex is fine; browsers don't care as long as it matches.
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

String _newSessionId() {
  // 19-digit numeric session id (browser convention).
  final n = _rand.nextInt(0x7fffffff);
  return '${DateTime.now().microsecondsSinceEpoch}$n';
}

final _rand = _SeededRandom();

/// Tiny xorshift PRNG to avoid pulling in `dart:math`'s `Random.secure()`
/// (which can throw on platforms without a CSPRNG, e.g. some embedded VMs).
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
