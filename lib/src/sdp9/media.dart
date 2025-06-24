import 'candidate.dart';

class Rtp {
  int payload;
  String codec;
  int rate;
  int? encoding;

  Rtp(
      {required this.payload,
      required this.codec,
      required this.rate,
      this.encoding});

  factory Rtp.fromJson(dynamic rtpJson) {
    // print("Encoding: ${rtpJson['encoding']}");
    return Rtp(
        payload: rtpJson['payload'],
        codec: rtpJson['codec'],
        rate: rtpJson['rate'],
        encoding: rtpJson['encoding']);
  }

  //     dynamic toJson() {
  //   return {
  //     'payload': 110,
  //     'codec': 'telephone-event',
  //     'rate': 48000,
  //     'encoding': null
  //   };
  // }
  dynamic toJson() {
    return {
      'payload': payload,
      'codec': codec,
      'rate': rate,
      'encoding': encoding
    };
  }
}

class Fmtp {
  int payload;
  String config;

  Fmtp({
    required this.payload,
    required this.config,
  });

  factory Fmtp.fromJson(dynamic rtpJson) {
    return Fmtp(
      payload: rtpJson['payload'],
      config: rtpJson['config'],
    );
  }

  //     dynamic toJson() {
  //   return {
  //     'payload': 110,
  //     'codec': 'telephone-event',
  //     'rate': 48000,
  //     'encoding': null
  //   };
  // }
  dynamic toJson() {
    return {'payload': payload, 'config': config};
  }
}

class Connection {
  int version;
  String ip;
  // {'version': 4, 'ip': '102.67.160.2'};

  Connection({required this.version, required this.ip});

  factory Connection.fromJson(dynamic connectionJson) {
    return Connection(
      version: connectionJson['version'],
      ip: connectionJson['ip'],
    );
  }
  dynamic toJson() {
    return {'version': version, 'ip': ip};
  }

  @override
  String toString() {
    // TODO: implement toString
    return toJson().toString();
  }
}

class Rtcp {
  int port;
  String netType;
  int ipVer;
  String address;

  Rtcp(
      {required this.port,
      required this.netType,
      required this.ipVer,
      required this.address});

  // 'rtcp': {'port': 9, 'netType': 'IN', 'ipVer': 4, 'address': '0.0.0.0'},

  factory Rtcp.fromJson(dynamic rtcpJson) {
    return Rtcp(
        port: rtcpJson['port'],
        netType: rtcpJson['netType'],
        ipVer: rtcpJson['ipVer'],
        address: rtcpJson['address']);
  }
  dynamic toJson() {
    return {
      'port': port,
      'netType': netType,
      'ipVer': ipVer,
      'address': address
    };
  }
}

class Fingerprint {
  String type;
  String hash;

  Fingerprint({required this.type, required this.hash});

  factory Fingerprint.fromJson(dynamic fpJson) {
    return Fingerprint(type: fpJson['type'], hash: fpJson['hash']);
  }
  dynamic toJson() {
    return {'type': type, 'hash': hash};
  }
}

class Ext {
  int value;
  String? direction;
  String uri;
  String? config;

  Ext({required this.value, this.direction, required this.uri, this.config});

  factory Ext.fromJson(dynamic extJson) {
    return Ext(
        value: extJson['value'],
        uri: extJson['uri'],
        direction: extJson['direction'],
        config: extJson['config']);
  }
  dynamic toJson() {
    return {'value': 1, 'direction': direction, 'uri': uri, 'config': config};
  }
}

class RtcpFb {
  int payload;
  String? type;
  String? subtype;

  RtcpFb({
    required this.payload,
    required this.type,
    required this.subtype,
  });

  // {'payload': 111, 'type': 'transport-cc', 'subtype': null}

  factory RtcpFb.fromJson(dynamic rtpJson) {
    print("RtpFB: $rtpJson");
    return RtcpFb(
        payload: rtpJson['payload'],
        type: rtpJson['type'],
        subtype: rtpJson['subtype']);
  }

