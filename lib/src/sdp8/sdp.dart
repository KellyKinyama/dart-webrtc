import 'commond.dart';
import 'server_agent.dart';

enum MediaType {
  audio("audio"),
  video("video");

  const MediaType(this.value);
  final String value;

  @override
  toString() {
    return value;
  }
}

enum CandidateType {
  host("host");

  const CandidateType(this.value);
  final String value;

  factory CandidateType.fromString(String key) {
    return values.firstWhere((element) => element.value == key);
  }

  @override
  toString() {
    return value;
  }
}

enum TransportType {
  udp("udp"),
  tcp("tcp");

  const TransportType(this.value);
  final String value;

  factory TransportType.fromString(String key) {
    return values.firstWhere((element) => element.value == key);
  }
  @override
  toString() {
    return value;
  }
}

enum FingerprintType {
  sha_256("sha-256");

  const FingerprintType(this.value);
  final String value;

  factory FingerprintType.fromString(String key) {
    return values.firstWhere((element) => element.value == key);
  }

  @override
  toString() {
    return value;
  }
}

class SdpMessage {
  late String sessionId;
  late List<SdpMedia> mediaItems;

  SdpMessage({required this.sessionId, required this.mediaItems});

  @override
  String toString() {
    String mediaItemsStr = "";
    int i = 0;
    for (SdpMedia media in mediaItems) {
      mediaItemsStr = "$mediaItemsStr[SdpMedia] $media";
      i++;
    }

    return joinSlice("\n", false, [
      "SessionID: $sessionId",
      processIndent("MediaItems:", "+", [mediaItemsStr])
    ]);
  }
}

class SdpMedia {
  late num mediaId;
  late MediaType type;
  late String ufrag;
  late String pwd;
  late FingerprintType fingerprintType;
  late String fingerprintHash;
  late List<SdpMediaCandidate> candidates;
  late String payloads;
  late String rtpCodec;

  SdpMedia(
      {required this.mediaId,
      required this.type,
      required this.ufrag,
      required this.pwd,
      required this.fingerprintType,
      required this.fingerprintHash,
      required this.candidates,
      required this.payloads,
      required this.rtpCodec});

  @override
  String toString() {
    String candidatesStr = "";
    for (SdpMediaCandidate candidate in candidates) {
      candidatesStr = "$candidatesStr[SdpCandidate] $candidate";
    }

    return joinSlice("\n", false, [
      processIndent(
          "MediaId: $mediaId, Type: $type, Ufrag: $ufrag, Pwd: $pwd", "", [
        "FingerprintType: $fingerprintType, FingerprintHash: $fingerprintHash",
        processIndent("Candidates:", "+", [candidatesStr])
      ])
    ]);
  }
}

class SdpMediaCandidate {
  late String ip;
  late num port;
  late CandidateType type;
  late TransportType transport;

  SdpMediaCandidate(
      {required this.ip,
      required this.port,
      required this.type,
      required this.transport});
  @override
  String toString() {
    return "Type: $type, Transport: $transport, Ip: $ip, Port: $port";
  }
}

SdpMessage generateSdpOffer(ServerAgent iceAgent) {
  final List<SdpMediaCandidate> candidates = [];
  for (IceCandidate agentCandidate in iceAgent.iceCandidates) {
    candidates.add(SdpMediaCandidate(
      ip: agentCandidate.ip,
      port: agentCandidate.port,
      type: CandidateType.fromString("host"),
      transport: TransportType.udp,
    ));
  }
  final offer = SdpMessage(sessionId: "1234", mediaItems: [
    SdpMedia(
        mediaId: 0,
        type: MediaType.video,
        payloads: "96", //rtp.PayloadTypeVP8.CodecCodeNumber(), //96
        rtpCodec:
            'VP8/90000', //rtp.PayloadTypeVP8.CodecName(),       //VP8/90000
        ufrag: iceAgent.ufrag,
        pwd: iceAgent.pwd,
        /*
					https://webrtcforthecurious.com/docs/04-securing/
					Certificate #
					Certificate contains the certificate for the Client or Server.
					This is used to uniquely identify who we were communicating with.
					After the handshake is over we will make sure this certificate
					when hashed matches the fingerprint in the SessionDescription.
				*/
        fingerprintType: FingerprintType.sha_256,
        fingerprintHash: iceAgent.fingerprintHash,
        candidates: candidates)
  ]);
  if (true) {
    offer.mediaItems.add(SdpMedia(
      mediaId: 1,
      type: MediaType.audio,
      payloads: "109", //rtp.PayloadTypeOpus.CodecCodeNumber(), //109
      rtpCodec:
          "OPUS/48000/2", //rtp.PayloadTypeOpus.CodecName(),       //OPUS/48000/2
      ufrag: iceAgent.ufrag,
      pwd: iceAgent.pwd,
      /*
				https://webrtcforthecurious.com/docs/04-securing/
				Certificate #
				Certificate contains the certificate for the Client or Server.
				This is used to uniquely identify who we were communicating with.
				After the handshake is over we will make sure this certificate
				when hashed matches the fingerprint in the SessionDescription.
			*/
      fingerprintType: FingerprintType.sha_256,
      fingerprintHash: iceAgent.fingerprintHash,
      candidates: candidates,
    ));
  }
  return offer;
}

void main() {
  final offer = generateSdpOffer(ServerAgent(
      conferenceName: "conferenceName",
      ufrag: generateICEUfrag(),
      pwd: generateICEPwd(),
      fingerprintHash: "fingerprintHash"));

  print("Sdp offer: $offer");
}
