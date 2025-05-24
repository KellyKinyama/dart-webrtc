import 'package:sdp_transform/sdp_transform.dart';

String? asString(dynamic value) => value?.toString();
int? asInt(dynamic value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '');

class SdpObject {
  final int version;
  final Origin origin;
  final String name;
  final Timing timing;
  final List<Group> groups;
  final List<Map<String, String>> extmapAllowMixed;
  final MsidSemantic msidSemantic;
  final List<Media> media;

  SdpObject({
    required this.version,
    required this.origin,
    required this.name,
    required this.timing,
    required this.groups,
    required this.extmapAllowMixed,
    required this.msidSemantic,
    required this.media,
  });

  factory SdpObject.fromJson(Map<String, dynamic> json) => SdpObject(
        version: json['version'],
        origin: Origin.fromJson(json['origin']),
        name: json['name'],
        timing: Timing.fromJson(json['timing']),
        groups: (json['groups'] as List).map((e) => Group.fromJson(e)).toList(),
        extmapAllowMixed: List<Map<String, String>>.from(
            json['extmapAllowMixed'].map((e) => Map<String, String>.from(e))),
        msidSemantic: MsidSemantic.fromJson(json['msidSemantic']),
        media: (json['media'] as List).map((e) => Media.fromJson(e)).toList(),
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'origin': origin.toJson(),
        'name': name,
        'timing': timing.toJson(),
        'groups': groups.map((e) => e.toJson()).toList(),
        'extmapAllowMixed': extmapAllowMixed,
        'msidSemantic': msidSemantic.toJson(),
        'media': media.map((e) => e.toJson()).toList(),
      };
}

class Origin {
  final String username;
  final int sessionId;
  final int sessionVersion;
  final String netType;
  final int ipVer;
  final String address;

  Origin({
    required this.username,
    required this.sessionId,
    required this.sessionVersion,
    required this.netType,
    required this.ipVer,
    required this.address,
  });

  factory Origin.fromJson(Map<String, dynamic> json) => Origin(
        username: json['username'],
        sessionId: json['sessionId'],
        sessionVersion: json['sessionVersion'],
        netType: json['netType'],
        ipVer: json['ipVer'],
        address: json['address'],
      );

  Map<String, dynamic> toJson() => {
        'username': username,
        'sessionId': sessionId,
        'sessionVersion': sessionVersion,
        'netType': netType,
        'ipVer': ipVer,
        'address': address,
      };
}

class Timing {
  final int start;
  final int stop;

  Timing({required this.start, required this.stop});

  factory Timing.fromJson(Map<String, dynamic> json) =>
      Timing(start: json['start'], stop: json['stop']);

  Map<String, dynamic> toJson() => {'start': start, 'stop': stop};
}

class Group {
  final String type;
  final String mids;

  Group({required this.type, required this.mids});

  factory Group.fromJson(Map<String, dynamic> json) =>
      Group(type: json['type'], mids: json['mids']);

  Map<String, dynamic> toJson() => {'type': type, 'mids': mids};
}

class MsidSemantic {
  final String semantic;
  final String token;

  MsidSemantic({required this.semantic, required this.token});

  factory MsidSemantic.fromJson(Map<String, dynamic> json) =>
      MsidSemantic(semantic: json['semantic'], token: json['token']);

  Map<String, dynamic> toJson() => {'semantic': semantic, 'token': token};
}

class Media {
  final String? type;
  final int? port;
  final String? protocol;
  final String? payloads;
  final Connection? connection;
  final Rtcp? rtcp;
  final String? iceUfrag;
  final String? icePwd;
  final String? iceOptions;
  final Fingerprint? fingerprint;
  final String? setup;
  final String? mid;
  final List<Rtp> rtp;
  final List<Fmtp> fmtp;
  final List<Ext> ext;
  final String? direction;
  final String? msid;
  final String? rtcpMux;
  final String? rtcpRsize;
  final List<RtcpFb> rtcpFb;
  final List<Ssrc> ssrcs;
  final List<SsrcGroup> ssrcGroups;