  //     dynamic toJson() {
  //   return {
  //     'payload': 110,
  //     'codec': 'telephone-event',
  //     'rate': 48000,
  //     'encoding': null
  //   };
  // }
  dynamic toJson() {
    return {'payload': payload, 'type': subtype, 'subtype': subtype};
  }
}

class SSRCS {
  int id;
  String attribute;
  String value;

  SSRCS({required this.id, required this.attribute, required this.value});
  // {'id': 1227153705, 'attribute': 'cname', 'value': 'tcfYxii359Px+p5/'}

  factory SSRCS.fromJson(dynamic ssrcsJson) {
    return SSRCS(
        id: ssrcsJson['id'],
        attribute: ssrcsJson['attribute'],
        value: ssrcsJson['value']);
  }

  dynamic toJson() {
    return {'id': id, 'attribute': attribute, 'value': value};
  }
}

class Media {
  List<Rtp> rtp;
  List<Fmtp> fmtp;
  List<Candidate> candidates;
  String type;
  int port;
  List<String> protocol;
  List<int> payloads;
  Connection connection;
  Rtcp rtcp;
  String iceUFrag;
  String icePwd;
  String iceOptions;
  Fingerprint fingerprint;
  String setup;
  int mid;
  List<Ext> exts;
  String direction;
  String msid;
  String rtcpMux;
  String rtcpRsize;
  List<RtcpFb> rtcpFb;
  List<SSRCS> ssrcs;

  Media(
      {required this.rtp,
      required this.fmtp,
      required this.candidates,
      required this.type,
      required this.port,
      required this.protocol,
      required this.payloads,
      required this.connection,
      required this.rtcp,
      required this.iceUFrag,
      required this.icePwd,
      required this.iceOptions,
      required this.fingerprint,
      required this.setup,
      required this.mid,
      required this.exts,
      required this.direction,
      required this.msid,
      required this.rtcpMux,
      required this.rtcpRsize,
      required this.rtcpFb,
      required this.ssrcs});

  factory Media.fromJson(dynamic mediaJson) {
    List<String> payloads = ((mediaJson['payloads']) as String).split(" ");

    return Media(
        rtp: List.generate(mediaJson['rtp'].length,
            (index) => Rtp.fromJson(mediaJson['rtp'][index])),
        fmtp: List.generate(mediaJson['fmtp'].length,
            (index) => Fmtp.fromJson(mediaJson['fmtp'][index])),
        candidates: List.generate(mediaJson['candidates'].length,
            (index) => Candidate.fromJson(mediaJson['candidates'][index])),
        type: mediaJson['type'],
        port: mediaJson['port'],
        protocol: (mediaJson['protocol'] as String).split("/"),
        payloads: List.generate(
            payloads.length, (index) => int.parse(payloads[index])),
        connection: Connection.fromJson(mediaJson['connection']),
        rtcp: Rtcp.fromJson(mediaJson['rtcp']),
        iceUFrag: mediaJson['iceUfrag'],
        icePwd: mediaJson['icePwd'],
        iceOptions: mediaJson['iceOptions'],
        fingerprint: Fingerprint.fromJson(mediaJson['fingerprint']),
        setup: mediaJson['setup'],
        mid: mediaJson['mid'],
        exts: List.generate(mediaJson['ext'].length,
            (index) => Ext.fromJson(mediaJson['ext'][index])),
        direction: mediaJson['direction'],
        msid: mediaJson['msid'],
        rtcpMux: mediaJson['rtcpMux'],
        rtcpRsize: mediaJson['rtcpRsize'],
        rtcpFb: List.generate(mediaJson['rtcpFb'].length,
            (index) => RtcpFb.fromJson(mediaJson['rtcpFb'][index])),
        ssrcs: List.generate(mediaJson['ssrcs'].length,
            (index) => SSRCS.fromJson(mediaJson['ssrcs'][index])));
  }

