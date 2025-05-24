import 'package:sdp_transform/sdp_transform.dart';

enum MediaType { video, audio }

enum CandidateType { host }

enum TransportType { udp, tcp }

enum FingerprintType { sha256 }

class SdpMediaCandidate {
  final String ip;
  final int port;
  final CandidateType type;
  final TransportType transport;

  SdpMediaCandidate({
    required this.ip,
    required this.port,
    required this.type,
    required this.transport,
  });

  Map<String, dynamic> toSdpMap(int foundation, int component) {
    return {
      'foundation': foundation.toString(),
      'component': component,
      'protocol': transport.name.toUpperCase(),
      'priority': 2113937151,
      'ip': ip,
      'port': port,
      'type': type.name,
    };
  }

  factory SdpMediaCandidate.fromMap(Map<String, dynamic> map) {
    return SdpMediaCandidate(
      ip: map['ip'],
      port: map['port'],
      type: CandidateType.host, // extend if needed
      transport: map['protocol'].toLowerCase() == 'udp'
          ? TransportType.udp
          : TransportType.tcp,
    );
  }
}

class SdpMedia {
  final int mediaId;
  final MediaType type;
  final String ufrag;
  final String pwd;
  final FingerprintType fingerprintType;
  final String fingerprintHash;
  final List<SdpMediaCandidate> candidates;
  final String payloads;
  final String rtpCodec;

  SdpMedia({
    required this.mediaId,
    required this.type,
    required this.ufrag,
    required this.pwd,
    required this.fingerprintType,
    required this.fingerprintHash,
    required this.candidates,
    required this.payloads,
    required this.rtpCodec,
  });

  Map<String, dynamic> toSdpMap() {
    return {
      'type': type.name,
      'port': 9,
      'protocol': 'UDP/TLS/RTP/SAVPF',
      'payloads': payloads,
      'mid': mediaId.toString(),
      'iceUfrag': ufrag,
      'icePwd': pwd,
      'fingerprint': {
        'type': fingerprintType.name,
        'hash': fingerprintHash,
      },
      'candidates': [
        for (int i = 0; i < candidates.length; i++)
          candidates[i].toSdpMap(i, 1),
      ],
      'rtp': [
        {
          'payload': int.parse(payloads),
          'codec': rtpCodec.split('/')[0],
          'rate': int.parse(rtpCodec.split('/')[1]),
        }
      ],
      'direction': 'sendrecv',
    };
  }

  factory SdpMedia.fromMap(Map<String, dynamic> map) {
    final fingerprint = map['fingerprint'] ?? {};
    final rtpList = map['rtp'] ?? [];

    return SdpMedia(
      mediaId: int.tryParse(map['mid'] ?? '0') ?? 0,
      type: map['type'] == 'audio' ? MediaType.audio : MediaType.video,
      ufrag: map['iceUfrag'],
      pwd: map['icePwd'],
      fingerprintType: FingerprintType.sha256,
      fingerprintHash: fingerprint['hash'] ?? '',
      payloads: map['payloads'] ?? '',
      rtpCodec: rtpList.isNotEmpty
          ? '${rtpList[0]['codec']}/${rtpList[0]['rate']}'
          : '',
      candidates: (map['candidates'] as List?)
              ?.map((c) => SdpMediaCandidate.fromMap(c))
              .toList() ??
          [],
    );
  }
}

class SdpMessage {
  final String sessionId;
  final List<SdpMedia> mediaItems;

  SdpMessage({
    required this.sessionId,
    required this.mediaItems,
  });

  Map<String, dynamic> toSdpMap() {
    return {
      'version': 0,
      'origin': {
        'username': '-',
        'sessionId': sessionId,
        'sessionVersion': 1,
        'netType': 'IN',
        'ipVer': 4,
        'address': '127.0.0.1',
      },
      'name': '-',
      'timing': [0, 0],
      'media': mediaItems.map((m) {
        final media = {
          'type': m.type.name,
          'mid': m.mediaId.toString(),
          'iceUfrag': m.ufrag,
          'icePwd': m.pwd,
          'fingerprint': {
            'type': m.fingerprintType.name,
            'hash': m.fingerprintHash,
          },
          'candidates': m.candidates
              .map((c) => {
                    'foundation': '1',
                    'component': 1,
                    'transport': c.transport.name.toUpperCase(),
                    'priority': 2122260223,
                    'ip': c.ip,
                    'port': c.port,
                    'type': 'host',
                  })
              .toList(),
          'payloads': m.payloads.split(' ').map(int.parse).toList(),
          'rtp': [
            {
              'payload': int.parse(m.payloads.split(' ').first),
              'codec': m.rtpCodec.split('/')[0],
              'rate': int.parse(m.rtpCodec.split('/')[1]),
              'encoding': m.rtpCodec.contains('/')
                  ? int.tryParse(m.rtpCodec.split('/').length > 2
                      ? m.rtpCodec.split('/')[2]
                      : '1')
                  : null,
            },
          ],
        };

        return media;

        // return m.toSdpMap();
      }).toList(),
    };
  }

  String toSdpString() => write(toSdpMap(), null);

