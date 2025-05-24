import 'package:collection/collection.dart';

enum MediaType {
  video,
  audio,
}

enum CandidateType {
  host,
}

enum TransportType {
  udp,
  tcp,
}

enum FingerprintType {
  sha256,
}

class SdpMessage {
  String? conferenceName;
  String sessionId;
  List<SdpMedia> mediaItems;

  SdpMessage({
    this.conferenceName,
    required this.sessionId,
    required this.mediaItems,
  });

  factory SdpMessage.fromJson(Map<String, dynamic> json) {
    final mediaList = json['media'] as List<dynamic>?;
    return SdpMessage(
      sessionId: (json['origin'] as Map<String, dynamic>)['sessionId'] as String,
      mediaItems: mediaList?.map((item) => SdpMedia.fromJson(item as Map<String, dynamic>)).toList() ?? [],
    );
  }

  @override
  String toString() {
    final mediaItemsStr = mediaItems.map((media) => '[SdpMedia] $media').toList();
    return [
      'SessionID: <u>$sessionId</u>',
      'MediaItems:',
      ...mediaItemsStr.map((str) => '+ $str'),
    ].join('\n');
  }
}

class SdpMedia {
  int? mediaId;
  MediaType type;
  String? ufrag;
  String? pwd;
  FingerprintType? fingerprintType;
  String? fingerprintHash;
  List<SdpMediaCandidate> candidates;
  String? payloads;
  String? rtpCodec;

  SdpMedia({
    this.mediaId,
    required this.type,
    this.ufrag,
    this.pwd,
    this.fingerprintType,
    this.fingerprintHash,
    this.candidates = const [],
    this.payloads,
    this.rtpCodec,
  });

  factory SdpMedia.fromJson(Map<String, dynamic> json) {
    final candidatesList = json['candidates'] as List<dynamic>?;
    Map<String, dynamic>? fingerprint;
    if (json.containsKey('fingerprint')) {
      fingerprint = json['fingerprint'] as Map<String, dynamic>?;
    }
    return SdpMedia(
      type: _parseMediaType(json['type'] as String),
      ufrag: json['iceUfrag'] as String?,
      pwd: json['icePwd'] as String?,
      fingerprintType: fingerprint != null ? _parseFingerprintType(fingerprint['type'] as String) : null,
      fingerprintHash: fingerprint != null ? fingerprint['hash'] as String? : null,
      candidates: candidatesList?.map((item) => SdpMediaCandidate.fromJson(item as Map<String, dynamic>)).toList() ?? [],
      payloads: json['payloads'] as String?,
      rtpCodec: json['rtpCodec'] as String?,
    );
  }

  @override
  String toString() {
    final candidatesStr = candidates.map((candidate) => '[SdpCandidate] $candidate').toList();
    return [
      'MediaId: <u>$mediaId</u>, Type: $type, Ufrag: <u>$ufrag</u>, Pwd: <u>$pwd</u>',
      if (fingerprintType != null && fingerprintHash != null)
        '  FingerprintType: <u>$fingerprintType</u>, FingerprintHash: <u>$fingerprintHash</u>',
      '  Candidates:',
      ...candidatesStr.map((str) => '  + $str'),
    ].join('\n');
  }
}

class SdpMediaCandidate {
  String? ip;
  int? port;
  CandidateType? type;
  TransportType? transport;

  SdpMediaCandidate({
    this.ip,
    this.port,
    this.type,
    this.transport,
  });

  factory SdpMediaCandidate.fromJson(Map<String, dynamic> json) {
    return SdpMediaCandidate(
      ip: json['ip'] as String?,
      port: (json['port'] as num?)?.toInt(),
      type: _parseCandidateType(json['type'] as String?),
      transport: _parseTransportType(json['transport'] as String?),
    );
  }

  @override
  String toString() {
    return 'Type: <u>$type</u>, Transport: <u>$transport</u>, Ip: <u>$ip</u>, Port: <u>$port</u>';
  }
}

MediaType _parseMediaType(String value) {
  return MediaType.values.firstWhere((e) => e.toString().split('.').last == value);
}

CandidateType? _parseCandidateType(String? value) {
  if (value == null) return null;
  return CandidateType.values.firstWhereOrNull((e) => e.toString().split('.').last == value);
}

TransportType? _parseTransportType(String? value) {
  if (value == null) return null;
  return TransportType.values.firstWhereOrNull((e) => e.toString().split('.').last == value);
}

FingerprintType _parseFingerprintType(String value) {
  return FingerprintType.values.firstWhere((e) => e.toString().split('.').last == value);
}

// --- Functions that rely on external packages are omitted ---
// --- You would need to implement or mock the 'agent', 'common', 'config', and 'rtp' packages ---

// Example of how you might start to implement the Go functions in Dart:

// SdpMessage parseSdpOfferAnswer(Map<String, dynamic> offer) {
//   final sdpMessage = SdpMessage.fromJson(offer);
//   // ... rest of the logic from the Go function
//   print("It seems the client has received our SDP Offer, processed it, accepted it, initialized it's media devices (webcam, microphone, etc...), started it's UDP listener, and sent us this SDP Answer. In this project, we don't use the client's candidates, because we has implemented only receiver functionalities, so we don't have any media stream to send :)");
//   print("Processing Incoming SDP: $sdpMessage");
//   print("\n\n");
//   return sdpMessage;
// }

// SdpMessage generateSdpOffer(/* agent.ServerAgent iceAgent */) {
//   final candidates = <SdpMediaCandidate>[];
//   // for _, agentCandidate := range iceAgent.IceCandidates {
//   //   candidates.add(SdpMediaCandidate(
//   //     ip: agentCandidate.Ip,
//   //     port: agentCandidate.Port,
//   //     type: CandidateType.host,
//   //     transport: TransportType.udp,
//   //   ));
//   // }
//   final offer = SdpMessage(
//     sessionId: "1234",
//     mediaItems: [
//       SdpMedia(
//         mediaId: 0,
//         type: MediaType.video,
//         payloads: /* rtp.PayloadTypeVP8.CodecCodeNumber() */ "96", // Placeholder
//         rtpCodec: /* rtp.PayloadTypeVP8.CodecName() */ "VP8/90000", // Placeholder
//         ufrag: /* iceAgent.Ufrag */ "ufrag", // Placeholder
//         pwd: /* iceAgent.Pwd */ "pwd", // Placeholder
//         fingerprintType: FingerprintType.sha256,
//         fingerprintHash: /* iceAgent.FingerprintHash */ "fingerprintHash", // Placeholder
//         candidates: candidates,
//       ),
//     ],
//   );
//   // if (config.Val.Server.RequestAudio) {
//   //   offer.mediaItems.add(SdpMedia(
//   //     mediaId: 1,
//   //     type: MediaType.audio,
//   //     payloads: rtp.PayloadTypeOpus.CodecCodeNumber(), //109
//   //     rtpCodec: rtp.PayloadTypeOpus.CodecName(), //OPUS/48000/2
//   //     ufrag: iceAgent.Ufrag,
//   //     pwd: iceAgent.Pwd,
//   //     fingerprintType: FingerprintType.sha256,
//   //     fingerprintHash: iceAgent.FingerprintHash,
//   //     candidates: candidates,
//   //   ));
//   // }
//   return offer;
// }

// // You would also need to implement the 'common' package's 'JoinSlice' and 'ProcessIndent'
// // functionalities if you intend to use the 'toString' methods exactly as in Go.