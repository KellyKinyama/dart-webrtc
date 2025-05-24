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

SdpMessage generateSdpAnswer(Map<String, dynamic> offer) {
  // Safe parsing for ICE credentials and fingerprint
  String iceUfrag = offer['sdp']
      .split('\r\n')
      .firstWhere((line) => line.startsWith('a=ice-ufrag:'), orElse: () => '')
      .split(':')
      .last
      .trim();
  String icePwd = offer['sdp']
      .split('\r\n')
      .firstWhere((line) => line.startsWith('a=ice-pwd:'), orElse: () => '')
      .split(':')
      .last
      .trim();
  String fingerprint = offer['sdp']
      .split('\r\n')
      .firstWhere((line) => line.startsWith('a=fingerprint:'), orElse: () => '')
      .split(' ')
      .last
      .trim();

  // Simulate ICE candidates and payloads for the answer
  var candidate1 = SdpMediaCandidate(
    ip: "127.0.0.1",
    port: 4444,
    type: CandidateType.host,
    transport: TransportType.udp,
  );

  var media = SdpMedia(
    mediaId: 0,
    type: MediaType.video,
    ufrag: iceUfrag,
    pwd: icePwd,
    fingerprintType: FingerprintType.sha256,
    fingerprintHash: fingerprint,
    candidates: [candidate1],
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
    sessionID: "8470111884785232115", // Keep the same session ID
    mediaItems: [media],
  );
}

