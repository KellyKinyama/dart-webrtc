import 'string_utils.dart'
    as su; // Assuming you have a string_utils.dart for string manipulation

// sdp.dart

// Assuming 'agent', 'common', 'config', 'logging', 'rtp' are other modules/packages
// You'll need to create Dart equivalents for these or find suitable Dart packages.
// For example, 'logging' could be replaced by Dart's 'logging' package.

// Enum definitions
enum MediaType {
  video,
  audio,
}

String mediaTypeToString(MediaType type) {
  switch (type) {
    case MediaType.video:
      return 'video';
    case MediaType.audio:
      return 'audio';
    default:
      return '';
  }
}

MediaType mediaTypeFromString(String type) {
  switch (type.toLowerCase()) {
    case 'video':
      return MediaType.video;
    case 'audio':
      return MediaType.audio;
    default:
      throw ArgumentError('Invalid MediaType: $type');
  }
}

enum CandidateType {
  host,
}

String candidateTypeToString(CandidateType type) {
  switch (type) {
    case CandidateType.host:
      return 'host';
    default:
      return '';
  }
}

CandidateType candidateTypeFromString(String type) {
  switch (type.toLowerCase()) {
    case 'host':
      return CandidateType.host;
    default:
      throw ArgumentError('Invalid CandidateType: $type');
  }
}

enum TransportType {
  udp,
  tcp,
}

String transportTypeToString(TransportType type) {
  switch (type) {
    case TransportType.udp:
      return 'udp';
    case TransportType.tcp:
      return 'tcp';
    default:
      return '';
  }
}

TransportType transportTypeFromString(String type) {
  switch (type.toLowerCase()) {
    case 'udp':
      return TransportType.udp;
    case 'tcp':
      return TransportType.tcp;
    default:
      throw ArgumentError('Invalid TransportType: $type');
  }
}

enum FingerprintType {
  sha256, // Dart enums usually use camelCase, but to match "sha-256"
}

String fingerprintTypeToString(FingerprintType type) {
  switch (type) {
    case FingerprintType.sha256:
      return 'sha-256';
    default:
      return '';
  }
}

FingerprintType fingerprintTypeFromString(String type) {
  switch (type.toLowerCase()) {
    case 'sha-256':
      return FingerprintType.sha256;
    default:
      throw ArgumentError('Invalid FingerprintType: $type');
  }
}

// Class definitions
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
    var mediaItemsList = <SdpMedia>[];
    if (json['mediaItems'] != null) {
      json['mediaItems'].forEach((v) {
        mediaItemsList.add(SdpMedia.fromJson(v));
      });
    }
    return SdpMessage(
      sessionId: json['sessionId'] ?? json['origin']?['sessionId'] ?? '',
      mediaItems: mediaItemsList,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['sessionId'] = sessionId;
    data['mediaItems'] = mediaItems.map((v) => v.toJson()).toList();
    if (conferenceName != null) {
      data['conferenceName'] = conferenceName;
    }
    return data;
  }

  @override
  String toString() {
    var mediaItemsStr = mediaItems.map((media) => '[SdpMedia] $media').toList();
    // Assuming string_utils.dart is imported as su
    // import 'string_utils.dart' as su;

    return su.joinSlice("\n", false, [
      'SessionID: <u>$sessionId</u>', // Assuming you want to keep the <u> tags or handle them
      su.processIndent("MediaItems:", "+", mediaItemsStr),
    ]);
  }
}

class SdpMedia {
  int mediaId;
  MediaType type;
  String ufrag;
  String pwd;
  FingerprintType fingerprintType;
  String fingerprintHash;
  List<SdpMediaCandidate> candidates;
  String payloads; // Consider if this should be a List<int> or specific type
  String rtpCodec; // Consider if this should be a more specific type

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

