import 'dart:convert';

import 'package:dartls/signal/fingerprint.dart';

class MediaType {
  static const String video = "video";
  static const String audio = "audio";
}

class CandidateType {
  static const String host = "host";
}

class TransportType {
  static const String udp = "udp";
  static const String tcp = "tcp";
}

class FingerprintType {
  static const String sha256 = "sha-256";
}

class SdpMessage {
  String conferenceName;
  String sessionID;
  List<SdpMedia> mediaItems;

  SdpMessage(
      {this.conferenceName = '',
      this.sessionID = '',
      this.mediaItems = const []});

  factory SdpMessage.fromMap(Map<String, dynamic> offer) {
    var sdpMessage = SdpMessage();
    sdpMessage.sessionID = offer['origin']['sessionId'];

    var mediaItems = offer['media'] as List;
    for (var mediaItemObj in mediaItems) {
      var mediaItem = mediaItemObj as Map<String, dynamic>;
      var sdpMedia = SdpMedia.fromMap(mediaItem);
      sdpMessage.mediaItems.add(sdpMedia);
    }

    return sdpMessage;
  }

  @override
  String toString() {
    var mediaItemsStr =
        mediaItems.map((media) => "${media.toString()}'\r\n'").join('\r\n');
    print("mediaItemsStr: $mediaItemsStr");
    return 'v=0\r\no=- $sessionID 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=extmap-allow-mixed\r\na=msid-semantic: WMS\r\n$mediaItemsStr\r\n';
  }
}

class SdpMedia {
  int mediaId;
  String type;
  String ufrag;
  String pwd;
  String fingerprintType;
  String fingerprintHash;
  List<SdpMediaCandidate> candidates;
  String payloads;
  String rtpCodec;

  SdpMedia({
    this.mediaId = 0,
    this.type = '',
    this.ufrag = '',
    this.pwd = '',
    this.fingerprintType = '',
    this.fingerprintHash = '',
    this.candidates = const [],
    this.payloads = '',
    this.rtpCodec = '',
  });

  factory SdpMedia.fromMap(Map<String, dynamic> mediaItem) {
    var sdpMedia = SdpMedia(
      type: mediaItem['type'],
      ufrag: mediaItem['iceUfrag'],
      pwd: mediaItem['icePwd'],
      fingerprintType: mediaItem['fingerprint']['type'],
      fingerprintHash: mediaItem['fingerprint']['hash'],
    );

    if (mediaItem['candidates'] != null) {
      var candidates = mediaItem['candidates'] as List;
      sdpMedia.candidates = candidates
          .map((candidate) => SdpMediaCandidate.fromMap(candidate))
          .toList();
    }

    return sdpMedia;
  }

  @override
  String toString() {
    var candidatesStr =
        candidates.map((candidate) => candidate.toString()).join('\r\n');
    return [
      'm=${type} 0 RTP/AVP ${payloads}\r\n',
      'c=IN IP4 127.0.0.1\r\n',
      'a=rtpmap:96 ${rtpCodec}/90000\r\n',
      'a=ice-ufrag:$ufrag\r\n',
      'a=ice-pwd:$pwd\r\n',
      'a=fingerprint:$fingerprintType ${fingerprint()}\r\n',
      'a=candidate:${candidatesStr}'
    ].join();
  }
}

class SdpMediaCandidate {
  String ip;
  int port;
  String type;
  String transport;

  SdpMediaCandidate({
    this.ip = '',
    this.port = 0,
    this.type = '',
    this.transport = '',
  });

  factory SdpMediaCandidate.fromMap(Map<String, dynamic> candidate) {
    return SdpMediaCandidate(
      ip: candidate['ip'],
      port: candidate['port'].toInt(),
      type: candidate['type'],
      transport: candidate['transport'],
    );
  }

  @override
  String toString() {
    return 'a=candidate:$type $ip $port typ $transport';
  }
}

class Agent {
  String ufrag;
  String pwd;
  String fingerprintHash;
  List<SdpMediaCandidate> iceCandidates;

  Agent({
    this.ufrag = '',
    this.pwd = '',
    this.fingerprintHash = '',
    this.iceCandidates = const [],
  });

  SdpMessage generateSdpOffer() {
    var candidates = iceCandidates.map((agentCandidate) {
      return SdpMediaCandidate(
        ip: agentCandidate.ip,
        port: agentCandidate.port,
        type: CandidateType.host,
        transport: TransportType.udp,
      );
    }).toList();

    var offer = SdpMessage(
      sessionID: '1234',
      mediaItems: [
        SdpMedia(
          mediaId: 0,
          type: MediaType.video,
          payloads: '96', // VP8 codec number
          rtpCodec: 'VP8/90000',
          ufrag: ufrag,
          pwd: pwd,
          fingerprintType: FingerprintType.sha256,
          fingerprintHash: fingerprintHash,
          candidates: candidates,
        ),
      ],
    );

    return offer;
  }
}

void main() {
  // Example usage
  var agent = Agent(
    ufrag: 'ufrag123',
    pwd: 'pwd123',
    fingerprintHash: fingerprint(),
    iceCandidates: [
      SdpMediaCandidate(
          ip: '127.0.0.1',
          port: 4444,
          type: CandidateType.host,
          transport: TransportType.udp),
    ],
  );

  var offer = agent.generateSdpOffer();
  print(offer);
}