  Media({
    this.type,
    this.port,
    this.protocol,
    this.payloads,
    this.connection,
    this.rtcp,
    this.iceUfrag,
    this.icePwd,
    this.iceOptions,
    this.fingerprint,
    this.setup,
    this.mid,
    this.rtp = const [],
    this.fmtp = const [],
    this.ext = const [],
    this.direction,
    this.msid,
    this.rtcpMux,
    this.rtcpRsize,
    this.rtcpFb = const [],
    this.ssrcs = const [],
    this.ssrcGroups = const [],
  });

  factory Media.fromJson(Map<String, dynamic> json) => Media(
        type: asString(json['type']),
        port: asInt(json['port']),
        protocol: asString(json['protocol']),
        payloads: asString(json['payloads']),
        connection: json['connection'] != null
            ? Connection.fromJson(json['connection'])
            : null,
        rtcp: json['rtcp'] != null ? Rtcp.fromJson(json['rtcp']) : null,
        iceUfrag: asString(json['iceUfrag']),
        icePwd: asString(json['icePwd']),
        iceOptions: asString(json['iceOptions']),
        fingerprint: json['fingerprint'] != null
            ? Fingerprint.fromJson(json['fingerprint'])
            : null,
        setup: asString(json['setup']),
        mid: asString(json['mid']),
        rtp: (json['rtp'] as List?)?.map((e) => Rtp.fromJson(e)).toList() ?? [],
        fmtp: (json['fmtp'] as List?)?.map((e) => Fmtp.fromJson(e)).toList() ??
            [],
        ext: (json['ext'] as List?)?.map((e) => Ext.fromJson(e)).toList() ?? [],
        direction: asString(json['direction']),
        msid: asString(json['msid']),
        rtcpMux: asString(json['rtcpMux']),
        rtcpRsize: asString(json['rtcpRsize']),
        rtcpFb: (json['rtcpFb'] as List?)
                ?.map((e) => RtcpFb.fromJson(e))
                .toList() ??
            [],
        ssrcs:
            (json['ssrcs'] as List?)?.map((e) => Ssrc.fromJson(e)).toList() ??
                [],
        ssrcGroups: (json['ssrcGroups'] as List?)
                ?.map((e) => SsrcGroup.fromJson(e))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'port': port,
        'protocol': protocol,
        'payloads': payloads,
        'connection': connection?.toJson(),
        'rtcp': rtcp?.toJson(),
        'iceUfrag': iceUfrag,
        'icePwd': icePwd,
        'iceOptions': iceOptions,
        'fingerprint': fingerprint?.toJson(),
        'setup': setup,
        'mid': mid,
        'rtp': rtp.map((e) => e.toJson()).toList(),
        'fmtp': fmtp.map((e) => e.toJson()).toList(),
        'ext': ext.map((e) => e.toJson()).toList(),
        'direction': direction,
        'msid': msid,
        'rtcpMux': rtcpMux,
        'rtcpRsize': rtcpRsize,
        'rtcpFb': rtcpFb.map((e) => e.toJson()).toList(),
        'ssrcs': ssrcs.map((e) => e.toJson()).toList(),
        'ssrcGroups': ssrcGroups.map((e) => e.toJson()).toList(),
      };
}

class Connection {
  final String? ip;
  final int? version;

  Connection({this.ip, this.version});

  factory Connection.fromJson(Map<String, dynamic> json) => Connection(
        ip: asString(json['ip']),
        version: asInt(json['version']),
      );

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'version': version,
      };
}

class Rtcp {
  final int? port;
  final String? ip;
  final int? version;

  Rtcp({this.port, this.ip, this.version});

  factory Rtcp.fromJson(Map<String, dynamic> json) => Rtcp(
        port: asInt(json['port']),
        ip: asString(json['ip']),
        version: asInt(json['version']),
      );

