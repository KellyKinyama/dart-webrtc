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
