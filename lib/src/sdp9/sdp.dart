import 'package:sdp_transform/sdp_transform.dart';

import 'media.dart';

class Origin {
  String username;
  int sessionId;
  int version;
  String netType;
  int ipVer;
  String address;

  // return {
  //     'username': '-',
  //     'sessionId': '3822856948944450794',
  //     'sessionVersion': 2,
  //     'netType': 'IN',
  //     'ipVer': 4,
  //     'address': '127.0.0.1'
  //   };

  Origin(
      {required this.username,
      required this.sessionId,
      required this.version,
      required this.netType,
      required this.ipVer,
      required this.address});

  factory Origin.fromJson(dynamic orgJson) {
    return Origin(
        username: orgJson["username"],
        sessionId: orgJson["sessionId"],
        version: orgJson["sessionVersion"],
        netType: orgJson["netType"],
        ipVer: orgJson["ipVer"],
        address: orgJson["address"]);
  }

  dynamic toJson() {
    return {
      'username': username,
      'sessionId': sessionId,
      'sessionVersion': version,
      'netType': netType,
      'ipVer': ipVer,
      'address': address
    };
  }
}

class ExtmapAllowMixed {
  String extmapAllowMixed;
  ExtmapAllowMixed(this.extmapAllowMixed);
  factory ExtmapAllowMixed.fromJson(dynamic extmapAllowMixedJson) {
    return ExtmapAllowMixed(extmapAllowMixedJson['extmap-allow-mixed']);
  }
  dynamic toJson() {
    return {'extmap-allow-mixed': extmapAllowMixed};
  }
}

class Timing {
  int start;
  int stop;
  Timing({required this.start, required this.stop});

  factory Timing.fromJson(dynamic timingJson) {
    return Timing(start: timingJson['start'], stop: timingJson['stop']);
  }
  dynamic toJson() {
    return {'start': start, 'stop': stop};
  }
}

class MsidSemantic {
  String semantic;
  String token;
  MsidSemantic({required this.semantic, required this.token});

  factory MsidSemantic.fromJson(dynamic msidSemantic) {
    return MsidSemantic(
        semantic: msidSemantic['semantic'], token: msidSemantic['token']);
  }
  dynamic toJson() {
    return {'semantic': semantic, 'token': token};
  }
}

class Group {
  String type;
  List<int> mids;
  Group({required this.type, required this.mids});

  factory Group.fromJson(dynamic group) {
    List<String> mids = (group['mids'] as String).split(" ");
    return Group(
        type: group['type'],
        mids: List.generate(mids.length, (index) => int.parse(mids[index])));
  }
  dynamic toJson() {
    return {'type': type, 'mids': mids.join(" ")};
  }
}

class Sdp {
  int version;
  Origin origin;
  String name;
  Timing timing;
  List<Group> groups;
  List<ExtmapAllowMixed> extmapAllowMixed;
  MsidSemantic msidSemantic;
  List<Media> medias;

  Sdp(
      {required this.version,
      required this.origin,
      required this.name,
      required this.timing,
      required this.groups,
      required this.extmapAllowMixed,
      required this.msidSemantic,
      required this.medias});

  factory Sdp.fromJson(dynamic sdpJson) {
    return Sdp(
        version: sdpJson['version'],
        origin: Origin.fromJson(sdpJson['origin']),
        name: sdpJson['name'],
        timing: Timing.fromJson(sdpJson['timing']),
        groups: List.generate(sdpJson['groups'].length,
            (index) => Group.fromJson(sdpJson['groups'][index])),
        extmapAllowMixed: List.generate(
            sdpJson['extmapAllowMixed'].length,
            (index) =>
                ExtmapAllowMixed.fromJson(sdpJson['extmapAllowMixed'][index])),
        msidSemantic: MsidSemantic.fromJson(sdpJson['msidSemantic']),
        medias: List.generate(sdpJson['media'].length,
            (index) => Media.fromJson(sdpJson['media'][index])));
  }

  toJson() {
    return {
      'version': version,
      'origin': origin.toJson(),
      'name': name,
      'timing': timing.toJson(),
      'groups': groups.map((group) => group.toJson()).toList(),
      'extmapAllowMixed':
          extmapAllowMixed.map((extmap) => extmap.toJson()).toList(),
      'msidSemantic': msidSemantic.toJson(),
      'media': medias.map((media) => media.toJson()).toList()
    };
  }

  @override
  String toString() {
    return write(toJson(), null);
  }

  factory Sdp.fromString(String sdp) {
    return Sdp.fromJson(parse(sdp));
  }
}