  factory SdpMessage.fromSdpString(String sdpString) {
    final map = parse(sdpString);
    return SdpMessage.fromSdpMap(map);
  }

  factory SdpMessage.fromSdpMap(Map<String, dynamic> sdpMap) {
    return SdpMessage(
      sessionId: sdpMap['origin']['sessionId'],
      mediaItems:
          (sdpMap['media'] as List).map((m) => SdpMedia.fromMap(m)).toList(),
    );
  }
}

class IceCandidate {
  final String ip;
  final int port;
  IceCandidate(this.ip, this.port);
}

class IceAgent {
  final String ufrag;
  final String pwd;
  final String fingerprintHash;
  final List<IceCandidate> iceCandidates;

  IceAgent(this.ufrag, this.pwd, this.fingerprintHash, this.iceCandidates);
}

SdpMessage generateSdpOffer(IceAgent iceAgent, {bool requestAudio = true}) {
  final candidates = iceAgent.iceCandidates
      .map((c) => SdpMediaCandidate(
            ip: c.ip,
            port: c.port,
            type: CandidateType.host,
            transport: TransportType.udp,
          ))
      .toList();

  final video = SdpMedia(
    mediaId: 0,
    type: MediaType.video,
    payloads: '96',
    rtpCodec: 'VP8/90000',
    ufrag: iceAgent.ufrag,
    pwd: iceAgent.pwd,
    fingerprintType: FingerprintType.sha256,
    fingerprintHash: iceAgent.fingerprintHash,
    candidates: candidates,
  );

  final mediaItems = [video];

  if (requestAudio) {
    final audio = SdpMedia(
      mediaId: 1,
      type: MediaType.audio,
      payloads: '109',
      rtpCodec: 'OPUS/48000/2',
      ufrag: iceAgent.ufrag,
      pwd: iceAgent.pwd,
      fingerprintType: FingerprintType.sha256,
      fingerprintHash: iceAgent.fingerprintHash,
      candidates: candidates,
    );
    mediaItems.add(audio);
  }

  return SdpMessage(sessionId: '123456789', mediaItems: mediaItems);
}

SdpMessage parseSdpOfferAnswer(Map<String, dynamic> offer) {
  final sessionId = offer['origin']?['sessionId']?.toString() ?? '0';
  final mediaItems = <SdpMedia>[];

  for (final media in (offer['media'] as List)) {
    final mid = int.tryParse(media['mid']?.toString() ?? '0') ?? 0;
    final type = (media['type'] == 'audio') ? MediaType.audio : MediaType.video;
    final ufrag = media['iceUfrag'] ?? '';
    final pwd = media['icePwd'] ?? '';

    final fingerprint = media['fingerprint'] ?? offer['fingerprint'];
    final fingerprintType = (fingerprint?['type'] ?? 'sha-256') == 'sha-256'
        ? FingerprintType.sha256
        : throw UnsupportedError('Unsupported fingerprint type');

    final fingerprintHash = fingerprint['hash'] ?? '';

    final candidates = <SdpMediaCandidate>[];
    for (final c in (media['candidates'] ?? [])) {
      candidates.add(SdpMediaCandidate(
        ip: c['ip'],
        port: (c['port'] as num).toInt(),
        type: CandidateType.host, // Extend this if needed
        transport:
            (c['transport'] == 'tcp') ? TransportType.tcp : TransportType.udp,
      ));
    }

    final payloads = media['payloads'] ?? '';
    String rtpCodec = '';
    if (media['rtp'] != null &&
        media['rtp'] is List &&
        media['rtp'].isNotEmpty) {
      final codec = media['rtp'][0];
      final codecName = codec['codec'] ?? '';
      final codecRate = codec['rate']?.toString() ?? '0';
      final channels = codec['encoding']?.toString();
      rtpCodec = channels != null
          ? '$codecName/$codecRate/$channels'
          : '$codecName/$codecRate';
    }

    mediaItems.add(SdpMedia(
      mediaId: mid,
      type: type,
      ufrag: ufrag,
      pwd: pwd,
      fingerprintType: fingerprintType,
      fingerprintHash: fingerprintHash,
      candidates: candidates,
      payloads: payloads,
      rtpCodec: rtpCodec,
    ));
  }

  return SdpMessage(
    sessionId: sessionId,
    mediaItems: mediaItems,
  );
}

void main() {
  final myIceAgent = IceAgent(
    'user123',
    'pass123',
    '12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF',
    [
      IceCandidate('192.168.1.10', 5000),
      IceCandidate('192.168.1.11', 5001),
    ],
  );

  final offer = generateSdpOffer(myIceAgent, requestAudio: true);
  final sdpString = offer.toSdpString();

  print('Generated SDP:\n$sdpString');

  final parsedMap = parse(sdpString);
  final parsedOffer = parseSdpOfferAnswer(parsedMap);

  print('\nParsed Media Items:');
  for (final media in parsedOffer.mediaItems) {
    print('- ${media.type}: ${media.rtpCodec} [${media.payloads}]');
    for (final cand in media.candidates) {
      print('  - Candidate: ${cand.ip}:${cand.port} (${cand.transport.name})');
    }
  }
}
