// Full Dart WebRTC SDP parser and builder with Chrome Offer SDP support.

class SessionDescription {
  final String type;
  final String sdp;

  SessionDescription({required this.type, required this.sdp});

  factory SessionDescription.parse(String sdp) {
    final lines =
        sdp.split(RegExp(r'\r?\n')).where((line) => line.isNotEmpty).toList();
    if (lines.isEmpty || !lines[0].startsWith('v=')) {
      throw FormatException('Invalid SDP: missing version line');
    }
    return SessionDescription(type: 'offer', sdp: sdp);
  }

  String build() {
    return sdp;
  }
}

class SdpParser {
  static Map<String, dynamic> parse(String rawSdp) {
    final lines = rawSdp.split(RegExp(r'\r?\n'));
    final session = <String, dynamic>{};
    final media = <Map<String, dynamic>>[];
    Map<String, dynamic>? currentMedia;

    for (var line in lines) {
      if (line.isEmpty) continue;
      final prefix = line.substring(0, 2);
      final content = line.length > 2 ? line.substring(2) : '';

      switch (prefix) {
        case 'v=':
          session['version'] = content;
          break;
        case 'o=':
          session['origin'] = content;
          break;
        case 's=':
          session['sessionName'] = content;
          break;
        case 't=':
          session['timing'] = content;
          break;
        case 'a=':
          _parseAttribute(session, currentMedia, content);
          break;
        case 'm=':
          currentMedia = {
            'media': content,
            'attributes': [],
          };
          media.add(currentMedia);
          break;
        case 'c=':
          if (currentMedia != null) {
            currentMedia['connection'] = content;
          } else {
            session['connection'] = content;
          }
          break;
        case 'b=':
          if (currentMedia != null) {
            currentMedia['bandwidth'] = content;
          } else {
            session['bandwidth'] = content;
          }
          break;
      }
    }

    session['media'] = media;
    return session;
  }

  static void _parseAttribute(
      Map<String, dynamic> session, Map<String, dynamic>? media, String line) {
    final parts = line.split(':');
    final attribute = parts[0];
    final value = parts.length > 1 ? parts.sublist(1).join(':') : null;

    if (media != null) {
      media['attributes'].add({
        'attribute': attribute,
        'value': value,
      });
    } else {
      session['attributes'] = session['attributes'] ?? [];
      (session['attributes'] as List).add({
        'attribute': attribute,
        'value': value,
      });
    }
  }
}

class SdpBuilder {
  static String build(Map<String, dynamic> session) {
    final buffer = StringBuffer();

    if (session.containsKey('version'))
      buffer.writeln('v=${session['version']}');
    if (session.containsKey('origin')) buffer.writeln('o=${session['origin']}');
    if (session.containsKey('sessionName'))
      buffer.writeln('s=${session['sessionName']}');
    if (session.containsKey('timing')) buffer.writeln('t=${session['timing']}');
    if (session.containsKey('connection'))
      buffer.writeln('c=${session['connection']}');

    if (session['attributes'] != null) {
      for (final attr in session['attributes']) {
        buffer.writeln(
            'a=${attr['attribute']}${attr['value'] != null ? ":${attr['value']}" : ''}');
      }
    }

    if (session['media'] != null) {
      for (final m in session['media']) {
        buffer.writeln('m=${m['media']}');
        if (m['connection'] != null) buffer.writeln('c=${m['connection']}');
        if (m['bandwidth'] != null) buffer.writeln('b=${m['bandwidth']}');

        for (final attr in m['attributes']) {
          buffer.writeln(
              'a=${attr['attribute']}${attr['value'] != null ? ":${attr['value']}" : ''}');
        }
      }
    }

    return buffer.toString();
  }
}

void main() {
  const chromeOfferSdp =
      """v=0\r\no=- 4215775240449105457 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=group:BUNDLE 0 1\r\na=extmap-allow-mixed\r\na=msid-semantic: WMS 160d6347-77ea-40b8-aded-2b586daf50ea\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111 63 9 0 8 13 110 126\r\nc=IN IP4 0.0.0.0\r\na=rtcp:9 IN IP4 0.0.0.0\r\na=ice-ufrag:yxYb\r\na=ice-pwd:05iMxO9GujD2fUWXSoi0ByNd\r\na=ice-options:trickle\r\na=fingerprint:sha-256 B4:C4:F9:49:A6:5A:11:49:3E:66:BD:1F:B3:43:E3:54:A9:3E:1D:11:71:5B:E0:4D:5F:F4:BC:D2:19:3B:84:E5\r\na=setup:actpass\r\na=mid:0\r\na=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level\r\n...""";

  final session = SdpParser.parse(chromeOfferSdp);
  final rebuiltSdp = SdpBuilder.build(session);

  print('Original SDP Length: ${chromeOfferSdp.length}');
  print('Rebuilt SDP Length: ${rebuiltSdp.length}');
  print('Rebuilt SDP Preview:\n$rebuiltSdp');
}