  Map<String, dynamic> toJson() => {
        'port': port,
        'ip': ip,
        'version': version,
      };
}

class Fingerprint {
  final String? type;
  final String? hash;

  Fingerprint({this.type, this.hash});

  factory Fingerprint.fromJson(Map<String, dynamic> json) => Fingerprint(
        type: asString(json['type']),
        hash: asString(json['hash']),
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'hash': hash,
      };
}

class Rtp {
  final int? payload;
  final String? codec;
  final int? rate;
  final int? encoding;

  Rtp({this.payload, this.codec, this.rate, this.encoding});

  factory Rtp.fromJson(Map<String, dynamic> json) => Rtp(
        payload: asInt(json['payload']),
        codec: asString(json['codec']),
        rate: asInt(json['rate']),
        encoding: asInt(json['encoding']),
      );

  Map<String, dynamic> toJson() => {
        'payload': payload,
        'codec': codec,
        'rate': rate,
        'encoding': encoding,
      };
}

class Fmtp {
  final int? payload;
  final String? config;

  Fmtp({this.payload, this.config});

  factory Fmtp.fromJson(Map<String, dynamic> json) => Fmtp(
        payload: asInt(json['payload']),
        config: asString(json['config']),
      );

  Map<String, dynamic> toJson() => {
        'payload': payload,
        'config': config,
      };
}

class Ext {
  final int? value;
  final String? uri;

  Ext({this.value, this.uri});

  factory Ext.fromJson(Map<String, dynamic> json) => Ext(
        value: asInt(json['value']),
        uri: asString(json['uri']),
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        'uri': uri,
      };
}

class RtcpFb {
  final int? payload;
  final String? type;
  final String? subtype;

  RtcpFb({this.payload, this.type, this.subtype});

  factory RtcpFb.fromJson(Map<String, dynamic> json) => RtcpFb(
        payload: asInt(json['payload']),
        type: asString(json['type']),
        subtype: asString(json['subtype']),
      );

  Map<String, dynamic> toJson() => {
        'payload': payload,
        'type': type,
        'subtype': subtype,
      };
}

class Ssrc {
  final int? id;
  final String? attribute;
  final String? value;

  Ssrc({this.id, this.attribute, this.value});

  factory Ssrc.fromJson(Map<String, dynamic> json) => Ssrc(
        id: asInt(json['id']),
        attribute: asString(json['attribute']),
        value: asString(json['value']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'attribute': attribute,
        'value': value,
      };
}

class SsrcGroup {
  final String? semantics;
  final String? ssrcs;

  SsrcGroup({this.semantics, this.ssrcs});

  factory SsrcGroup.fromJson(Map<String, dynamic> json) => SsrcGroup(
        semantics: asString(json['semantics']),
        ssrcs: asString(json['ssrcs']),
      );

