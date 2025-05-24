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

SdpObject createSdpOffer() {
  return SdpObject(
    version: 0,
    origin: Origin(
      username: '-',
      sessionId: 4215775240449105457,
      sessionVersion: 2,
      netType: 'IN',
      ipVer: 4,
      address: '127.0.0.1',
    ),
    name: '-',
    timing: Timing(start: 0, stop: 0),
    groups: [
      Group(type: 'BUNDLE', mids: '0 1'),
    ],
    extmapAllowMixed: [
      {'extmap-allow-mixed': 'extmap-allow-mixed'},
    ],
    msidSemantic: MsidSemantic(
      semantic: 'WMS',
      token: '160d6347-77ea-40b8-aded-2b586daf50ea',
    ),
    media: [
      Media(
        rtp: [
          Rtp(payload: 111, codec: 'opus', rate: 48000, encoding: 2),
          Rtp(payload: 63, codec: 'red', rate: 48000, encoding: 2),
          Rtp(payload: 9, codec: 'G722', rate: 8000, encoding: null),
          Rtp(payload: 0, codec: 'PCMU', rate: 8000, encoding: null),
          Rtp(payload: 8, codec: 'PCMA', rate: 8000, encoding: null),
          Rtp(payload: 13, codec: 'CN', rate: 8000, encoding: null),
          Rtp(
              payload: 110,
              codec: 'telephone-event',
              rate: 48000,
              encoding: null),
          Rtp(
              payload: 126,
              codec: 'telephone-event',
              rate: 8000,
              encoding: null),
        ],
        fmtp: [
          Fmtp(payload: 111, config: 'minptime=10;useinbandfec=1'),
          Fmtp(payload: 63, config: '111/111'),
        ],
        type: 'audio',
        port: 9,
        protocol: 'UDP/TLS/RTP/SAVPF',
        payloads: '111 63 9 0 8 13 110 126',
        connection: Connection(version: 4, ip: '0.0.0.0'),
        rtcp: Rtcp(port: 9, ip: '0.0.0.0', version: 4),
        iceUfrag: 'yxYb',
        icePwd: '05iMxO9GujD2fUWXSoi0ByNd',
        iceOptions: 'trickle',
        fingerprint: Fingerprint(
          type: 'sha-256',
          hash:
              'B4:C4:F9:49:A6:5A:11:49:3E:66:BD:1F:B3:43:E3:54:A9:3E:1D:11:71:5B:E0:4D:5F:F4:BC:D2:19:3B:84:E5',
        ),
        setup: 'actpass',
        mid: '0',
        ext: [
          Ext(value: 1, uri: 'urn:ietf:params:rtp-hdrext:ssrc-audio-level'),
          Ext(
              value: 2,
              uri:
                  'http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time'),
          Ext(
              value: 3,
              uri:
                  'http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01'),
          Ext(value: 4, uri: 'urn:ietf:params:rtp-hdrext:sdes:mid'),
        ],
        direction: 'sendrecv',
        msid:
            '160d6347-77ea-40b8-aded-2b586daf50ea ebe4768c-cec1-4e71-bc80-099c1e6c1f10',
        rtcpMux: 'rtcp-mux',
        rtcpFb: [
          RtcpFb(payload: 111, type: 'transport-cc'),
        ],
        ssrcs: [
          Ssrc(id: 3485940486, attribute: 'cname', value: 'Dm9nmXDg4q8eNPqz'),
          Ssrc(
              id: 3485940486,
              attribute: 'msid',
              value:
                  '160d6347-77ea-40b8-aded-2b586daf50ea ebe4768c-cec1-4e71-bc80-099c1e6c1f10'),
        ],
      ),
      Media(
        rtp: [
          Rtp(payload: 96, codec: 'VP8', rate: 90000, encoding: null),
          Rtp(payload: 97, codec: 'rtx', rate: 90000, encoding: null),
          Rtp(payload: 102, codec: 'H264', rate: 90000, encoding: null),
          Rtp(payload: 103, codec: 'rtx', rate: 90000, encoding: null),
          Rtp(payload: 104, codec: 'H264', rate: 90000, encoding: null),
          Rtp(payload: 105, codec: 'rtx', rate: 90000, encoding: null),
          Rtp(payload: 106, codec: 'H264', rate: 90000, encoding: null),
          Rtp(payload: 107, codec: 'rtx', rate: 90000, encoding: null),
          Rtp(payload: 108, codec: 'H264', rate: 90000, encoding: null),
          Rtp(payload: 109, codec: 'rtx', rate: 90000, encoding: null),
          Rtp(payload: 127, codec: 'H264', rate: 90000, encoding: null),
          Rtp(payload: 125, codec: 'rtx', rate: 90000, encoding: null),
          Rtp(payload: 39, codec: 'H264', rate: 90000, encoding: null),
          Rtp(payload: 40, codec: 'rtx', rate: 90000, encoding: null),
          Rtp(payload: 98, codec: 'VP9', rate: 90000, encoding: null),
          Rtp(payload: 99, codec: 'rtx', rate: 90000, encoding: null),
          Rtp(payload: 100, codec: 'VP9', rate: 90000, encoding: null),
          Rtp(payload: 101, codec: 'rtx', rate: 90000, encoding: null),
          Rtp(payload: 112, codec: 'H264', rate: 90000, encoding: null),
          Rtp(payload: 113, codec: 'rtx', rate: 90000, encoding: null),
          Rtp(payload: 114, codec: 'red', rate: 90000, encoding: null),
          Rtp(payload: 115, codec: 'rtx', rate: 90000, encoding: null),
          Rtp(payload: 116, codec: 'ulpfec', rate: 90000, encoding: null),
        ],
        fmtp: [
          Fmtp(payload: 97, config: 'apt=96'),
          Fmtp(
              payload: 102,
              config:
                  'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42001f'),
          Fmtp(payload: 103, config: 'apt=102'),
          Fmtp(
              payload: 104,
              config:
                  'level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42001f'),
          Fmtp(payload: 105, config: 'apt=104'),
          Fmtp(
              payload: 106,
              config:
                  'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f'),
          Fmtp(payload: 107, config: 'apt=106'),
          Fmtp(
              payload: 108,
              config:
                  'level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42e01f'),
          Fmtp(payload: 109, config: 'apt=108'),
          Fmtp(
              payload: 127,
              config:
                  'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=4d001f'),
          Fmtp(payload: 125, config: 'apt=127'),
          Fmtp(
              payload: 39,
              config:
                  'level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=4d001f'),
          Fmtp(payload: 40, config: 'apt=39'),
          Fmtp(payload: 98, config: 'profile-id=0'),
          Fmtp(payload: 99, config: 'apt=98'),
          Fmtp(payload: 100, config: 'profile-id=2'),
          Fmtp(payload: 101, config: 'apt=100'),
          Fmtp(
              payload: 112,
              config:
                  'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=64001f'),
          Fmtp(payload: 113, config: 'apt=112'),
          Fmtp(payload: 115, config: 'apt=114'),
        ],
        type: 'video',
        port: 9,
        protocol: 'UDP/TLS/RTP/SAVPF',
        payloads:
            '96 97 102 103 104 105 106 107 108 109 127 125 39 40 98 99 100 101 112 113 114 115 116',
        connection: Connection(version: 4, ip: '0.0.0.0'),
        rtcp: Rtcp(port: 9, ip: '0.0.0.0', version: 4),
        iceUfrag: 'yxYb',
        icePwd: '05iMxO9GujD2fUWXSoi0ByNd',
        iceOptions: 'trickle',
        fingerprint: Fingerprint(
          type: 'sha-256',
          hash:
              'B4:C4:F9:49:A6:5A:11:49:3E:66:BD:1F:B3:43:E3:54:A9:3E:1D:11:71:5B:E0:4D:5F:F4:BC:D2:19:3B:84:E5',
        ),
        setup: 'actpass',
        mid: '1',
        ext: [
          Ext(value: 14, uri: 'urn:ietf:params:rtp-hdrext:toffset'),
          Ext(
              value: 2,
              uri:
                  'http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time'),
          Ext(value: 13, uri: 'urn:3gpp:video-orientation'),
          Ext(
              value: 3,
              uri:
                  'http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01'),
          Ext(
              value: 5,
              uri:
                  'http://www.webrtc.org/experiments/rtp-hdrext/playout-delay'),
          Ext(
              value: 6,
              uri:
                  'http://www.webrtc.org/experiments/rtp-hdrext/video-content-type'),
          Ext(
              value: 7,
              uri: 'http://www.webrtc.org/experiments/rtp-hdrext/video-timing'),
          Ext(
              value: 8,
              uri: 'http://www.webrtc.org/experiments/rtp-hdrext/color-space'),
          Ext(value: 4, uri: 'urn:ietf:params:rtp-hdrext:sdes:mid'),
          Ext(value: 10, uri: 'urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id'),
          Ext(
              value: 11,
              uri: 'urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id'),
        ],
        direction: 'sendrecv',
        msid:
            '160d6347-77ea-40b8-aded-2b586daf50ea f6d17d02-83e5-4023-9729-8fbe26711952',
        rtcpMux: 'rtcp-mux',
        rtcpRsize: 'rtcp-rsize',
        rtcpFb: [
          RtcpFb(payload: 96, type: 'goog-remb'),
          RtcpFb(payload: 96, type: 'transport-cc'),
          RtcpFb(payload: 96, type: 'ccm', subtype: 'fir'),
          RtcpFb(payload: 96, type: 'nack'),
          RtcpFb(payload: 96, type: 'nack', subtype: 'pli'),
          RtcpFb(payload: 102, type: 'goog-remb'),
          RtcpFb(payload: 102, type: 'transport-cc'),
          RtcpFb(payload: 102, type: 'ccm', subtype: 'fir'),
          RtcpFb(payload: 102, type: 'nack'),
          RtcpFb(payload: 102, type: 'nack', subtype: 'pli'),
          RtcpFb(payload: 104, type: 'goog-remb'),
          RtcpFb(payload: 104, type: 'transport-cc'),
          RtcpFb(payload: 104, type: 'ccm', subtype: 'fir'),
          RtcpFb(payload: 104, type: 'nack'),
          RtcpFb(payload: 104, type: 'nack', subtype: 'pli'),
          RtcpFb(payload: 106, type: 'goog-remb'),
          RtcpFb(payload: 106, type: 'transport-cc'),
          RtcpFb(payload: 106, type: 'ccm', subtype: 'fir'),
          RtcpFb(payload: 106, type: 'nack'),
          RtcpFb(payload: 106, type: 'nack', subtype: 'pli'),
          RtcpFb(payload: 108, type: 'goog-remb'),
          RtcpFb(payload: 108, type: 'transport-cc'),
          RtcpFb(payload: 108, type: 'ccm', subtype: 'fir'),
          RtcpFb(payload: 108, type: 'nack'),
          RtcpFb(payload: 108, type: 'nack', subtype: 'pli'),
          RtcpFb(payload: 127, type: 'goog-remb'),
          RtcpFb(payload: 127, type: 'transport-cc'),
          RtcpFb(payload: 127, type: 'ccm', subtype: 'fir'),
          RtcpFb(payload: 127, type: 'nack'),
          RtcpFb(payload: 127, type: 'nack', subtype: 'pli'),
          RtcpFb(payload: 39, type: 'goog-remb'),
          RtcpFb(payload: 39, type: 'transport-cc'),
          RtcpFb(payload: 39, type: 'ccm', subtype: 'fir'),
          RtcpFb(payload: 39, type: 'nack'),
          RtcpFb(payload: 39, type: 'nack', subtype: 'pli'),
          RtcpFb(payload: 98, type: 'goog-remb'),
          RtcpFb(payload: 98, type: 'transport-cc'),
          RtcpFb(payload: 98, type: 'ccm', subtype: 'fir'),
          RtcpFb(payload: 98, type: 'nack'),
          RtcpFb(payload: 98, type: 'nack', subtype: 'pli'),
          RtcpFb(payload: 100, type: 'goog-remb'),
          RtcpFb(payload: 100, type: 'transport-cc'),
          RtcpFb(payload: 100, type: 'ccm', subtype: 'fir'),
          RtcpFb(payload: 100, type: 'nack'),
          RtcpFb(payload: 100, type: 'nack', subtype: 'pli'),
          RtcpFb(payload: 112, type: 'goog-remb'),
          RtcpFb(payload: 112, type: 'transport-cc'),
          RtcpFb(payload: 112, type: 'ccm', subtype: 'fir'),
          RtcpFb(payload: 112, type: 'nack'),
          RtcpFb(payload: 112, type: 'nack', subtype: 'pli'),
        ],
        ssrcGroups: [
          SsrcGroup(semantics: 'FID', ssrcs: '4176833956 4153795228'),
        ],
        ssrcs: [
          Ssrc(id: 4176833956, attribute: 'cname', value: 'Dm9nmXDg4q8eNPqz'),
          Ssrc(
              id: 4176833956,
              attribute: 'msid',
              value:
                  '160d6347-77ea-40b8-aded-2b586daf50ea f6d17d02-83e5-4023-9729-8fbe26711952'),
          Ssrc(id: 4153795228, attribute: 'cname', value: 'Dm9nmXDg4q8eNPqz'),
          Ssrc(
              id: 4153795228,
              attribute: 'msid',
              value:
                  '160d6347-77ea-40b8-aded-2b586daf50ea f6d17d02-83e5-4023-9729-8fbe26711952'),
        ],
      ),
    ],
  );
}

void main() {
  final offer = createSdpOffer();
  print(write(offer.toJson(), null));
}