  factory SdpMedia.fromJson(Map<String, dynamic> json) {
    var candidatesList = <SdpMediaCandidate>[];
    if (json['candidates'] != null) {
      json['candidates'].forEach((v) {
        candidatesList.add(SdpMediaCandidate.fromJson(v));
      });
    }
    return SdpMedia(
      mediaId: json['mediaId']?.toInt() ?? 0,
      type: mediaTypeFromString(json['type'] ?? 'video'),
      ufrag: json['ufrag'] ?? json['iceUfrag'] ?? '',
      pwd: json['pwd'] ?? json['icePwd'] ?? '',
      fingerprintType: fingerprintTypeFromString(
          json['fingerprintType'] ?? json['fingerprint']?['type'] ?? 'sha-256'),
      fingerprintHash:
          json['fingerprintHash'] ?? json['fingerprint']?['hash'] ?? '',
      candidates: candidatesList,
      payloads: json['payloads'] ?? '',
      rtpCodec: json['rtpCodec'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['mediaId'] = mediaId;
    data['type'] = mediaTypeToString(type);
    data['ufrag'] = ufrag;
    data['pwd'] = pwd;
    data['fingerprintType'] = fingerprintTypeToString(fingerprintType);
    data['fingerprintHash'] = fingerprintHash;
    data['candidates'] = candidates.map((v) => v.toJson()).toList();
    data['payloads'] = payloads;
    data['rtpCodec'] = rtpCodec;
    return data;
  }

  @override
  String toString() {
    var candidatesStr =
        candidates.map((candidate) => '[SdpCandidate] $candidate').toList();
    // Assuming string_utils.dart is imported as su

    // The original Go code had a more complex structure here.
    // It was common.ProcessIndent(fmt.Sprintf(...), "", []string{...})
    // This implies the formatted string itself was the "title" and the array was its "lines".

    String mediaDetails =
        'MediaId: <u>$mediaId</u>, Type: ${mediaTypeToString(type)}, Ufrag: <u>$ufrag</u>, Pwd: <u>$pwd</u>';
    List<String> detailsLines = [
      'FingerprintType: <u>${fingerprintTypeToString(fingerprintType)}</u>, FingerprintHash: <u>$fingerprintHash</u>',
      su.processIndent("Candidates:", "+", candidatesStr),
    ];

    return su.joinSlice("\n", false, [
      su.processIndent(mediaDetails, "",
          detailsLines) // No bullet for the main details lines
    ]);
  }
}

class SdpMediaCandidate {
  String ip;
  int port;
  CandidateType type;
  TransportType transport;

  SdpMediaCandidate({
    required this.ip,
    required this.port,
    required this.type,
    required this.transport,
  });

  factory SdpMediaCandidate.fromJson(Map<String, dynamic> json) {
    return SdpMediaCandidate(
      ip: json['ip'] ?? '',
      port: json['port']?.toInt() ?? 0,
      type: candidateTypeFromString(json['type'] ?? 'host'),
      transport: transportTypeFromString(json['transport'] ?? 'udp'),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['ip'] = ip;
    data['port'] = port;
    data['type'] = candidateTypeToString(type);
    data['transport'] = transportTypeToString(transport);
    return data;
  }

  @override
  String toString() {
    return 'Type: ${candidateTypeToString(type)}, Transport: ${transportTypeToString(transport)}, Ip: $ip, Port: $port';
  }
}

// sdp.dart (or wherever your SdpMessage and related classes are defined)

// Ensure you have these enums and classes defined above this function:
// enum MediaType {...}
// enum CandidateType {...}
// enum TransportType {...}
// enum FingerprintType {...}
// class SdpMessage {...}
// class SdpMedia {...}
// class SdpMediaCandidate {...}
// And the helper functions like mediaTypeFromString, candidateTypeFromString etc.

// Placeholder for actual parsing if the structure is more complex.
// For the given Go code, it seems 'payloads' and 'rtpCodec' for SdpMedia
// were primarily set during offer generation rather than parsed from an answer.
// If your SDP answer contains detailed RTP maps (a=rtpmap, a=fmtp lines),
// you'll need a more sophisticated parser here.

SdpMessage parseSdpOfferAnswer(Map<String, dynamic> offer) {
  String sessionId = offer['origin']?['sessionId']?.toString() ?? '';
  List<SdpMedia> mediaItems = [];

  if (offer['media'] is List) {
    for (var mediaItemObj in (offer['media'] as List)) {
      if (mediaItemObj is Map<String, dynamic>) {
        MediaType type =
            mediaTypeFromString(mediaItemObj['type']?.toString() ?? 'video');
        String ufrag = mediaItemObj['iceUfrag']?.toString() ?? '';
        String pwd = mediaItemObj['icePwd']?.toString() ?? '';

        Map<String, dynamic>? fingerprintData =
            mediaItemObj['fingerprint'] ?? offer['fingerprint'];
        FingerprintType fingerprintTypeVal = FingerprintType.sha256;
        String fingerprintHashVal = '';

        if (fingerprintData is Map<String, dynamic>) {
          fingerprintTypeVal = fingerprintTypeFromString(
              fingerprintData['type']?.toString() ?? 'sha-256');
          fingerprintHashVal = fingerprintData['hash']?.toString() ?? '';
        }

        List<SdpMediaCandidate> candidates = [];
        if (mediaItemObj['candidates'] is List) {
          for (var candidateObj in (mediaItemObj['candidates'] as List)) {
            if (candidateObj is Map<String, dynamic>) {
              candidates.add(SdpMediaCandidate(
                ip: candidateObj['ip']?.toString() ?? '',
                port: int.tryParse(candidateObj['port']?.toString() ?? '') ??
                    0, // Robust parsing
                type: candidateTypeFromString(
                    candidateObj['type']?.toString() ?? 'host'),
                transport: transportTypeFromString(
                    candidateObj['transport']?.toString() ?? 'udp'),
              ));
            }
          }
        }

        // Simplified parsing for 'payloads' and 'rtpCodec' based on common SDP structures.
        // Assumes 'rtp' is a list of maps, each with 'payload', 'codec', and 'rate'.
        String parsedPayloads = '';
        String parsedRtpCodec = '';

        if (mediaItemObj['rtp'] is List) {
          List<String> rtpPayloads = [];
          List<String> rtpCodecs = [];
          for (var rtpMapEntry in (mediaItemObj['rtp'] as List)) {
            if (rtpMapEntry is Map<String, dynamic>) {
              if (rtpMapEntry['payload'] != null) {
                rtpPayloads.add(rtpMapEntry['payload'].toString());
              }
              if (rtpMapEntry['codec'] != null && rtpMapEntry['rate'] != null) {
                rtpCodecs.add("${rtpMapEntry['codec']}/${rtpMapEntry['rate']}");
              }
            }
          }
          parsedPayloads = rtpPayloads.join(' ');
          parsedRtpCodec = rtpCodecs.join('; ');
        }

        // You might also need to parse 'fmtp' attributes here if they are relevant
        // for codec parameters and append them to parsedRtpCodec or store separately.
        // Example:
        // if (mediaItemObj['fmtp'] is List) {
        //   for (var fmtpEntry in (mediaItemObj['fmtp'] as List)) {
        //     if (fmtpEntry is Map<String, dynamic> && fmtpEntry['config'] != null) {
        //       // Typically, fmtp lines are associated with a specific payload type.
        //       // You'd need to match fmtpEntry['payload'] with one from the rtp list.
        //       // E.g., "a=fmtp:96 profile-level-id=42e01f;level-asymmetry-allowed=1;packetization-mode=1"
        //       // parsedRtpCodec += "; fmtpConfig=${fmtpEntry['config']}"; // Simplified
        //     }
        //   }
        // }

        mediaItems.add(SdpMedia(
          mediaId: int.tryParse(mediaItemObj['mid']?.toString() ?? '') ??
              mediaItems.length, // Robust parsing
          type: type,
          ufrag: ufrag,
          pwd: pwd,
          fingerprintType: fingerprintTypeVal,
          fingerprintHash: fingerprintHashVal,
          candidates: candidates,
          payloads: parsedPayloads,
          rtpCodec: parsedRtpCodec,
        ));
      }
    }
  }

  // logging.Descf(...) equivalent
  print(
      "It seems the client has received our SDP Offer, processed it, accepted it, initialized its media devices (webcam, microphone, etc...), started its UDP listener, and sent us this SDP Answer. In this project, we don't use the client's candidates, because we has implemented only receiver functionalities, so we don't have any media stream to send :)");
  SdpMessage sdpMessage =
      SdpMessage(sessionId: sessionId, mediaItems: mediaItems);
  print("Processing Incoming SDP: $sdpMessage");
  print("\n\n"); // LineSpacer(2)

  return sdpMessage;
}

// Placeholder for ServerAgent and related types for generateSdpOffer
class AgentCandidate {
  String ip;
  int port;
  AgentCandidate({required this.ip, required this.port});
}

class ServerAgent {
  String ufrag;
  String pwd;
  String fingerprintHash;
  List<AgentCandidate> iceCandidates;

  ServerAgent({
    required this.ufrag,
    required this.pwd,
    required this.fingerprintHash,
    required this.iceCandidates,
  });
}

// Placeholder for RTP constants for generateSdpOffer
class RtpPayloadType {
  final String _codecCodeNumber;
  final String _codecName;

  RtpPayloadType(this._codecCodeNumber, this._codecName);

  String codecCodeNumber() => _codecCodeNumber;
  String codecName() => _codecName;
}

final RtpPayloadType payloadTypeVP8 = RtpPayloadType("96", "VP8/90000"); //
final RtpPayloadType payloadTypeOpus = RtpPayloadType("109", "OPUS/48000/2"); //

// Placeholder for config for generateSdpOffer
class Config {
  ServerConfig server = ServerConfig();
}

class ServerConfig {
  bool requestAudio = true; // Default, adjust as needed
}

final config = Config();

SdpMessage generateSdpOffer(ServerAgent iceAgent) {
  List<SdpMediaCandidate> candidates = [];
  for (var agentCandidate in iceAgent.iceCandidates) {
    candidates.add(SdpMediaCandidate(
      ip: agentCandidate.ip,
      port: agentCandidate.port,
      type: CandidateType.host, // In Go it was "host" string
      transport: TransportType.udp,
    ));
  }

  List<SdpMedia> mediaItems = [
    SdpMedia(
      mediaId: 0,
      type: MediaType.video,
      payloads: payloadTypeVP8.codecCodeNumber(), //
      rtpCodec: payloadTypeVP8.codecName(), //
      ufrag: iceAgent.ufrag,
      pwd: iceAgent.pwd,
      fingerprintType: FingerprintType.sha256,
      fingerprintHash: iceAgent.fingerprintHash,
      candidates: List.from(candidates), // Create a copy for this media item
    ),
  ];

  if (config.server.requestAudio) {
    //
    mediaItems.add(SdpMedia(
      mediaId: 1,
      type: MediaType.audio,
      payloads: payloadTypeOpus.codecCodeNumber(), //
      rtpCodec: payloadTypeOpus.codecName(), //
      ufrag: iceAgent.ufrag,
      pwd: iceAgent.pwd,
      fingerprintType: FingerprintType.sha256,
      fingerprintHash: iceAgent.fingerprintHash,
      candidates: List.from(candidates), // Create a copy for this media item
    ));
  }

  return SdpMessage(
    sessionId: "1234", //
    mediaItems: mediaItems,
  );
}

void main() {
  // Example Usage (you'll need to populate ServerAgent and offerJson)
  var iceAgent = ServerAgent(
    ufrag: "someUfrag",
    pwd: "somePassword",
    fingerprintHash: "someFingerprintHash",
    iceCandidates: [AgentCandidate(ip: "192.168.1.100", port: 9000)],
  );

  SdpMessage offer = generateSdpOffer(iceAgent);
  print("Generated SDP Offer:");
  print(offer.toJson()); // Or offer.toString() for formatted string

  // Example for parsing an offer/answer
  Map<String, dynamic> offerJson = {
    "origin": {"sessionId": "5678"},
    "media": [
      {
        "type": "video",
        "mid": "0",
        "iceUfrag": "clientUfragVideo",
        "icePwd": "clientPwdVideo",
        "fingerprint": {"type": "sha-256", "hash": "clientFingerprintVideo"},
        "candidates": [
          {
            "ip": "192.168.1.200",
            "port": 7000,
            "type": "host",
            "transport": "udp"
          }
        ],
        "rtp": [
          // Example of how rtp payload info might look
          {"payload": 96, "codec": "VP8", "rate": 90000}
        ]
      }
    ]
  };
  SdpMessage parsedAnswer = parseSdpOfferAnswer(offerJson);
  print("\nParsed SDP Answer:");
  print(parsedAnswer.toJson()); // Or parsedAnswer.toString()
}
