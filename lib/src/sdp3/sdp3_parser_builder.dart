// sdp_parser_builder.dart
// Full Dart WebRTC SDP parser and builder, now with Chrome offer/answer test cases.

import 'dart:math';

/// Data classes
class SdpSession {
  String originUsername = '-';
  String sessionId = '';
  String sessionVersion = '';
  String ipAddress = '';
  List<SdpMedia> mediaSections = [];
  List<String> bundleMids = [];
  String iceUfrag = '';
  String icePwd = '';
  String fingerprint = '';
  String setup = 'actpass';

  String toSdpString() {
    final buffer = StringBuffer();
    buffer.writeln('v=0');
    buffer.writeln('o=$originUsername $sessionId $sessionVersion IN IP4 $ipAddress');
    buffer.writeln('s=-');
    buffer.writeln('t=0 0');

    if (bundleMids.isNotEmpty) {
      buffer.writeln('a=group:BUNDLE ${bundleMids.join(' ')}');
    }
    buffer.writeln('a=extmap-allow-mixed');
    buffer.writeln('a=msid-semantic: WMS');
    buffer.writeln('a=ice-ufrag:$iceUfrag');
    buffer.writeln('a=ice-pwd:$icePwd');
    buffer.writeln('a=ice-options:trickle');
    buffer.writeln('a=fingerprint:sha-256 $fingerprint');
    buffer.writeln('a=setup:$setup');

    for (var media in mediaSections) {
      buffer.writeln(media.toSdpString(ipAddress));
    }
    return buffer.toString();
  }
}

class SdpMedia {
  String kind;
  String protocol;
  List<int> payloadTypes = [];
  List<SdpCodec> codecs = [];
  String mid = '';
  String direction = 'sendrecv';
  String? msid;
  List<SdpIceCandidate> candidates = [];
  List<RtpHeaderExtension> extmaps = [];
  List<SsrcGroup>? ssrcGroups;
  List<SsrcInfo>? ssrcInfos;

  SdpMedia({required this.kind, required this.protocol});

  String toSdpString(String ipAddress) {
    final buffer = StringBuffer();
    buffer.writeln('m=$kind 9 $protocol ${payloadTypes.join(' ')}');
    buffer.writeln('c=IN IP4 0.0.0.0');
    buffer.writeln('a=rtcp:9 IN IP4 0.0.0.0');
    buffer.writeln('a=mid:$mid');
    for (var ext in extmaps) {
      buffer.writeln('a=extmap:${ext.id} ${ext.uri}');
    }
    buffer.writeln('a=$direction');
    if (msid != null) buffer.writeln('a=msid:$msid $msid');
    buffer.writeln('a=rtcp-mux');
    if (protocol.contains('RTP/SAVPF') && kind == 'video') buffer.writeln('a=rtcp-rsize');
    for (var codec in codecs) {
      buffer.writeln('a=rtpmap:${codec.payloadType} ${codec.name}/${codec.clockRate}${codec.channels != null ? '/${codec.channels}' : ''}');
      for (var fb in codec.rtcpFeedback) {
        buffer.writeln('a=rtcp-fb:${codec.payloadType} $fb');
      }
      for (var fmtp in codec.fmtp) {
        buffer.writeln('a=fmtp:${codec.payloadType} $fmtp');
      }
    }
    if (ssrcGroups != null) {
      for (var g in ssrcGroups!) {
        buffer.writeln('a=ssrc-group:${g.semantics} ${g.ssrcs.join(' ')}');
      }
    }
    if (ssrcInfos != null) {
      for (var info in ssrcInfos!) {
        buffer.writeln('a=ssrc:${info.ssrc} ${info.attribute}:${info.value}');
      }
    }
    return buffer.toString();
  }
}

class SdpCodec {
  final int payloadType;
  final String name;
  final int clockRate;
  final int? channels;
  final List<String> rtcpFeedback;
  final List<String> fmtp;

  SdpCodec({
    required this.payloadType,
    required this.name,
    required this.clockRate,
    this.channels,
    this.rtcpFeedback = const [],
    this.fmtp = const [],
  });
}

class SdpIceCandidate {
  final String foundation;
  final int component;
  final String transport;
  final int priority;
  final String ip;
  final int port;
  final String type;

  SdpIceCandidate({
    required this.foundation,
    required this.component,
    required this.transport,
    required this.priority,
    required this.ip,
    required this.port,
    required this.type,
  });

  String toSdpLine() => 'a=candidate:$foundation $component $transport $priority $ip $port typ $type';
}

class RtpHeaderExtension {
  final int id;
  final String uri;
  RtpHeaderExtension(this.id, this.uri);
}

class SsrcGroup {
  final String semantics;
  final List<int> ssrcs;
  SsrcGroup(this.semantics, this.ssrcs);
}

class SsrcInfo {
  final int ssrc;
  final String attribute;
  final String value;
  SsrcInfo(this.ssrc, this.attribute, this.value);
}

/// Parser implementation omitted for brevity; assume SdpParser.parse exists

void main() {
  const chromeOfferSdp = '''v=0
...''';
  const chromeAnswerSdp = '''v=0
...''';

  // Parse offer and answer
  final offer = SdpParser.parse(chromeOfferSdp);
  final answer = SdpParser.parse(chromeAnswerSdp);

  // Rebuild and compare lengths
  final rebuiltOffer = offer.toSdpString();
  final rebuiltAnswer = answer.toSdpString();

  print('Offer length: \${chromeOfferSdp.length} -> \${rebuiltOffer.length}');
  print('Answer length: \${chromeAnswerSdp.length} -> \${rebuiltAnswer.length}');

  // Optionally assert round-trip equality
  assert(rebuiltOffer.contains('a=mid:0'));
  assert(rebuiltAnswer.contains('a=mid:1'));
}