  Map<String, dynamic> toJson() => {
        'semantics': semantics,
        'ssrcs': ssrcs,
      };
}

void main() {
  const chromeOfferSdp = {
    "type": "offer",
    "sdp":
        "v=0\r\no=- 4215775240449105457 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=group:BUNDLE 0 1\r\na=extmap-allow-mixed\r\na=msid-semantic: WMS 160d6347-77ea-40b8-aded-2b586daf50ea\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111 63 9 0 8 13 110 126\r\nc=IN IP4 0.0.0.0\r\na=rtcp:9 IN IP4 0.0.0.0\r\na=ice-ufrag:yxYb\r\na=ice-pwd:05iMxO9GujD2fUWXSoi0ByNd\r\na=ice-options:trickle\r\na=fingerprint:sha-256 B4:C4:F9:49:A6:5A:11:49:3E:66:BD:1F:B3:43:E3:54:A9:3E:1D:11:71:5B:E0:4D:5F:F4:BC:D2:19:3B:84:E5\r\na=setup:actpass\r\na=mid:0\r\na=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level\r\na=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\r\na=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\r\na=extmap:4 urn:ietf:params:rtp-hdrext:sdes:mid\r\na=sendrecv\r\na=msid:160d6347-77ea-40b8-aded-2b586daf50ea ebe4768c-cec1-4e71-bc80-099c1e6c1f10\r\na=rtcp-mux\r\na=rtpmap:111 opus/48000/2\r\na=rtcp-fb:111 transport-cc\r\na=fmtp:111 minptime=10;useinbandfec=1\r\na=rtpmap:63 red/48000/2\r\na=fmtp:63 111/111\r\na=rtpmap:9 G722/8000\r\na=rtpmap:0 PCMU/8000\r\na=rtpmap:8 PCMA/8000\r\na=rtpmap:13 CN/8000\r\na=rtpmap:110 telephone-event/48000\r\na=rtpmap:126 telephone-event/8000\r\na=ssrc:3485940486 cname:Dm9nmXDg4q8eNPqz\r\na=ssrc:3485940486 msid:160d6347-77ea-40b8-aded-2b586daf50ea ebe4768c-cec1-4e71-bc80-099c1e6c1f10\r\nm=video 9 UDP/TLS/RTP/SAVPF 96 97 102 103 104 105 106 107 108 109 127 125 39 40 98 99 100 101 112 113 114 115 116\r\nc=IN IP4 0.0.0.0\r\na=rtcp:9 IN IP4 0.0.0.0\r\na=ice-ufrag:yxYb\r\na=ice-pwd:05iMxO9GujD2fUWXSoi0ByNd\r\na=ice-options:trickle\r\na=fingerprint:sha-256 B4:C4:F9:49:A6:5A:11:49:3E:66:BD:1F:B3:43:E3:54:A9:3E:1D:11:71:5B:E0:4D:5F:F4:BC:D2:19:3B:84:E5\r\na=setup:actpass\r\na=mid:1\r\na=extmap:14 urn:ietf:params:rtp-hdrext:toffset\r\na=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\r\na=extmap:13 urn:3gpp:video-orientation\r\na=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\r\na=extmap:5 http://www.webrtc.org/experiments/rtp-hdrext/playout-delay\r\na=extmap:6 http://www.webrtc.org/experiments/rtp-hdrext/video-content-type\r\na=extmap:7 http://www.webrtc.org/experiments/rtp-hdrext/video-timing\r\na=extmap:8 http://www.webrtc.org/experiments/rtp-hdrext/color-space\r\na=extmap:4 urn:ietf:params:rtp-hdrext:sdes:mid\r\na=extmap:10 urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id\r\na=extmap:11 urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id\r\na=sendrecv\r\na=msid:160d6347-77ea-40b8-aded-2b586daf50ea f6d17d02-83e5-4023-9729-8fbe26711952\r\na=rtcp-mux\r\na=rtcp-rsize\r\na=rtpmap:96 VP8/90000\r\na=rtcp-fb:96 goog-remb\r\na=rtcp-fb:96 transport-cc\r\na=rtcp-fb:96 ccm fir\r\na=rtcp-fb:96 nack\r\na=rtcp-fb:96 nack pli\r\na=rtpmap:97 rtx/90000\r\na=fmtp:97 apt=96\r\na=rtpmap:102 H264/90000\r\na=rtcp-fb:102 goog-remb\r\na=rtcp-fb:102 transport-cc\r\na=rtcp-fb:102 ccm fir\r\na=rtcp-fb:102 nack\r\na=rtcp-fb:102 nack pli\r\na=fmtp:102 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42001f\r\na=rtpmap:103 rtx/90000\r\na=fmtp:103 apt=102\r\na=rtpmap:104 H264/90000\r\na=rtcp-fb:104 goog-remb\r\na=rtcp-fb:104 transport-cc\r\na=rtcp-fb:104 ccm fir\r\na=rtcp-fb:104 nack\r\na=rtcp-fb:104 nack pli\r\na=fmtp:104 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42001f\r\na=rtpmap:105 rtx/90000\r\na=fmtp:105 apt=104\r\na=rtpmap:106 H264/90000\r\na=rtcp-fb:106 goog-remb\r\na=rtcp-fb:106 transport-cc\r\na=rtcp-fb:106 ccm fir\r\na=rtcp-fb:106 nack\r\na=rtcp-fb:106 nack pli\r\na=fmtp:106 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f\r\na=rtpmap:107 rtx/90000\r\na=fmtp:107 apt=106\r\na=rtpmap:108 H264/90000\r\na=rtcp-fb:108 goog-remb\r\na=rtcp-fb:108 transport-cc\r\na=rtcp-fb:108 ccm fir\r\na=rtcp-fb:108 nack\r\na=rtcp-fb:108 nack pli\r\na=fmtp:108 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42e01f\r\na=rtpmap:109 rtx/90000\r\na=fmtp:109 apt=108\r\na=rtpmap:127 H264/90000\r\na=rtcp-fb:127 goog-remb\r\na=rtcp-fb:127 transport-cc\r\na=rtcp-fb:127 ccm fir\r\na=rtcp-fb:127 nack\r\na=rtcp-fb:127 nack pli\r\na=fmtp:127 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=4d001f\r\na=rtpmap:125 rtx/90000\r\na=fmtp:125 apt=127\r\na=rtpmap:39 H264/90000\r\na=rtcp-fb:39 goog-remb\r\na=rtcp-fb:39 transport-cc\r\na=rtcp-fb:39 ccm fir\r\na=rtcp-fb:39 nack\r\na=rtcp-fb:39 nack pli\r\na=fmtp:39 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=4d001f\r\na=rtpmap:40 rtx/90000\r\na=fmtp:40 apt=39\r\na=rtpmap:98 VP9/90000\r\na=rtcp-fb:98 goog-remb\r\na=rtcp-fb:98 transport-cc\r\na=rtcp-fb:98 ccm fir\r\na=rtcp-fb:98 nack\r\na=rtcp-fb:98 nack pli\r\na=fmtp:98 profile-id=0\r\na=rtpmap:99 rtx/90000\r\na=fmtp:99 apt=98\r\na=rtpmap:100 VP9/90000\r\na=rtcp-fb:100 goog-remb\r\na=rtcp-fb:100 transport-cc\r\na=rtcp-fb:100 ccm fir\r\na=rtcp-fb:100 nack\r\na=rtcp-fb:100 nack pli\r\na=fmtp:100 profile-id=2\r\na=rtpmap:101 rtx/90000\r\na=fmtp:101 apt=100\r\na=rtpmap:112 H264/90000\r\na=rtcp-fb:112 goog-remb\r\na=rtcp-fb:112 transport-cc\r\na=rtcp-fb:112 ccm fir\r\na=rtcp-fb:112 nack\r\na=rtcp-fb:112 nack pli\r\na=fmtp:112 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=64001f\r\na=rtpmap:113 rtx/90000\r\na=fmtp:113 apt=112\r\na=rtpmap:114 red/90000\r\na=rtpmap:115 rtx/90000\r\na=fmtp:115 apt=114\r\na=rtpmap:116 ulpfec/90000\r\na=ssrc-group:FID 4176833956 4153795228\r\na=ssrc:4176833956 cname:Dm9nmXDg4q8eNPqz\r\na=ssrc:4176833956 msid:160d6347-77ea-40b8-aded-2b586daf50ea f6d17d02-83e5-4023-9729-8fbe26711952\r\na=ssrc:4153795228 cname:Dm9nmXDg4q8eNPqz\r\na=ssrc:4153795228 msid:160d6347-77ea-40b8-aded-2b586daf50ea f6d17d02-83e5-4023-9729-8fbe26711952\r\n"
  };
  const chromeAnswerSdp = {
    "type": "answer",
    "sdp":
        "v=0\r\no=- 2875481597283948546 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=group:BUNDLE 0 1\r\na=extmap-allow-mixed\r\na=msid-semantic: WMS\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111 63 9 0 8 13 110 126\r\nc=IN IP4 0.0.0.0\r\na=rtcp:9 IN IP4 0.0.0.0\r\na=ice-ufrag:zbhr\r\na=ice-pwd:pzhairRs+AhjQigDx9V5mu9s\r\na=ice-options:trickle\r\na=fingerprint:sha-256 EA:70:3E:9F:C4:CC:85:E9:68:4D:C4:82:0F:15:63:79:0B:8C:BE:FB:B2:47:06:BA:D0:E7:3A:63:8C:EB:C6:1E\r\na=setup:active\r\na=mid:0\r\na=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level\r\na=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\r\na=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\r\na=extmap:4 urn:ietf:params:rtp-hdrext:sdes:mid\r\na=recvonly\r\na=rtcp-mux\r\na=rtpmap:111 opus/48000/2\r\na=rtcp-fb:111 transport-cc\r\na=fmtp:111 minptime=10;useinbandfec=1\r\na=rtpmap:63 red/48000/2\r\na=fmtp:63 111/111\r\na=rtpmap:9 G722/8000\r\na=rtpmap:0 PCMU/8000\r\na=rtpmap:8 PCMA/8000\r\na=rtpmap:13 CN/8000\r\na=rtpmap:110 telephone-event/48000\r\na=rtpmap:126 telephone-event/8000\r\nm=video 9 UDP/TLS/RTP/SAVPF 96 97 102 103 104 105 106 107 108 109 127 125 39 40 98 99 100 101 112 113 114 115 116\r\nc=IN IP4 0.0.0.0\r\na=rtcp:9 IN IP4 0.0.0.0\r\na=ice-ufrag:zbhr\r\na=ice-pwd:pzhairRs+AhjQigDx9V5mu9s\r\na=ice-options:trickle\r\na=fingerprint:sha-256 EA:70:3E:9F:C4:CC:85:E9:68:4D:C4:82:0F:15:63:79:0B:8C:BE:FB:B2:47:06:BA:D0:E7:3A:63:8C:EB:C6:1E\r\na=setup:active\r\na=mid:1\r\na=extmap:14 urn:ietf:params:rtp-hdrext:toffset\r\na=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\r\na=extmap:13 urn:3gpp:video-orientation\r\na=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\r\na=extmap:5 http://www.webrtc.org/experiments/rtp-hdrext/playout-delay\r\na=extmap:6 http://www.webrtc.org/experiments/rtp-hdrext/video-content-type\r\na=extmap:7 http://www.webrtc.org/experiments/rtp-hdrext/video-timing\r\na=extmap:8 http://www.webrtc.org/experiments/rtp-hdrext/color-space\r\na=extmap:4 urn:ietf:params:rtp-hdrext:sdes:mid\r\na=extmap:10 urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id\r\na=extmap:11 urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id\r\na=recvonly\r\na=rtcp-mux\r\na=rtcp-rsize\r\na=rtpmap:96 VP8/90000\r\na=rtcp-fb:96 goog-remb\r\na=rtcp-fb:96 transport-cc\r\na=rtcp-fb:96 ccm fir\r\na=rtcp-fb:96 nack\r\na=rtcp-fb:96 nack pli\r\na=rtpmap:97 rtx/90000\r\na=fmtp:97 apt=96\r\na=rtpmap:102 H264/90000\r\na=rtcp-fb:102 goog-remb\r\na=rtcp-fb:102 transport-cc\r\na=rtcp-fb:102 ccm fir\r\na=rtcp-fb:102 nack\r\na=rtcp-fb:102 nack pli\r\na=fmtp:102 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42001f\r\na=rtpmap:103 rtx/90000\r\na=fmtp:103 apt=102\r\na=rtpmap:104 H264/90000\r\na=rtcp-fb:104 goog-remb\r\na=rtcp-fb:104 transport-cc\r\na=rtcp-fb:104 ccm fir\r\na=rtcp-fb:104 nack\r\na=rtcp-fb:104 nack pli\r\na=fmtp:104 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42001f\r\na=rtpmap:105 rtx/90000\r\na=fmtp:105 apt=104\r\na=rtpmap:106 H264/90000\r\na=rtcp-fb:106 goog-remb\r\na=rtcp-fb:106 transport-cc\r\na=rtcp-fb:106 ccm fir\r\na=rtcp-fb:106 nack\r\na=rtcp-fb:106 nack pli\r\na=fmtp:106 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f\r\na=rtpmap:107 rtx/90000\r\na=fmtp:107 apt=106\r\na=rtpmap:108 H264/90000\r\na=rtcp-fb:108 goog-remb\r\na=rtcp-fb:108 transport-cc\r\na=rtcp-fb:108 ccm fir\r\na=rtcp-fb:108 nack\r\na=rtcp-fb:108 nack pli\r\na=fmtp:108 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42e01f\r\na=rtpmap:109 rtx/90000\r\na=fmtp:109 apt=108\r\na=rtpmap:127 H264/90000\r\na=rtcp-fb:127 goog-remb\r\na=rtcp-fb:127 transport-cc\r\na=rtcp-fb:127 ccm fir\r\na=rtcp-fb:127 nack\r\na=rtcp-fb:127 nack pli\r\na=fmtp:127 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=4d001f\r\na=rtpmap:125 rtx/90000\r\na=fmtp:125 apt=127\r\na=rtpmap:39 H264/90000\r\na=rtcp-fb:39 goog-remb\r\na=rtcp-fb:39 transport-cc\r\na=rtcp-fb:39 ccm fir\r\na=rtcp-fb:39 nack\r\na=rtcp-fb:39 nack pli\r\na=fmtp:39 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=4d001f\r\na=rtpmap:40 rtx/90000\r\na=fmtp:40 apt=39\r\na=rtpmap:98 VP9/90000\r\na=rtcp-fb:98 goog-remb\r\na=rtcp-fb:98 transport-cc\r\na=rtcp-fb:98 ccm fir\r\na=rtcp-fb:98 nack\r\na=rtcp-fb:98 nack pli\r\na=fmtp:98 profile-id=0\r\na=rtpmap:99 rtx/90000\r\na=fmtp:99 apt=98\r\na=rtpmap:100 VP9/90000\r\na=rtcp-fb:100 goog-remb\r\na=rtcp-fb:100 transport-cc\r\na=rtcp-fb:100 ccm fir\r\na=rtcp-fb:100 nack\r\na=rtcp-fb:100 nack pli\r\na=fmtp:100 profile-id=2\r\na=rtpmap:101 rtx/90000\r\na=fmtp:101 apt=100\r\na=rtpmap:112 H264/90000\r\na=rtcp-fb:112 goog-remb\r\na=rtcp-fb:112 transport-cc\r\na=rtcp-fb:112 ccm fir\r\na=rtcp-fb:112 nack\r\na=rtcp-fb:112 nack pli\r\na=fmtp:112 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=64001f\r\na=rtpmap:113 rtx/90000\r\na=fmtp:113 apt=112\r\na=rtpmap:114 red/90000\r\na=rtpmap:115 rtx/90000\r\na=fmtp:115 apt=114\r\na=rtpmap:116 ulpfec/90000\r\n"
  };

  const simpleTest = [
    {"offer": chromeOfferSdp, "answer": chromeAnswerSdp}
  ];

  final sdpOffer = parse(chromeAnswerSdp['sdp'] as String);
  print("Parsed: $sdpOffer");

  final sdp = SdpObject.fromJson(sdpOffer);
  // print("Reconstructed: ${write(sdp.toJson(), null)}");
}
