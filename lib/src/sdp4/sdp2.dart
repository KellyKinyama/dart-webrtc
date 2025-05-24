// src/sdp/sdp.dart

// import 'package:your_project/agent/server_agent.dart';
// import 'package:your_project/rtp/rtp.dart';
// import 'package:your_project/common/common.dart';
// import 'package:your_project/config/config.dart';
// import 'package:your_project/logging/logging.dart';

import '../agent/server_agent2.dart';

enum MediaType { video, audio }

enum CandidateType { host }

enum TransportType { udp, tcp }

enum FingerprintType { sha256 }

class SdpMessage {
  final String conferenceName;
  final String sessionId;
  final List<SdpMedia> mediaItems;

  SdpMessage({
    required this.conferenceName,
    required this.sessionId,
    required this.mediaItems,
  });

  factory SdpMessage.fromMap(Map<String, dynamic> data) {
    final sessionId = data['origin']['sessionId'] as String;
    final media = (data['media'] as List).cast<Map<String, dynamic>>();

    final mediaItems = media.map((mediaItem) {
      final candidatesData = (mediaItem['candidates'] ?? []) as List;
      final fingerprint = (mediaItem['fingerprint'] ?? data['fingerprint'])
          as Map<String, dynamic>;

      return SdpMedia(
        mediaId: mediaItem['mid'] ?? 0,
        type: _parseMediaType(mediaItem['type']),
        ufrag: mediaItem['iceUfrag'],
        pwd: mediaItem['icePwd'],
        fingerprintType: _parseFingerprintType(fingerprint['type']),
        fingerprintHash: fingerprint['hash'],
        payloads: mediaItem['payloads'] ?? '',
        rtpCodec: mediaItem['rtpCodec'] ?? '',
        candidates: candidatesData
            .map<SdpMediaCandidate>((c) => SdpMediaCandidate.fromMap(c))
            .toList(),
      );
    }).toList();

    // logProtoSDP('Client received our SDP Offer, processed and accepted it.');
    // logInfoSDP('Incoming SDP processed: $sessionId');

    return SdpMessage(
      conferenceName: '',
      sessionId: sessionId,
      mediaItems: mediaItems,
    );
  }

  static MediaType _parseMediaType(String value) {
    switch (value) {
      case 'audio':
        return MediaType.audio;
      case 'video':
        return MediaType.video;
      default:
        throw ArgumentError('Unknown media type: $value');
    }
  }

  static FingerprintType _parseFingerprintType(String value) {
    switch (value.toLowerCase()) {
      case 'sha-256':
        return FingerprintType.sha256;
      default:
        throw ArgumentError('Unknown fingerprint type: $value');
    }
  }

  @override
  String toString() {
    final mediaItemsStr =
        mediaItems.map((media) => "[SdpMedia] ${media.toString()}").toList();
    return joinSlice("\n", false, [
      "SessionID: <u>$sessionId</u>",
      processIndent("MediaItems:", "+", mediaItemsStr),
    ]);
  }
}

class SdpMedia {
  final int mediaId;
  final MediaType type;
  final String ufrag;
  final String pwd;
  final FingerprintType fingerprintType;
  final String fingerprintHash;
  final String payloads;
  final String rtpCodec;
  final List<SdpMediaCandidate> candidates;

  SdpMedia({
    required this.mediaId,
    required this.type,
    required this.ufrag,
    required this.pwd,
    required this.fingerprintType,
    required this.fingerprintHash,
    required this.payloads,
    required this.rtpCodec,
    required this.candidates,
  });

  @override
  String toString() {
    final candidatesStr = candidates
        .map((candidate) => "[SdpCandidate] ${candidate.toString()}")
        .toList();
    return joinSlice("\n", false, [
      processIndent(
        "MediaId: <u>$mediaId</u>, Type: $type, Ufrag: <u>$ufrag</u>, Pwd: <u>$pwd</u>",
        "",
        [
          "FingerprintType: <u>$fingerprintType</u>, FingerprintHash: <u>$fingerprintHash</u>",
          processIndent("Candidates:", "+", candidatesStr),
        ],
      ),
    ]);
  }
}

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

  factory SdpMediaCandidate.fromMap(Map<String, dynamic> data) {
    return SdpMediaCandidate(
      ip: data['ip'],
      port: (data['port'] as num).toInt(),
      type: CandidateType.host,
      transport: _parseTransportType(data['transport']),
    );
  }

  static TransportType _parseTransportType(String value) {
    switch (value.toLowerCase()) {
      case 'udp':
        return TransportType.udp;
      case 'tcp':
        return TransportType.tcp;
      default:
        throw ArgumentError('Unknown transport type: $value');
    }
  }

  @override
  String toString() {
    return "Type: <u>$type</u>, Transport: <u>$transport</u>, Ip: <u>${maskIPString(ip)}</u>, Port: <u>$port</u>";
  }
}

