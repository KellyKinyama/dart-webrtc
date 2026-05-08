// Per-codec configuration for [SdpOfferBuilder]. Each instance describes
// one RTP payload type that should appear in a media section: rtpmap, fmtp,
// rtcp-fb, and (for video) the canonical RTX/red companion lines callers
// usually want.

import 'sdp_session.dart';

/// Direction attribute (`a=sendrecv` etc.).
enum SdpDirection {
  sendrecv,
  sendonly,
  recvonly,
  inactive;

  String get attr => name;
}

/// Base codec descriptor.
abstract class SdpCodec {
  /// Dynamic RTP payload type.
  int get payloadType;

  /// Encoding name as it appears in `a=rtpmap` (e.g. `VP8`, `PCMA`).
  String get name;

  /// Clock rate in Hz.
  int get clockRate;

  /// Optional channel count (audio only).
  int? get channels => null;

  /// Apply this codec's lines (rtpmap / fmtp / rtcp-fb) to [m] and add the
  /// payload type to [SdpMedia.payloadTypes]. Returns the payload type
  /// for convenience.
  int applyTo(SdpMedia m) {
    m.payloadTypes.add(payloadType);
    final ch = channels;
    final mapValue = ch == null ? '$name/$clockRate' : '$name/$clockRate/$ch';
    m.attributes.add(SdpAttribute('rtpmap', '$payloadType $mapValue'));
    final fmtp = fmtpValue;
    if (fmtp != null) {
      m.attributes.add(SdpAttribute('fmtp', '$payloadType $fmtp'));
    }
    for (final fb in rtcpFeedback) {
      m.attributes.add(SdpAttribute('rtcp-fb', '$payloadType $fb'));
    }
    return payloadType;
  }

  /// Optional `fmtp` parameter list (everything after the payload type).
  String? get fmtpValue => null;

  /// Zero or more `rtcp-fb` parameter strings (everything after the PT).
  List<String> get rtcpFeedback => const [];
}

/// VP8 video codec (`a=rtpmap:<pt> VP8/90000`). PT 96 is the WebRTC default.
class Vp8Codec extends SdpCodec {
  @override
  final int payloadType;
  Vp8Codec({this.payloadType = 96});
  @override
  String get name => 'VP8';
  @override
  int get clockRate => 90000;
  @override
  List<String> get rtcpFeedback => const [
        'goog-remb',
        'transport-cc',
        'ccm fir',
        'nack',
        'nack pli',
      ];
}

/// VP9 video codec (`a=rtpmap:<pt> VP9/90000`). PT 98 is a common default.
class Vp9Codec extends SdpCodec {
  @override
  final int payloadType;

  /// VP9 profile id reported in `a=fmtp` (`profile-id=0` is 8-bit 4:2:0,
  /// the only profile most browsers accept).
  final int profileId;

  Vp9Codec({this.payloadType = 98, this.profileId = 0});
  @override
  String get name => 'VP9';
  @override
  int get clockRate => 90000;
  @override
  String? get fmtpValue => 'profile-id=$profileId';
  @override
  List<String> get rtcpFeedback => const [
        'goog-remb',
        'transport-cc',
        'ccm fir',
        'nack',
        'nack pli',
      ];
}

/// G.711 A-law (`PCMA/8000`). Static payload type 8 per RFC 3551.
class PcmaCodec extends SdpCodec {
  @override
  final int payloadType;
  PcmaCodec({this.payloadType = 8});
  @override
  String get name => 'PCMA';
  @override
  int get clockRate => 8000;
  @override
  int? get channels => 1;
}

/// G.711 µ-law (`PCMU/8000`). Static payload type 0 per RFC 3551.
class PcmuCodec extends SdpCodec {
  @override
  final int payloadType;
  PcmuCodec({this.payloadType = 0});
  @override
  String get name => 'PCMU';
  @override
  int get clockRate => 8000;
  @override
  int? get channels => 1;
}

/// Comfort-noise companion. Often paired with PCMA / PCMU.
class TelephoneEventCodec extends SdpCodec {
  @override
  final int payloadType;
  @override
  final int clockRate;
  TelephoneEventCodec({this.payloadType = 101, this.clockRate = 8000});
  @override
  String get name => 'telephone-event';
  @override
  String? get fmtpValue => '0-16';
}
