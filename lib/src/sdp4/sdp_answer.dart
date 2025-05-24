import 'package:sdp_transform/sdp_transform.dart';

// Helper functions for safe type conversion
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
  final String? netType;
  final int? ipVer;
  final String? address;

  Rtcp({this.port, this.netType, this.ipVer, this.address});

  factory Rtcp.fromJson(Map<String, dynamic> json) => Rtcp(
        port: asInt(json['port']),
        netType: asString(json['netType']),
        ipVer: asInt(json['ipVer']),
        address: asString(json['address']),
      );

  Map<String, dynamic> toJson() => {
        'port': port,
        'netType': netType,
        'ipVer': ipVer,
        'address': address,
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

SdpObject createSdpAnswer(SdpObject offer) {
  // 1. Basic structure from the offer
  final answer = SdpObject(
    version: 0,
    origin: Origin(
      username: '-', // Typically set by the answering side
      sessionId: offer.origin.sessionId, // Reuse the session ID from the offer
      sessionVersion: 2, // Increment as needed
      netType: offer.origin.netType,
      ipVer: offer.origin.ipVer,
      address: '127.0.0.1', // Set to the actual address of the answerer
    ),
    name: '-',
    timing: Timing(start: 0, stop: 0),
    groups: offer.groups, // Copy groups from the offer
    extmapAllowMixed: offer.extmapAllowMixed,
    msidSemantic: offer.msidSemantic,
    media: [], // Initialize empty media list; will populate below
  );

  // 2. Process each media description in the offer
  for (final offerMedia in offer.media) {
    //  Create a corresponding media object for the answer
    final answerMedia = Media(
      type: offerMedia.type,
      port: 9, //  Set the appropriate port
      protocol: offerMedia.protocol,
      payloads: offerMedia.payloads,
      connection: Connection(version: 4, ip: '0.0.0.0'),
      rtcp: Rtcp(
        port: 9,
        netType: 'IN',
        ipVer: 4,
        address:
            '0.0.0.0', // The address for RTCP.  This may need to be the actual address.
      ),
      iceUfrag: 'zbhr', //  Set the actual ICE username fragment
      icePwd: 'pzhairRs+AhjQigDx9V5mu9s', // Set the actual ICE password
      iceOptions: 'trickle',
      fingerprint: Fingerprint(
        type: 'sha-256',
        hash:
            'EA:70:3E:9F:C4:CC:85:E9:68:4D:C4:82:0F:15:63:79:0B:8C:BE:FB:B2:47:06:BA:D0:E7:3A:63:8C:EB:C6:1E', // Set the actual fingerprint
      ),
      setup: 'active', //  Set the correct setup
      mid: offerMedia.mid,
      direction: 'recvonly', //  Set the direction
      rtcpMux: offerMedia.rtcpMux,
      rtcpRsize: offerMedia.rtcpRsize,
    );

    // Copy RTP and FMTP from the offer
    answerMedia.rtp = offerMedia.rtp;
    answerMedia.fmtp = offerMedia.fmtp;
    answerMedia.ext = offerMedia.ext;
    answerMedia.rtcpFb = offerMedia.rtcpFb;
    answerMedia.ssrcs = offerMedia.ssrcs;
    answerMedia.ssrcGroups = offerMedia.ssrcGroups;

    answer.media.add(answerMedia);
  }
  return answer;
}

void main() {
  // Example usage (replace with actual offer)
  final offer = SdpObject(
    version: 0,
    origin: Origin(
      username: 'user1',
      sessionId: 1234567890,
      sessionVersion: 1,
      netType: 'IN',
      ipVer: 4,
      address: '192.0.2.1',
    ),
    name: 'My Session',
    timing: Timing(start: 0, stop: 0),
    groups: [Group(type: 'BUNDLE', mids: '0 1')],
    extmapAllowMixed: [],
    msidSemantic: MsidSemantic(semantic: 'WMS', token: '*'),
    media: [
      Media(
        type: 'audio',
        port: 5000,
        protocol: 'RTP/AVP',
        payloads: '0 8',
        connection: Connection(version: 4, ip: '192.0.2.1'),
        rtp: [
          Rtp(payload: 0, codec: 'PCMU', rate: 8000, encoding: null),
          Rtp(payload: 8, codec: 'PCMA', rate: 8000, encoding: null),
        ],
        direction: 'sendrecv',
        mid: '0',
      ),
      Media(
        type: 'video',
        port: 5002,
        protocol: 'RTP/AVP',
        payloads: '96',
        connection: Connection(version: 4, ip: '192.0.2.1'),
        rtp: [Rtp(payload: 96, codec: 'VP8', rate: 90000, encoding: null)],
        direction: 'sendrecv',
        mid: '1',
      ),
    ],
  );

  final answer = createSdpAnswer(offer);
  print(write(answer.toJson(), null));
}