void main() {
  // Simulate offer parsing (replace this with actual offer JSON)
  Map<String, dynamic> offer = {
    "type": "offer",
    "sdp":
        "v=0\r\no=- 8470111884785232115 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=group:BUNDLE 0\r\na=extmap-allow-mixed\r\na=msid-semantic: WMS 94e8a71a-c2d6-40e3-bf73-63217a27f19d\r\nm=video 59910 UDP/TLS/RTP/SAVPF 96 97 103 104 107 108 109 114 115 116 117 118 39 40 45 46 98 99 100 101 119 120 123 124 125\r\nc=IN IP4 10.100.53.172\r\na=rtcp:9 IN IP4 0.0.0.0\r\na=candidate:2357293033 1 udp 2122260223 10.100.53.172 59910 typ host generation 0 network-id 1 network-cost 10\r\na=ice-ufrag:w0CM\r\na=ice-pwd:PKh44DFsq19kq+uDSV6Pob3j\r\na=ice-options:trickle\r\na=fingerprint:sha-256 5C:1F:9A:EA:72:00:DB:5A:84:6C:D8:85:D7:53:83:BF:A5:5B:88:39:7D:B7:75:13:48:62:F3:07:EE:FD:88:B5\r\na=setup:actpass\r\na=mid:0\r\na=extmap:1 urn:ietf:params:rtp-hdrext:toffset\r\na=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\r\na=extmap:3 urn:3gpp:video-orientation\r\na=extmap:4 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\r\na=extmap:5 http://www.webrtc.org/experiments/rtp-hdrext/playout-delay\r\na=extmap:6 http://www.webrtc.org/experiments/rtp-hdrext/video-content-type\r\na=extmap:7 http://www.webrtc.org/experiments/rtp-hdrext/video-timing\r\na=extmap:8 http://www.webrtc.org/experiments/rtp-hdrext/color-space\r\na=extmap:9 urn:ietf:params:rtp-hdrext:sdes:mid\r\na=extmap:10 urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id\r\na=extmap:11 urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id\r\na=sendrecv\r\na=msid:94e8a71a-c2d6-40e3-bf73-63217a27f19d 09ebd0c1-4522-4ca7-aba1-cbb90c8aab72\r\na=rtcp-mux\r\na=rtcp-rsize\r\na=rtpmap:96 VP8/90000\r\na=rtcp-fb:96 goog-remb\r\na=rtcp-fb:96 transport-cc\r\na=rtcp-fb:96 ccm fir\r\na=rtcp-fb:96 nack\r\na=rtcp-fb:96 nack pli\r\na=rtpmap:97 rtx/90000\r\na=fmtp:97 apt=96\r\na=rtpmap:103 H264/90000\r\na=rtcp-fb:103 goog-remb\r\na=rtcp-fb:103 transport-cc\r\na=rtcp-fb:103 ccm fir\r\na=rtcp-fb:103 nack\r\na=rtcp-fb:103 nack pli\r\na=fmtp:103 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42001f\r\na=rtpmap:104 rtx/90000\r\na=fmtp:104 apt=103\r\na=rtpmap:107 H264/90000\r\na=rtcp-fb:107 goog-remb\r\na=rtcp-fb:107 transport-cc\r\na=rtcp-fb:107 ccm fir\r\na=rtcp-fb:107 nack\r\na=rtcp-fb:107 nack pli\r\na=fmtp:107 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42001f\r\na=rtpmap:108 rtx/90000\r\na=fmtp:108 apt=107\r\na=rtpmap:109 H264/90000\r\na=rtcp-fb:109 goog-remb\r\na=rtcp-fb:109 transport-cc\r\na=rtcp-fb:109 ccm fir\r\na=rtcp-fb:109 nack\r\na=rtcp-fb:109 nack pli\r\na=fmtp:109 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f\r\na=rtpmap:114 rtx/90000\r\na=fmtp:114 apt=109\r\na=rtpmap:115 H264/90000\r\na=rtcp-fb:115 goog-remb\r\na=rtcp-fb:115 transport-cc\r\na=rtcp-fb:115 ccm fir\r\na=rtcp-fb:115 nack\r\na=rtcp-fb:115 nack pli\r\na=fmtp:115 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42e01f\r\na=rtpmap:116 rtx/90000\r\na=fmtp:116 apt=115\r\na=rtpmap:117 H264/90000\r\na=rtcp-fb:117 goog-remb\r\na=rtcp-fb:117 transport-cc\r\na=rtcp-fb:117 ccm fir\r\na=rtcp-fb:117 nack\r\na=rtcp-fb:117 nack pli\r\na=fmtp:117 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=4d001f\r\na=rtpmap:118 rtx/90000\r\na=fmtp:118 apt=117\r\na=rtpmap:39 H264/90000\r\na=rtcp-fb:39 goog-remb\r\na=rtcp-fb:39 transport-cc\r\na=rtcp-fb:39 ccm fir\r\na=rtcp-fb:39 nack\r\na=rtcp-fb:39 nack pli\r\na=fmtp:39 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=4d001f\r\na=rtpmap:40 rtx/90000\r\na=fmtp:40 apt=39\r\na=rtpmap:45 AV1/90000\r\na=rtcp-fb:45 goog-remb\r\na=rtcp-fb:45 transport-cc\r\na=rtcp-fb:45 ccm fir\r\na=rtcp-fb:45 nack\r\na=rtcp-fb:45 nack pli\r\na=fmtp:45 level-idx=5;profile=0;tier=0\r\na=rtpmap:46 rtx/90000\r\na=fmtp:46 apt=45\r\na=rtpmap:98 VP9/90000\r\na=rtcp-fb:98 goog-remb\r\na=rtcp-fb:98 transport-cc\r\na=rtcp-fb:98 ccm fir\r\na=rtcp-fb:98 nack\r\na=rtcp-fb:98 nack pli\r\na=fmtp:98 profile-id=0\r\na=rtpmap:99 rtx/90000\r\na=fmtp:99 apt=98\r\na=rtpmap:100 VP9/90000\r\na=rtcp-fb:100 goog-remb\r\na=rtcp-fb:100 transport-cc\r\na=rtcp-fb:100 ccm fir\r\na=rtcp-fb:100 nack\r\na=rtcp-fb:100 nack pli\r\na=fmtp:100 profile-id=2\r\na=rtpmap:101 rtx/90000\r\na=fmtp:101 apt=100\r\na=rtpmap:119 H264/90000\r\na=rtcp-fb:119 goog-remb\r\na=rtcp-fb:119 transport-cc\r\na=rtcp-fb:119 ccm fir\r\na=rtcp-fb:119 nack\r\na=rtcp-fb:119 nack pli\r\na=fmtp:119 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=64001f\r\na=rtpmap:120 rtx/90000\r\na=fmtp:120 apt=119\r\na=rtpmap:123 red/90000\r\na=rtpmap:124 rtx/90000\r\na=fmtp:124 apt=123\r\na=rtpmap:125 ulpfec/90000\r\na=ssrc-group:FID 676863502 166851119\r\na=ssrc:676863502 cname:aILbs6Vl5bcASzby\r\na=ssrc:676863502 msid:94e8a71a-c2d6-40e3-bf73-63217a27f19d 09ebd0c1-4522-4ca7-aba1-cbb90c8aab72\r\na=ssrc:166851119 cname:aILbs6Vl5bcASzby\r\na=ssrc:166851119 msid:94e8a71a-c2d6-40e3-bf73-63217a27f19d 09ebd0c1-4522-4ca7-aba1-cbb90c8aab72\r\n"
  };

  var sdpAnswer = generateSdpAnswer(offer);
  print(sdpAnswer);
}