void main() {
  // final sdp = Sdp.fromJson(sdpJson);
  // print("Sdp: ${Sdp.fromString(sdp.toString())}");
  final sdp = Sdp.fromString(sdpOffer["sdp"]!);
  print("Sdp: ${Sdp.fromJson(sdp.toJson())}");
}

final sdpOffer = {
  "type": "offer",
  "sdp":
      "v=0\r\no=- 3822856948944450794 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=group:BUNDLE 0 1\r\na=extmap-allow-mixed\r\na=msid-semantic: WMS 84f453ca-0dbd-4d92-8eec-6b671c88f990\r\nm=audio 51584 UDP/TLS/RTP/SAVPF 111 63 9 0 8 13 110 126\r\nc=IN IP4 102.67.160.2\r\na=rtcp:9 IN IP4 0.0.0.0\r\na=candidate:4057065925 1 udp 2122260223 172.22.16.1 51582 typ host generation 0 network-id 1\r\na=candidate:3027289326 1 udp 2122194687 192.168.56.1 51583 typ host generation 0 network-id 3\r\na=candidate:2359944424 1 udp 2122129151 10.100.53.194 51584 typ host generation 0 network-id 2 network-cost 10\r\na=candidate:259734865 1 tcp 1518280447 172.22.16.1 9 typ host tcptype active generation 0 network-id 1\r\na=candidate:1255805050 1 tcp 1518214911 192.168.56.1 9 typ host tcptype active generation 0 network-id 3\r\na=candidate:1912811644 1 tcp 1518149375 10.100.53.194 9 typ host tcptype active generation 0 network-id 2 network-cost 10\r\na=candidate:1298641826 1 udp 1685921535 102.67.160.2 51584 typ srflx raddr 10.100.53.194 rport 51584 generation 0 network-id 2 network-cost 10\r\na=ice-ufrag:OaAE\r\na=ice-pwd:x/xqQ5Oiwcn41g5m7kUJ3O2+\r\na=ice-options:trickle\r\na=fingerprint:sha-256 4F:AC:D4:CF:2C:76:3A:A1:B8:1B:F3:83:31:2F:C5:BC:30:21:E0:A4:44:DE:2D:81:B9:BB:99:BC:91:7F:8A:39\r\na=setup:actpass\r\na=mid:0\r\na=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level\r\na=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\r\na=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\r\na=extmap:4 urn:ietf:params:rtp-hdrext:sdes:mid\r\na=sendrecv\r\na=msid:84f453ca-0dbd-4d92-8eec-6b671c88f990 660e6102-24a7-43a5-9e01-a733f091341d\r\na=rtcp-mux\r\na=rtcp-rsize\r\na=rtpmap:111 opus/48000/2\r\na=rtcp-fb:111 transport-cc\r\na=fmtp:111 minptime=10;useinbandfec=1\r\na=rtpmap:63 red/48000/2\r\na=fmtp:63 111/111\r\na=rtpmap:9 G722/8000\r\na=rtpmap:0 PCMU/8000\r\na=rtpmap:8 PCMA/8000\r\na=rtpmap:13 CN/8000\r\na=rtpmap:110 telephone-event/48000\r\na=rtpmap:126 telephone-event/8000\r\na=ssrc:1227153705 cname:tcfYxii359Px+p5/\r\na=ssrc:1227153705 msid:84f453ca-0dbd-4d92-8eec-6b671c88f990 660e6102-24a7-43a5-9e01-a733f091341d\r\nm=video 51587 UDP/TLS/RTP/SAVPF 96 97 103 104 107 108 109 114 115 116 117 118 39 40 45 46 98 99 100 101 119 120 49 50 123 124 125\r\nc=IN IP4 102.67.160.2\r\na=rtcp:9 IN IP4 0.0.0.0\r\na=candidate:4057065925 1 udp 2122260223 172.22.16.1 51585 typ host generation 0 network-id 1\r\na=candidate:3027289326 1 udp 2122194687 192.168.56.1 51586 typ host generation 0 network-id 3\r\na=candidate:2359944424 1 udp 2122129151 10.100.53.194 51587 typ host generation 0 network-id 2 network-cost 10\r\na=candidate:259734865 1 tcp 1518280447 172.22.16.1 9 typ host tcptype active generation 0 network-id 1\r\na=candidate:1255805050 1 tcp 1518214911 192.168.56.1 9 typ host tcptype active generation 0 network-id 3\r\na=candidate:1912811644 1 tcp 1518149375 10.100.53.194 9 typ host tcptype active generation 0 network-id 2 network-cost 10\r\na=candidate:1298641826 1 udp 1685921535 102.67.160.2 51587 typ srflx raddr 10.100.53.194 rport 51587 generation 0 network-id 2 network-cost 10\r\na=ice-ufrag:OaAE\r\na=ice-pwd:x/xqQ5Oiwcn41g5m7kUJ3O2+\r\na=ice-options:trickle\r\na=fingerprint:sha-256 4F:AC:D4:CF:2C:76:3A:A1:B8:1B:F3:83:31:2F:C5:BC:30:21:E0:A4:44:DE:2D:81:B9:BB:99:BC:91:7F:8A:39\r\na=setup:actpass\r\na=mid:1\r\na=extmap:14 urn:ietf:params:rtp-hdrext:toffset\r\na=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\r\na=extmap:13 urn:3gpp:video-orientation\r\na=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\r\na=extmap:5 http://www.webrtc.org/experiments/rtp-hdrext/playout-delay\r\na=extmap:6 http://www.webrtc.org/experiments/rtp-hdrext/video-content-type\r\na=extmap:7 http://www.webrtc.org/experiments/rtp-hdrext/video-timing\r\na=extmap:8 http://www.webrtc.org/experiments/rtp-hdrext/color-space\r\na=extmap:4 urn:ietf:params:rtp-hdrext:sdes:mid\r\na=extmap:10 urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id\r\na=extmap:11 urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id\r\na=sendrecv\r\na=msid:84f453ca-0dbd-4d92-8eec-6b671c88f990 7d0980a9-b60d-4ccc-a31c-2e148fb0b1fd\r\na=rtcp-mux\r\na=rtcp-rsize\r\na=rtpmap:96 VP8/90000\r\na=rtcp-fb:96 goog-remb\r\na=rtcp-fb:96 transport-cc\r\na=rtcp-fb:96 ccm fir\r\na=rtcp-fb:96 nack\r\na=rtcp-fb:96 nack pli\r\na=rtpmap:97 rtx/90000\r\na=fmtp:97 apt=96\r\na=rtpmap:103 H264/90000\r\na=rtcp-fb:103 goog-remb\r\na=rtcp-fb:103 transport-cc\r\na=rtcp-fb:103 ccm fir\r\na=rtcp-fb:103 nack\r\na=rtcp-fb:103 nack pli\r\na=fmtp:103 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42001f\r\na=rtpmap:104 rtx/90000\r\na=fmtp:104 apt=103\r\na=rtpmap:107 H264/90000\r\na=rtcp-fb:107 goog-remb\r\na=rtcp-fb:107 transport-cc\r\na=rtcp-fb:107 ccm fir\r\na=rtcp-fb:107 nack\r\na=rtcp-fb:107 nack pli\r\na=fmtp:107 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42001f\r\na=rtpmap:108 rtx/90000\r\na=fmtp:108 apt=107\r\na=rtpmap:109 H264/90000\r\na=rtcp-fb:109 goog-remb\r\na=rtcp-fb:109 transport-cc\r\na=rtcp-fb:109 ccm fir\r\na=rtcp-fb:109 nack\r\na=rtcp-fb:109 nack pli\r\na=fmtp:109 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f\r\na=rtpmap:114 rtx/90000\r\na=fmtp:114 apt=109\r\na=rtpmap:115 H264/90000\r\na=rtcp-fb:115 goog-remb\r\na=rtcp-fb:115 transport-cc\r\na=rtcp-fb:115 ccm fir\r\na=rtcp-fb:115 nack\r\na=rtcp-fb:115 nack pli\r\na=fmtp:115 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42e01f\r\na=rtpmap:116 rtx/90000\r\na=fmtp:116 apt=115\r\na=rtpmap:117 H264/90000\r\na=rtcp-fb:117 goog-remb\r\na=rtcp-fb:117 transport-cc\r\na=rtcp-fb:117 ccm fir\r\na=rtcp-fb:117 nack\r\na=rtcp-fb:117 nack pli\r\na=fmtp:117 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=4d001f\r\na=rtpmap:118 rtx/90000\r\na=fmtp:118 apt=117\r\na=rtpmap:39 H264/90000\r\na=rtcp-fb:39 goog-remb\r\na=rtcp-fb:39 transport-cc\r\na=rtcp-fb:39 ccm fir\r\na=rtcp-fb:39 nack\r\na=rtcp-fb:39 nack pli\r\na=fmtp:39 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=4d001f\r\na=rtpmap:40 rtx/90000\r\na=fmtp:40 apt=39\r\na=rtpmap:45 AV1/90000\r\na=rtcp-fb:45 goog-remb\r\na=rtcp-fb:45 transport-cc\r\na=rtcp-fb:45 ccm fir\r\na=rtcp-fb:45 nack\r\na=rtcp-fb:45 nack pli\r\na=fmtp:45 level-idx=5;profile=0;tier=0\r\na=rtpmap:46 rtx/90000\r\na=fmtp:46 apt=45\r\na=rtpmap:98 VP9/90000\r\na=rtcp-fb:98 goog-remb\r\na=rtcp-fb:98 transport-cc\r\na=rtcp-fb:98 ccm fir\r\na=rtcp-fb:98 nack\r\na=rtcp-fb:98 nack pli\r\na=fmtp:98 profile-id=0\r\na=rtpmap:99 rtx/90000\r\na=fmtp:99 apt=98\r\na=rtpmap:100 VP9/90000\r\na=rtcp-fb:100 goog-remb\r\na=rtcp-fb:100 transport-cc\r\na=rtcp-fb:100 ccm fir\r\na=rtcp-fb:100 nack\r\na=rtcp-fb:100 nack pli\r\na=fmtp:100 profile-id=2\r\na=rtpmap:101 rtx/90000\r\na=fmtp:101 apt=100\r\na=rtpmap:119 H264/90000\r\na=rtcp-fb:119 goog-remb\r\na=rtcp-fb:119 transport-cc\r\na=rtcp-fb:119 ccm fir\r\na=rtcp-fb:119 nack\r\na=rtcp-fb:119 nack pli\r\na=fmtp:119 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=64001f\r\na=rtpmap:120 rtx/90000\r\na=fmtp:120 apt=119\r\na=rtpmap:49 H265/90000\r\na=rtcp-fb:49 goog-remb\r\na=rtcp-fb:49 transport-cc\r\na=rtcp-fb:49 ccm fir\r\na=rtcp-fb:49 nack\r\na=rtcp-fb:49 nack pli\r\na=fmtp:49 level-id=93;profile-id=1;tier-flag=0;tx-mode=SRST\r\na=rtpmap:50 rtx/90000\r\na=fmtp:50 apt=49\r\na=rtpmap:123 red/90000\r\na=rtpmap:124 rtx/90000\r\na=fmtp:124 apt=123\r\na=rtpmap:125 ulpfec/90000\r\na=ssrc-group:FID 3746892314 822236710\r\na=ssrc:3746892314 cname:tcfYxii359Px+p5/\r\na=ssrc:3746892314 msid:84f453ca-0dbd-4d92-8eec-6b671c88f990 7d0980a9-b60d-4ccc-a31c-2e148fb0b1fd\r\na=ssrc:822236710 cname:tcfYxii359Px+p5/\r\na=ssrc:822236710 msid:84f453ca-0dbd-4d92-8eec-6b671c88f990 7d0980a9-b60d-4ccc-a31c-2e148fb0b1fd\r\n"
};
final sdpJson = {
  'version': 0,
  'origin': {
    'username': '-',
    'sessionId': '3822856948944450794',
    'sessionVersion': 2,
    'netType': 'IN',
    'ipVer': 4,
    'address': '127.0.0.1'
  },
  'name': '-',
  'timing': {'start': 0, 'stop': 0},
  'groups': [
    {'type': 'BUNDLE', 'mids': '0 1'}
  ],
  'extmapAllowMixed': [
    {'extmap-allow-mixed': 'extmap-allow-mixed'}
  ],
  'msidSemantic': {
    'semantic': 'WMS',
    'token': '84f453ca-0dbd-4d92-8eec-6b671c88f990'
  },
  'media': [
    {
      'rtp': [
        {'payload': 111, 'codec': 'opus', 'rate': 48000, 'encoding': 2},
        {'payload': 63, 'codec': 'red', 'rate': 48000, 'encoding': 2},
        {'payload': 9, 'codec': 'G722', 'rate': 8000, 'encoding': null},
        {'payload': 0, 'codec': 'PCMU', 'rate': 8000, 'encoding': null},
        {'payload': 8, 'codec': 'PCMA', 'rate': 8000, 'encoding': null},
        {'payload': 13, 'codec': 'CN', 'rate': 8000, 'encoding': null},
        {
          'payload': 110,
          'codec': 'telephone-event',
          'rate': 48000,
          'encoding': null
        },
        {
          'payload': 126,
          'codec': 'telephone-event',
          'rate': 8000,
          'encoding': null
        }
      ],
      'fmtp': [
        {'payload': 111, 'config': 'minptime=10;useinbandfec=1'},
        {'payload': 63, 'config': '111/111'}
      ],
      'type': 'audio',
      'port': 51584,
      'protocol': 'UDP/TLS/RTP/SAVPF',
      'payloads': '111 63 9 0 8 13 110 126',
      'connection': {'version': 4, 'ip': '102.67.160.2'},
      'rtcp': {'port': 9, 'netType': 'IN', 'ipVer': 4, 'address': '0.0.0.0'},
      'candidates': [
        {
          'foundation': '4057065925',
          'component': 1,
          'transport': 'udp',
          'priority': 2122260223,
          'ip': '172.22.16.1',
          'port': 51582,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': null,
          'generation': 0,
          'network-id': 1,
          'network-cost': null
        },
        {
          'foundation': '3027289326',
          'component': 1,
          'transport': 'udp',
          'priority': 2122194687,
          'ip': '192.168.56.1',
          'port': 51583,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': null,
          'generation': 0,
          'network-id': 3,
          'network-cost': null
        },
        {
          'foundation': '2359944424',
          'component': 1,
          'transport': 'udp',
          'priority': 2122129151,
          'ip': '10.100.53.194',
          'port': 51584,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': null,
          'generation': 0,
          'network-id': 2,
          'network-cost': 10
        },
        {
          'foundation': '259734865',
          'component': 1,
          'transport': 'tcp',
          'priority': 1518280447,
          'ip': '172.22.16.1',
          'port': 9,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': 'active',
          'generation': 0,
          'network-id': 1,
          'network-cost': null
        },
        {
          'foundation': '1255805050',
          'component': 1,
          'transport': 'tcp',
          'priority': 1518214911,
          'ip': '192.168.56.1',
          'port': 9,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': 'active',
          'generation': 0,
          'network-id': 3,
          'network-cost': null
        },
        {
          'foundation': '1912811644',
          'component': 1,
          'transport': 'tcp',
          'priority': 1518149375,
          'ip': '10.100.53.194',
          'port': 9,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': 'active',
          'generation': 0,
          'network-id': 2,
          'network-cost': 10
        },
        {
          'foundation': '1298641826',
          'component': 1,
          'transport': 'udp',
          'priority': 1685921535,
          'ip': '102.67.160.2',
          'port': 51584,
          'type': 'srflx',
          'raddr': '10.100.53.194',
          'rport': 51584,
          'tcptype': null,
          'generation': 0,
          'network-id': 2,
          'network-cost': 10
        }
      ],
      'iceUfrag': 'OaAE',
      'icePwd': 'x/xqQ5Oiwcn41g5m7kUJ3O2+',
      'iceOptions': 'trickle',
      'fingerprint': {
        'type': 'sha-256',
        'hash':
            '4F:AC:D4:CF:2C:76:3A:A1:B8:1B:F3:83:31:2F:C5:BC:30:21:E0:A4:44:DE:2D:81:B9:BB:99:BC:91:7F:8A:39'
      },
      'setup': 'actpass',
      'mid': '0',
      'ext': [
        {
          'value': 1,
          'direction': null,
          'uri': 'urn:ietf:params:rtp-hdrext:ssrc-audio-level',
          'config': null
        },
        {
          'value': 2,
          'direction': null,
          'uri': 'http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time',
          'config': null
        },
        {
          'value': 3,
          'direction': null,
          'uri':
              'http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01',
          'config': null
        },
        {
          'value': 4,
          'direction': null,
          'uri': 'urn:ietf:params:rtp-hdrext:sdes:mid',
          'config': null
        }
      ],
      'direction': 'sendrecv',
      'msid':
          '84f453ca-0dbd-4d92-8eec-6b671c88f990 660e6102-24a7-43a5-9e01-a733f091341d',
      'rtcpMux': 'rtcp-mux',
      'rtcpRsize': 'rtcp-rsize',
      'rtcpFb': [
        {'payload': 111, 'type': 'transport-cc', 'subtype': null}
      ],
      'ssrcs': [
        {'id': 1227153705, 'attribute': 'cname', 'value': 'tcfYxii359Px+p5/'},
        {
          'id': 1227153705,
          'attribute': 'msid',
          'value':
              '84f453ca-0dbd-4d92-8eec-6b671c88f990 660e6102-24a7-43a5-9e01-a733f091341d'
        }
      ]
    },
    {
      'rtp': [
        {'payload': 96, 'codec': 'VP8', 'rate': 90000, 'encoding': null},
        {'payload': 97, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
        {'payload': 103, 'codec': 'H264', 'rate': 90000, 'encoding': null},
        {'payload': 104, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
        {'payload': 107, 'codec': 'H264', 'rate': 90000, 'encoding': null},
        {'payload': 108, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
        {'payload': 109, 'codec': 'H264', 'rate': 90000, 'encoding': null},
        {'payload': 114, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
        {'payload': 115, 'codec': 'H264', 'rate': 90000, 'encoding': null},
        {'payload': 116, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
        {'payload': 117, 'codec': 'H264', 'rate': 90000, 'encoding': null},
        {'payload': 118, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
        {'payload': 39, 'codec': 'H264', 'rate': 90000, 'encoding': null},
        {'payload': 40, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
        {'payload': 45, 'codec': 'AV1', 'rate': 90000, 'encoding': null},
        {'payload': 46, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
        {'payload': 98, 'codec': 'VP9', 'rate': 90000, 'encoding': null},
        {'payload': 99, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
        {'payload': 100, 'codec': 'VP9', 'rate': 90000, 'encoding': null},
        {'payload': 101, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
        {'payload': 119, 'codec': 'H264', 'rate': 90000, 'encoding': null},
        {'payload': 120, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
        {'payload': 49, 'codec': 'H265', 'rate': 90000, 'encoding': null},
        {'payload': 50, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
        {'payload': 123, 'codec': 'red', 'rate': 90000, 'encoding': null},
        {'payload': 124, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
        {'payload': 125, 'codec': 'ulfec', 'rate': 90000, 'encoding': null}
      ],
      'fmtp': [
        {'payload': 97, 'config': 'apt=96'},
        {
          'payload': 103,
          'config':
              'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42001f'
        },
        {'payload': 104, 'config': 'apt=103'},
        {
          'payload': 107,
          'config':
              'level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42001f'
        },
        {'payload': 108, 'config': 'apt=107'},
        {
          'payload': 109,
          'config':
              'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f'
        },
        {'payload': 114, 'config': 'apt=109'},
        {
          'payload': 115,
          'config':
              'level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42e01f'
        },
        {'payload': 116, 'config': 'apt=115'},
        {
          'payload': 117,
          'config':
              'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=4d001f'
        },
        {'payload': 118, 'config': 'apt=117'},
        {
          'payload': 39,
          'config':
              'level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=4d001f'
        },
        {'payload': 40, 'config': 'apt=39'},
        {'payload': 45, 'config': 'level-idx=5;profile=0;tier=0'},
        {'payload': 46, 'config': 'apt=45'},
        {'payload': 98, 'config': 'profile-id=0'},
        {'payload': 99, 'config': 'apt=98'},
        {'payload': 100, 'config': 'profile-id=2'},
        {'payload': 101, 'config': 'apt=100'},
        {
          'payload': 119,
          'config':
              'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=64001f'
        },
        {'payload': 120, 'config': 'apt=119'},
        {
          'payload': 49,
          'config': 'level-id=93;profile-id=1;tier-flag=0;tx-mode=SRST'
        },
        {'payload': 50, 'config': 'apt=49'},
        {'payload': 124, 'config': 'apt=123'}
      ],
      'type': 'video',
      'port': 51587,
      'protocol': 'UDP/TLS/RTP/SAVPF',
      'payloads':
          '96 97 103 104 107 108 109 114 115 116 117 118 39 40 45 46 98 99 100 101 119 120 49 50 123 124 125',
      'connection': {'version': 4, 'ip': '102.67.160.2'},
      'rtcp': {'port': 9, 'netType': 'IN', 'ipVer': 4, 'address': '0.0.0.0'},
      'candidates': [
        {
          'foundation': '4057065925',
          'component': 1,
          'transport': 'udp',
          'priority': 2122260223,
          'ip': '172.22.16.1',
          'port': 51585,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': null,
          'generation': 0,
          'network-id': 1,
          'network-cost': null
        },
        {
          'foundation': '3027289326',
          'component': 1,
          'transport': 'udp',
          'priority': 2122194687,
          'ip': '192.168.56.1',
          'port': 51586,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': null,
          'generation': 0,
          'network-id': 3,
          'network-cost': null
        },
        {
          'foundation': '2359944424',
          'component': 1,
          'transport': 'udp',
          'priority': 2122129151,
          'ip': '10.100.53.194',
          'port': 51587,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': null,
          'generation': 0,
          'network-id': 2,
          'network-cost': 10
        },
        {
          'foundation': '259734865',
          'component': 1,
          'transport': 'tcp',
          'priority': 1518280447,
          'ip': '172.22.16.1',
          'port': 9,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': 'active',
          'generation': 0,
          'network-id': 1,
          'network-cost': null
        },
        {
          'foundation': '1255805050',
          'component': 1,
          'transport': 'tcp',
          'priority': 1518214911,
          'ip': '192.168.56.1',
          'port': 9,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': 'active',
          'generation': 0,
          'network-id': 3,
          'network-cost': null
        },
        {
          'foundation': '1912811644',
          'component': 1,
          'transport': 'tcp',
          'priority': 1518149375,
          'ip': '10.100.53.194',
          'port': 9,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': 'active',
          'generation': 0,
          'network-id': 2,
          'network-cost': 10
        },
        {
          'foundation': '1298641826',
          'component': 1,
          'transport': 'udp',
          'priority': 1685921535,
          'ip': '102.67.160.2',
          'port': 51587,
          'type': 'srflx',
          'raddr': '10.100.53.194',
          'rport': 51587,
          'tcptype': null,
          'generation': 0,
          'network-id': 2,
          'network-cost': 10
        }
      ],
      'iceUfrag': 'OaAE',
      'icePwd': 'x/xqQ5Oiwcn41g5m7kUJ3O2+',
      'iceOptions': 'trickle',
      'fingerprint': {
        'type': 'sha-256',
        'hash':
            '4F:AC:D4:CF:2C:76:3A:A1:B8:1B:F3:83:31:2F:C5:BC:30:21:E0:A4:44:DE:2D:81:B9:BB:99:BC:91:7F:8A:39'
      },
      'setup': 'actpass',
      'mid': '1',
      'ext': [
        {
          'value': 14,
          'direction': null,
          'uri': 'urn:ietf:params:rtp-hdrext:toffset',
          'config': null
        },
        {
          'value': 2,
          'direction': null,
          'uri': 'http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time',
          'config': null
        },
        {
          'value': 13,
          'direction': null,
          'uri': 'urn:3gpp:video-orientation',
          'config': null
        },
        {
          'value': 3,
          'direction': null,
          'uri':
              'http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01',
          'config': null
        },
        {
          'value': 5,
          'direction': null,
          'uri': 'http://www.webrtc.org/experiments/rtp-hdrext/playout-delay',
          'config': null
        },
        {
          'value': 6,
          'direction': null,
          'uri':
              'http://www.webrtc.org/experiments/rtp-hdrext/video-content-type',
          'config': null
        },
        {
          'value': 7,
          'direction': null,
          'uri': 'http://www.webrtc.org/experiments/rtp-hdrext/video-timing',
          'config': null
        },
        {
          'value': 8,
          'direction': null,
          'uri': 'http://www.webrtc.org/experiments/rtp-hdrext/color-space',
          'config': null
        },
        {
          'value': 4,
          'direction': null,
          'uri': 'urn:ietf:params:rtp-hdrext:sdes:mid',
          'config': null
        },
        {
          'value': 10,
          'direction': null,
          'uri': 'urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id',
          'config': null
        },
        {
          'value': 11,
          'direction': null,
          'uri': 'urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id',
          'config': null
        }
      ],
      'direction': 'sendrecv',
      'msid':
          '84f453ca-0dbd-4d92-8eec-6b671c88f990 7d0980a9-b60d-4ccc-a31c-2e148fb0b1fd',
      'rtcpMux': 'rtcp-mux',
      'rtcpRsize': 'rtcp-rsize',
      'rtcpFb': [
        {'payload': 96, 'type': 'goog-remb', 'subtype': null},
        {'payload': 96, 'type': 'transport-cc', 'subtype': null},
        {'payload': 96, 'type': 'ccm', 'subtype': 'fir'},
        {'payload': 96, 'type': 'nack', 'subtype': null},
        {'payload': 96, 'type': 'nack', 'subtype': 'pli'},
        {'payload': 103, 'type': 'goog-remb', 'subtype': null},
        {'payload': 103, 'type': 'transport-cc', 'subtype': null},
        {'payload': 103, 'type': 'ccm', 'subtype': 'fir'},
        {'payload': 103, 'type': 'nack', 'subtype': null},
        {'payload': 103, 'type': 'nack', 'subtype': 'pli'},
        {'payload': 107, 'type': 'goog-remb', 'subtype': null},
        {'payload': 107, 'type': 'transport-cc', 'subtype': null},
        {'payload': 107, 'type': 'ccm', 'subtype': 'fir'},
        {'payload': 107, 'type': 'nack', 'subtype': null},
        {'payload': 107, 'type': 'nack', 'subtype': 'pli'},
        {'payload': 109, 'type': 'goog-remb', 'subtype': null},
        {'payload': 109, 'type': 'transport-cc', 'subtype': null},
        {'payload': 109, 'type': 'ccm', 'subtype': 'fir'},
        {'payload': 109, 'type': 'nack', 'subtype': null},
        {'payload': 109, 'type': 'nack', 'subtype': 'pli'},
        {'payload': 115, 'type': 'goog-remb', 'subtype': null},
        {'payload': 115, 'type': 'transport-cc', 'subtype': null},
        {'payload': 115, 'type': 'ccm', 'subtype': 'fir'},
        {'payload': 115, 'type': 'nack', 'subtype': null},
        {'payload': 115, 'type': 'nack', 'subtype': 'pli'},
        {'payload': 117, 'type': 'goog-remb', 'subtype': null},
        {'payload': 117, 'type': 'transport-cc', 'subtype': null},
        {'payload': 117, 'type': 'ccm', 'subtype': 'fir'},
        {'payload': 117, 'type': 'nack', 'subtype': null},
        {'payload': 117, 'type': 'nack', 'subtype': 'pli'},
        {'payload': 39, 'type': 'goog-remb', 'subtype': null},
        {'payload': 39, 'type': 'transport-cc', 'subtype': null},
        {'payload': 39, 'type': 'ccm', 'subtype': 'fir'},
        {'payload': 39, 'type': 'nack', 'subtype': null},
        {'payload': 39, 'type': 'nack', 'subtype': 'pli'},
        {'payload': 45, 'type': 'goog-remb', 'subtype': null},
        {'payload': 45, 'type': 'transport-cc', 'subtype': null},
        {'payload': 45, 'type': 'ccm', 'subtype': 'fir'},
        {'payload': 45, 'type': 'nack', 'subtype': null},
        {'payload': 45, 'type': 'nack', 'subtype': 'pli'},
        {'payload': 98, 'type': 'goog-remb', 'subtype': null},
        {'payload': 98, 'type': 'transport-cc', 'subtype': null},
        {'payload': 98, 'type': 'ccm', 'subtype': 'fir'},
        {'payload': 98, 'type': 'nack', 'subtype': null},
        {'payload': 98, 'type': 'nack', 'subtype': 'pli'},
        {'payload': 100, 'type': 'goog-remb', 'subtype': null},
        {'payload': 100, 'type': 'transport-cc', 'subtype': null},
        {'payload': 100, 'type': 'ccm', 'subtype': 'fir'},
        {'payload': 100, 'type': 'nack', 'subtype': null},
        {'payload': 100, 'type': 'nack', 'subtype': 'pli'},
        {'payload': 119, 'type': 'goog-remb', 'subtype': null},
        {'payload': 119, 'type': 'transport-cc', 'subtype': null},
        {'payload': 119, 'type': 'ccm', 'subtype': 'fir'},
        {'payload': 119, 'type': 'nack', 'subtype': null},
        {'payload': 119, 'type': 'nack', 'subtype': 'pli'},
        {'payload': 49, 'type': 'goog-remb', 'subtype': null},
        {'payload': 49, 'type': 'transport-cc', 'subtype': null},
        {'payload': 49, 'type': 'ccm', 'subtype': 'fir'},
        {'payload': 49, 'type': 'nack', 'subtype': null},
        {'payload': 49, 'type': 'nack', 'subtype': 'pli'}
      ],
      'ssrcGroups': [
        {'semantics': 'FID', 'ssrcs': '3746892314 822236710'}
      ],
      'ssrcs': [
        {'id': 3746892314, 'attribute': 'cname', 'value': 'tcfYxii359Px+p5/'},
        {
          'id': 3746892314,
          'attribute': 'msid',
          'value':
              '84f453ca-0dbd-4d92-8eec-6b671c88f990 7d0980a9-b60d-4ccc-a31c-2e148fb0b1fd'
        },
        {'id': 822236710, 'attribute': 'cname', 'value': 'tcfYxii359Px+p5/'},
        {
          'id': 822236710,
          'attribute': 'msid',
          'value':
              '84f453ca-0dbd-4d92-8eec-6b671c88f990 7d0980a9-b60d-4ccc-a31c-2e148fb0b1fd'
        }
      ]
    }
  ]
};