bool requestAudio = true;
SdpMessage generateSdpOffer(ServerAgent agent) {
  final candidates = agent.iceCandidates.map((candidate) {
    return SdpMediaCandidate(
      ip: candidate.ip,
      port: candidate.port,
      type: CandidateType.host,
      transport: TransportType.udp,
    );
  }).toList();

  final mediaItems = <SdpMedia>[
    SdpMedia(
      mediaId: 0,
      type: MediaType.video,
      ufrag: agent.ufrag,
      pwd: agent.pwd,
      fingerprintType: FingerprintType.sha256,
      fingerprintHash: agent.fingerprintHash,
      payloads: RtpPayloadType.vp8.codecCodeNumber().toString(),
      rtpCodec: RtpPayloadType.vp8.codecName(),
      candidates: candidates,
    ),
  ];

  if (requestAudio) {
    mediaItems.add(
      SdpMedia(
        mediaId: 1,
        type: MediaType.audio,
        ufrag: agent.ufrag,
        pwd: agent.pwd,
        fingerprintType: FingerprintType.sha256,
        fingerprintHash: agent.fingerprintHash,
        payloads: RtpPayloadType.opus.codecCodeNumber().toString(),
        rtpCodec: RtpPayloadType.opus.codecName(),
        candidates: candidates,
      ),
    );
  }

  return SdpMessage(
    conferenceName: 'default',
    sessionId: '1234',
    mediaItems: mediaItems,
  );
}

enum RtpPayloadType { vp8, opus }

extension RtpPayloadTypeExtension on RtpPayloadType {
  String codecName() {
    switch (this) {
      case RtpPayloadType.vp8:
        return 'VP8';
      case RtpPayloadType.opus:
        return 'Opus';
    }
  }

  int codecCodeNumber() {
    switch (this) {
      case RtpPayloadType.vp8:
        return 96; // Example codec number for VP8
      case RtpPayloadType.opus:
        return 111; // Example codec number for Opus
    }
  }
}

SdpMedia createSdpMedia({
  required int mediaId,
  required MediaType type,
  required String ufrag,
  required String pwd,
  required String fingerprintHash,
  required RtpPayloadType payloadType,
  required List<SdpMediaCandidate> candidates,
}) {
  return SdpMedia(
    mediaId: mediaId,
    type: type,
    ufrag: ufrag,
    pwd: pwd,
    fingerprintType: FingerprintType.sha256,
    fingerprintHash: fingerprintHash,
    payloads: payloadType.codecCodeNumber().toString(),
    rtpCodec: payloadType.codecName(),
    candidates: candidates,
  );
}

String joinSlice(String separator, bool indent, List<String> lines) {
  final buffer = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    if (indent) {
      buffer.write('\t');
    }
    buffer.write(lines[i]);
    if (i < lines.length - 1) {
      buffer.write(separator);
    }
  }
  return buffer.toString();
}

String processIndent(String title, String bullet, List<String> lines) {
  final buffer = StringBuffer();
  if (title.isNotEmpty) {
    buffer.write(title);
    buffer.write('\n');
  }
  for (var i = 0; i < lines.length; i++) {
    buffer.write('\t');
    if (bullet.isNotEmpty) {
      buffer.write('$bullet ');
    }
    if (lines[i].contains('\n')) {
      final parts = lines[i].split('\n');
      buffer.write(processIndent(parts[0], "", parts.sublist(1)));
    } else {
      buffer.write(lines[i]);
    }
    if (i < lines.length - 1) {
      buffer.write('\n');
    }
  }
  return buffer.toString();
}

List<String> toStrSlice(List<dynamic> values) {
  return values.map((e) => e as String).toList();
}

String maskIPString(String ip) {
  final parts = ip.split('.');
  final buffer = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    if (i > 0) {
      buffer.write('.');
    }
    if (i < 2) {
      buffer.write(parts[i]);
    } else {
      buffer.write('***');
    }
  }
  return buffer.toString();
}



void main(){
  SdpMessage sdpMsg= generateSdpOffer(ServerAgent(conferenceName: '')) ;

}