  dynamic toJson() {
    return {
      'rtp': rtp.map((rtpEntry) => rtpEntry.toJson()).toList(),
      'fmtp': fmtp.map((fmtpEntry) => fmtpEntry.toJson()).toList(),
      'type': type,
      'port': port,
      'protocol': protocol.join("/"),
      'payloads': payloads.join(" "),
      'connection': connection.toJson(),
      'rtcp': rtcp.toJson(),
      'candidates': candidates.map((candidate) => candidate.toJson()).toList(),
      'iceUfrag': iceUFrag,
      'icePwd': icePwd,
      'iceOptions': iceOptions,
      'fingerprint': fingerprint.toJson(),
      'setup': setup,
      'mid': mid,
      'ext': exts.map((ext) => ext.toJson()).toList(),
      'direction': direction,
      'msid': msid,
      'rtcpMux': rtcpMux,
      'rtcpRsize': rtcpRsize,
      'rtcpFb': rtcpFb.map((rtcpfb) => rtcpfb.toJson()).toList(),
      'ssrcs': ssrcs.map((ssrc) => ssrc.toJson()).toList()
    };
  }

  // dynamic toJson() {
  //   return {
  //     'rtp': [
  //       {'payload': 111, 'codec': 'opus', 'rate': 48000, 'encoding': 2},
  //     ],
  //     'fmtp': [
  //       {'payload': 111, 'config': 'minptime=10;useinbandfec=1'},
  //     ],
  //     'type': 'audio',
  //     'port': 51584,
  //     'protocol': 'UDP/TLS/RTP/SAVPF',
  //     'payloads': '111 63 9 0 8 13 110 126',
  //     'connection': {'version': 4, 'ip': '102.67.160.2'},
  //     'rtcp': {'port': 9, 'netType': 'IN', 'ipVer': 4, 'address': '0.0.0.0'},
  //     'candidates': [
  //       {
  //         'foundation': '4057065925',
  //         'component': 1,
  //         'transport': 'udp',
  //         'priority': 2122260223,
  //         'ip': '172.22.16.1',
  //         'port': 51582,
  //         'type': 'host',
  //         'raddr': null,
  //         'rport': null,
  //         'tcptype': null,
  //         'generation': 0,
  //         'network-id': 1,
  //         'network-cost': null
  //       },
  //     ],
  //     'iceUfrag': 'OaAE',
  //     'icePwd': 'x/xqQ5Oiwcn41g5m7kUJ3O2+',
  //     'iceOptions': 'trickle',
  //     'fingerprint': {
  //       'type': 'sha-256',
  //       'hash':
  //           '4F:AC:D4:CF:2C:76:3A:A1:B8:1B:F3:83:31:2F:C5:BC:30:21:E0:A4:44:DE:2D:81:B9:BB:99:BC:91:7F:8A:39'
  //     },
  //     'setup': 'actpass',
  //     'mid': '0',
  //     'ext': [
  //       {
  //         'value': 1,
  //         'direction': null,
  //         'uri': 'urn:ietf:params:rtp-hdrext:ssrc-audio-level',
  //         'config': null
  //       },
  //     ],
  //     'direction': 'sendrecv',
  //     'msid':
  //         '84f453ca-0dbd-4d92-8eec-6b671c88f990 660e6102-24a7-43a5-9e01-a733f091341d',
  //     'rtcpMux': 'rtcp-mux',
  //     'rtcpRsize': 'rtcp-rsize',
  //     'rtcpFb': [
  //       {'payload': 111, 'type': 'transport-cc', 'subtype': null}
  //     ],
  //     'ssrcs': [
  //       {'id': 1227153705, 'attribute': 'cname', 'value': 'tcfYxii359Px+p5/'},
  //       {
  //         'id': 1227153705,
  //         'attribute': 'msid',
  //         'value':
  //             '84f453ca-0dbd-4d92-8eec-6b671c88f990 660e6102-24a7-43a5-9e01-a733f091341d'
  //       }
  //     ]
  //   };
  // }
}

void main() {
  final media = Media.fromJson(mediaJson);
  print("Media: ${media.toJson()}");
}

final mediaJson = {
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
    {'payload': 126, 'codec': 'telephone-event', 'rate': 8000, 'encoding': null}
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
};
