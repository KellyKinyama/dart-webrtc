import 'dart:convert';

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

  SdpMessage({
    required this.conferenceName,
    required this.sessionID,
    required this.mediaItems,
  });

  @override
  String toString() {
    String mediaItemsStr =
        mediaItems.map((media) => media.toString()).join('\r\n');
    return 'v=0\r\n'
        'o=- $sessionID 3 IN IP4 127.0.0.1\r\n'
        's=-\r\n'
        't=0 0\r\n'
        'a=group:BUNDLE 0\r\n'
        'a=extmap-allow-mixed\r\n'
        'a=msid-semantic: WMS b7698b5d-fc96-465e-9505-bd9347113a40\r\n'
        '$mediaItemsStr';
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
  List<String> extmaps;
  String setup;
  String mid;

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
    required this.extmaps,
    required this.setup,
    required this.mid,
  });

  @override
  String toString() {
    String candidatesStr =
        candidates.map((candidate) => candidate.toString()).join('\r\n');
    String extmapStr = extmaps.map((extmap) => 'a=extmap:$extmap').join('\r\n');

    // Generate individual rtpmap lines for each payload type
    String rtpmapStr = payloads
        .split(" ")
        .map((payloadType) => 'a=rtpmap:$payloadType $rtpCodec/90000\r\n')
        .join('');

    return 'm=$type 4444 UDP/TLS/RTP/SAVPF $payloads\r\n'
        'c=IN IP4 127.0.0.1\r\n'
        '$candidatesStr\r\n'
        'a=ice-ufrag:$ufrag\r\n'
        'a=ice-pwd:$pwd\r\n'
        'a=ice-options:trickle\r\n'
        'a=fingerprint:$fingerprintType $fingerprintHash\r\n'
        'a=setup:$setup\r\n'
        'a=mid:$mid\r\n'
        '$extmapStr\r\n'
        'a=sendrecv\r\n'
        'a=rtcp-mux\r\n'
        'a=rtcp-rsize\r\n'
        '$rtpmapStr' // Include the rtpmap lines here
        'a=rtcp-fb:$payloads goog-remb\r\n'
        'a=rtcp-fb:$payloads transport-cc\r\n'
        'a=rtcp-fb:$payloads ccm fir\r\n'
        'a=rtcp-fb:$payloads nack\r\n'
        'a=rtcp-fb:$payloads nack pli\r\n';
  }
}

class SdpMediaCandidate {
  String ip;
  int port;
  String type;
  String transport;

  SdpMediaCandidate({
    required this.ip,
    required this.port,
    required this.type,
    required this.transport,
  });

  @override
  String toString() {
    return 'a=candidate:$type 1 $transport 2130706431 $ip $port typ host generation 0 network-id 1 network-cost 10';
  }
}

SdpMessage generateSdpOffer() {
  var candidate1 = SdpMediaCandidate(
    ip: "127.0.0.1",
    port: 4444, // Changed to port 4444
    type: "1591551051",
    transport: TransportType.udp,
  );
  var candidate2 = SdpMediaCandidate(
    ip: "127.0.0.1",
    port: 4444, // Changed to port 4444
    type: "538101459",
    transport: TransportType.udp,
  );

  var media = SdpMedia(
    mediaId: 0,
    type: MediaType.video,
    ufrag: "AHhu",
    pwd: "JRJiSJyYR1qr28k8ZJVXiDJH",
    fingerprintType: FingerprintType.sha256,
    fingerprintHash:
        "35:B9:06:BE:8A:DA:63:9A:1C:61:6D:DF:61:AF:D0:DA:E1:54:4B:FB:8E:B8:80:0F:9B:5E:3F:E5:92:98:A9:4A",
    candidates: [candidate1, candidate2],
    payloads:
        "96 97 103 104 107 108 109 114 115 116 117 118 39 40 45 46 98 99 100 101 119 120 123 124 125",
    rtpCodec: "VP8",
    extmaps: [
      "1 urn:ietf:params:rtp-hdrext:toffset",
      "2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time",
      "3 urn:3gpp:video-orientation"
    ],
    setup: "active",
    mid: "0",
  );

  return SdpMessage(
    conferenceName: "TestConference",
    sessionID: "5749109219785652925",
    mediaItems: [media],
  );
}

void main() {
  var sdpOffer = generateSdpOffer();
  print(sdpOffer);
}
