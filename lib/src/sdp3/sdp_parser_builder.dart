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
    buffer.writeln('a=ice-ufrag:$iceUfrag');
    buffer.writeln('a=ice-pwd:$icePwd');
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

  SdpMedia({required this.kind, required this.protocol});

  String toSdpString(String ipAddress) {
    final buffer = StringBuffer();
    buffer.writeln('m=$kind 9 $protocol ${payloadTypes.join(' ')}');
    buffer.writeln('c=IN IP4 $ipAddress');
    buffer.writeln('a=mid:$mid');
    buffer.writeln('a=$direction');
    if (msid != null) {
      buffer.writeln('a=msid:$msid $msid');
    }
    for (var codec in codecs) {
      buffer.writeln('a=rtpmap:${codec.payloadType} ${codec.name}/${codec.clockRate}');
    }
    for (var candidate in candidates) {
      buffer.writeln(candidate.toSdpLine());
    }
    buffer.writeln('a=end-of-candidates');
    return buffer.toString();
  }
}

class SdpCodec {
  final int payloadType;
  final String name;
  final int clockRate;

  SdpCodec({
    required this.payloadType,
    required this.name,
    required this.clockRate,
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

  String toSdpLine() {
    return 'a=candidate:$foundation $component $transport $priority $ip $port typ $type';
  }

  static SdpIceCandidate parse(String candidateLine) {
    final parts = candidateLine.split(RegExp(r'\s+'));
    return SdpIceCandidate(
      foundation: parts[0],
      component: int.parse(parts[1]),
      transport: parts[2],
      priority: int.parse(parts[3]),
      ip: parts[4],
      port: int.parse(parts[5]),
      type: parts[7],
    );
  }
}

/// Parser

class SdpParser {
  static SdpSession parse(String sdpText) {
    final lines = sdpText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final session = SdpSession();
    SdpMedia? currentMedia;

    for (var line in lines) {
      if (line.startsWith('o=')) {
        final parts = line.substring(2).split(' ');
        session.originUsername = parts[0];
        session.sessionId = parts[1];
        session.sessionVersion = parts[2];
        session.ipAddress = parts[5];
      } else if (line.startsWith('a=group:BUNDLE')) {
        session.bundleMids = line.substring('a=group:BUNDLE'.length).trim().split(' ');
      } else if (line.startsWith('a=ice-ufrag:')) {
        session.iceUfrag = line.substring('a=ice-ufrag:'.length);
      } else if (line.startsWith('a=ice-pwd:')) {
        session.icePwd = line.substring('a=ice-pwd:'.length);
      } else if (line.startsWith('a=fingerprint:')) {
        session.fingerprint = line.substring('a=fingerprint:sha-256'.length).trim();
      } else if (line.startsWith('a=setup:')) {
        session.setup = line.substring('a=setup:'.length);
      } else if (line.startsWith('m=')) {
        final parts = line.substring(2).split(' ');
        currentMedia = SdpMedia(kind: parts[0], protocol: parts[2]);
        currentMedia.payloadTypes = parts.sublist(3).map((p) => int.parse(p)).toList();
        session.mediaSections.add(currentMedia);
      } else if (line.startsWith('a=mid:') && currentMedia != null) {
        currentMedia.mid = line.substring('a=mid:'.length);
      } else if (line.startsWith('a=sendrecv') && currentMedia != null) {
        currentMedia.direction = 'sendrecv';
      } else if (line.startsWith('a=sendonly') && currentMedia != null) {
        currentMedia.direction = 'sendonly';
      } else if (line.startsWith('a=recvonly') && currentMedia != null) {
        currentMedia.direction = 'recvonly';
      } else if (line.startsWith('a=inactive') && currentMedia != null) {
        currentMedia.direction = 'inactive';
      } else if (line.startsWith('a=msid:') && currentMedia != null) {
        currentMedia.msid = line.substring('a=msid:'.length).split(' ')[0];
      } else if (line.startsWith('a=rtpmap:') && currentMedia != null) {
        final parts = line.substring('a=rtpmap:'.length).split(' ');
        final payloadType = int.parse(parts[0]);
        final codecParts = parts[1].split('/');
        final codecName = codecParts[0];
        final clockRate = int.parse(codecParts[1]);
        currentMedia.codecs.add(SdpCodec(payloadType: payloadType, name: codecName, clockRate: clockRate));
      } else if (line.startsWith('a=candidate:') && currentMedia != null) {
        final candidateLine = line.substring('a=candidate:'.length);
        currentMedia.candidates.add(SdpIceCandidate.parse(candidateLine));
      }
    }

    return session;
  }
}
