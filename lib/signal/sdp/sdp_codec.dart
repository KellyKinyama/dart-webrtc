// Codec descriptors that emit `rtpmap`, `fmtp`, and `rtcp-fb` entries into
// a media-section map produced by `package:sdp_transform`.
//
// Each [SdpCodec.applyTo] call:
//   - appends its payload type to `media['payloads']`,
//   - pushes one entry into `media['rtp']`,
//   - optionally pushes one entry into `media['fmtp']`,
//   - pushes zero or more entries into `media['rtcpFb']`.

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
  /// RTP payload type. Dynamic codecs (VP8/VP9/Opus) typically use 96-127;
  /// G.711 PCMU/PCMA have static numbers (0 / 8) per RFC 3551.
  int get payloadType;

  /// Encoding name as it appears in `a=rtpmap`.
  String get name;

  /// Clock rate in Hz.
  int get clockRate;

  /// Optional channel count (audio only).
  int? get channels => null;

  /// Optional `fmtp` config (everything after `a=fmtp:<pt> `).
  String? get fmtpValue => null;

  /// Zero or more `rtcp-fb` parameter strings (everything after `<pt>`).
  List<String> get rtcpFeedback => const [];

  /// Append this codec's lines to a media map. Returns the payload type for
  /// chaining. The map must use the `sdp_transform` shape.
  int applyTo(Map<String, dynamic> media) {
    final pt = payloadType;
    final payloads = (media['payloads'] as String? ?? '').trim();
    media['payloads'] = payloads.isEmpty ? '$pt' : '$payloads $pt';

    final rtp = (media['rtp'] as List?) ?? <Map<String, dynamic>>[];
    final entry = <String, dynamic>{
      'payload': pt,
      'codec': name,
      'rate': clockRate,
    };
    final ch = channels;
    if (ch != null) entry['encoding'] = ch;
    rtp.add(entry);
    media['rtp'] = rtp;

    final fmtp = fmtpValue;
    if (fmtp != null) {
      final list = (media['fmtp'] as List?) ?? <Map<String, dynamic>>[];
      list.add({'payload': pt, 'config': fmtp});
      media['fmtp'] = list;
    }
    final fb = rtcpFeedback;
    if (fb.isNotEmpty) {
      final list = (media['rtcpFb'] as List?) ?? <Map<String, dynamic>>[];
      for (final item in fb) {
        final parts = item.split(' ');
        final m = <String, dynamic>{'payload': pt, 'type': parts[0]};
        if (parts.length > 1) m['subtype'] = parts.sublist(1).join(' ');
        list.add(m);
      }
      media['rtcpFb'] = list;
    }
    return pt;
  }
}

/// VP8 (`VP8/90000`). PT 96 is the WebRTC default.
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

/// H.264 (`H264/90000`). PT 102 is a common WebRTC default.
///
/// Browsers strictly validate the `profile-level-id` in `a=fmtp`. The
/// default `42e01f` (Constrained Baseline 3.1, packetization-mode=1) is
/// the safest interop choice — Chrome, Edge, Firefox and Safari all
/// negotiate it. Cameras almost always emit a Baseline / Main bitstream
/// that decodes inside this profile envelope.
class H264Codec extends SdpCodec {
  @override
  final int payloadType;

  /// `profile-level-id` hex string (3 bytes — profile_idc, profile_iop,
  /// level_idc).
  final String profileLevelId;

  /// RFC 6184 §5.4: 0 = single-NAL only, 1 = non-interleaved (FU-A +
  /// STAP-A). Browsers require mode 1 in practice.
  final int packetizationMode;

  H264Codec({
    this.payloadType = 102,
    this.profileLevelId = '42e01f',
    this.packetizationMode = 1,
  });

  @override
  String get name => 'H264';
  @override
  int get clockRate => 90000;
  @override
  String? get fmtpValue =>
      'level-asymmetry-allowed=1;packetization-mode=$packetizationMode;'
      'profile-level-id=$profileLevelId';
  @override
  List<String> get rtcpFeedback => const [
        'goog-remb',
        'transport-cc',
        'ccm fir',
        'nack',
        'nack pli',
      ];
}

/// VP9 (`VP9/90000`). PT 98 is a common default.
class Vp9Codec extends SdpCodec {
  @override
  final int payloadType;

  /// VP9 profile reported in `a=fmtp` (`profile-id=0` is 8-bit 4:2:0).
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

/// G.711 A-law (`PCMA/8000`). Static payload type 8.
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

/// G.711 µ-law (`PCMU/8000`). Static payload type 0.
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

/// `telephone-event` (DTMF) companion, usually paired with PCMA / PCMU.
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

/// RTX retransmission stream (`rtx/90000`) — RFC 4588.
///
/// Carries lost packets of a primary codec identified by [apt] (associated
/// payload type). Browsers won't perform NACK-driven retransmission unless
/// every primary video codec they offer also has a paired RTX entry.
class RtxCodec extends SdpCodec {
  @override
  final int payloadType;

  /// The primary codec's payload type that this RTX stream retransmits.
  final int apt;

  @override
  final int clockRate;

  RtxCodec({
    required this.payloadType,
    required this.apt,
    this.clockRate = 90000,
  });

  @override
  String get name => 'rtx';

  @override
  String? get fmtpValue => 'apt=$apt';
}

/// Single `a=extmap:<id> <uri>` declaration.
///
/// IDs are scoped per session; if you want the same extension in multiple
/// media sections they MUST share the same id (BUNDLE requirement).
class SdpRtpExtension {
  final int id;
  final String uri;
  final String? direction; // null, 'sendonly', 'recvonly', 'inactive'

  const SdpRtpExtension({
    required this.id,
    required this.uri,
    this.direction,
  });

  /// Append `a=extmap:` to a media section map.
  void applyTo(Map<String, dynamic> media) {
    final list = (media['ext'] as List?) ?? <Map<String, dynamic>>[];
    final entry = <String, dynamic>{'value': id, 'uri': uri};
    if (direction != null) entry['direction'] = direction;
    list.add(entry);
    media['ext'] = list;
  }

  // ---- Well-known URIs ----------------------------------------------

  /// `urn:ietf:params:rtp-hdrext:sdes:mid` — required for BUNDLE.
  static const String midUri = 'urn:ietf:params:rtp-hdrext:sdes:mid';

  /// `http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time`.
  static const String absSendTimeUri =
      'http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time';

  /// transport-wide congestion control sequence number.
  static const String transportCcUri =
      'http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01';

  /// `urn:ietf:params:rtp-hdrext:toffset` — RTP timestamp offset.
  static const String toffsetUri = 'urn:ietf:params:rtp-hdrext:toffset';
}
