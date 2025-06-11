import 'package:sdp_transform/sdp_transform.dart';

final sdpOffer = {
  "type": "offer",
  "sdp":
      "v=0\r\no=- 3822856948944450794 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=group:BUNDLE 0 1\r\na=extmap-allow-mixed\r\na=msid-semantic: WMS 84f453ca-0dbd-4d92-8eec-6b671c88f990\r\nm=audio 51584 UDP/TLS/RTP/SAVPF 111 63 9 0 8 13 110 126\r\nc=IN IP4 102.67.160.2\r\na=rtcp:9 IN IP4 0.0.0.0\r\na=candidate:4057065925 1 udp 2122260223 172.22.16.1 51582 typ host generation 0 network-id 1\r\na=candidate:3027289326 1 udp 2122194687 192.168.56.1 51583 typ host generation 0 network-id 3\r\na=candidate:2359944424 1 udp 2122129151 10.100.53.194 51584 typ host generation 0 network-id 2 network-cost 10\r\na=candidate:259734865 1 tcp 1518280447 172.22.16.1 9 typ host tcptype active generation 0 network-id 1\r\na=candidate:1255805050 1 tcp 1518214911 192.168.56.1 9 typ host tcptype active generation 0 network-id 3\r\na=candidate:1912811644 1 tcp 1518149375 10.100.53.194 9 typ host tcptype active generation 0 network-id 2 network-cost 10\r\na=candidate:1298641826 1 udp 1685921535 102.67.160.2 51584 typ srflx raddr 10.100.53.194 rport 51584 generation 0 network-id 2 network-cost 10\r\na=ice-ufrag:OaAE\r\na=ice-pwd:x/xqQ5Oiwcn41g5m7kUJ3O2+\r\na=ice-options:trickle\r\na=fingerprint:sha-256 4F:AC:D4:CF:2C:76:3A:A1:B8:1B:F3:83:31:2F:C5:BC:30:21:E0:A4:44:DE:2D:81:B9:BB:99:BC:91:7F:8A:39\r\na=setup:actpass\r\na=mid:0\r\na=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level\r\na=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\r\na=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\r\na=extmap:4 urn:ietf:params:rtp-hdrext:sdes:mid\r\na=sendrecv\r\na=msid:84f453ca-0dbd-4d92-8eec-6b671c88f990 660e6102-24a7-43a5-9e01-a733f091341d\r\na=rtcp-mux\r\na=rtcp-rsize\r\na=rtpmap:111 opus/48000/2\r\na=rtcp-fb:111 transport-cc\r\na=fmtp:111 minptime=10;useinbandfec=1\r\na=rtpmap:63 red/48000/2\r\na=fmtp:63 111/111\r\na=rtpmap:9 G722/8000\r\na=rtpmap:0 PCMU/8000\r\na=rtpmap:8 PCMA/8000\r\na=rtpmap:13 CN/8000\r\na=rtpmap:110 telephone-event/48000\r\na=rtpmap:126 telephone-event/8000\r\na=ssrc:1227153705 cname:tcfYxii359Px+p5/\r\na=ssrc:1227153705 msid:84f453ca-0dbd-4d92-8eec-6b671c88f990 660e6102-24a7-43a5-9e01-a733f091341d\r\nm=video 51587 UDP/TLS/RTP/SAVPF 96 97 103 104 107 108 109 114 115 116 117 118 39 40 45 46 98 99 100 101 119 120 49 50 123 124 125\r\nc=IN IP4 102.67.160.2\r\na=rtcp:9 IN IP4 0.0.0.0\r\na=candidate:4057065925 1 udp 2122260223 172.22.16.1 51585 typ host generation 0 network-id 1\r\na=candidate:3027289326 1 udp 2122194687 192.168.56.1 51586 typ host generation 0 network-id 3\r\na=candidate:2359944424 1 udp 2122129151 10.100.53.194 51587 typ host generation 0 network-id 2 network-cost 10\r\na=candidate:259734865 1 tcp 1518280447 172.22.16.1 9 typ host tcptype active generation 0 network-id 1\r\na=candidate:1255805050 1 tcp 1518214911 192.168.56.1 9 typ host tcptype active generation 0 network-id 3\r\na=candidate:1912811644 1 tcp 1518149375 10.100.53.194 9 typ host tcptype active generation 0 network-id 2 network-cost 10\r\na=candidate:1298641826 1 udp 1685921535 102.67.160.2 51587 typ srflx raddr 10.100.53.194 rport 51587 generation 0 network-id 2 network-cost 10\r\na=ice-ufrag:OaAE\r\na=ice-pwd:x/xqQ5Oiwcn41g5m7kUJ3O2+\r\na=ice-options:trickle\r\na=fingerprint:sha-256 4F:AC:D4:CF:2C:76:3A:A1:B8:1B:F3:83:31:2F:C5:BC:30:21:E0:A4:44:DE:2D:81:B9:BB:99:BC:91:7F:8A:39\r\na=setup:actpass\r\na=mid:1\r\na=extmap:14 urn:ietf:params:rtp-hdrext:toffset\r\na=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\r\na=extmap:13 urn:3gpp:video-orientation\r\na=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\r\na=extmap:5 http://www.webrtc.org/experiments/rtp-hdrext/playout-delay\r\na=extmap:6 http://www.webrtc.org/experiments/rtp-hdrext/video-content-type\r\na=extmap:7 http://www.webrtc.org/experiments/rtp-hdrext/video-timing\r\na=extmap:8 http://www.webrtc.org/experiments/rtp-hdrext/color-space\r\na=extmap:4 urn:ietf:params:rtp-hdrext:sdes:mid\r\na=extmap:10 urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id\r\na=extmap:11 urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id\r\na=sendrecv\r\na=msid:84f453ca-0dbd-4d92-8eec-6b671c88f990 7d0980a9-b60d-4ccc-a31c-2e148fb0b1fd\r\na=rtcp-mux\r\na=rtcp-rsize\r\na=rtpmap:96 VP8/90000\r\na=rtcp-fb:96 goog-remb\r\na=rtcp-fb:96 transport-cc\r\na=rtcp-fb:96 ccm fir\r\na=rtcp-fb:96 nack\r\na=rtcp-fb:96 nack pli\r\na=rtpmap:97 rtx/90000\r\na=fmtp:97 apt=96\r\na=rtpmap:103 H264/90000\r\na=rtcp-fb:103 goog-remb\r\na=rtcp-fb:103 transport-cc\r\na=rtcp-fb:103 ccm fir\r\na=rtcp-fb:103 nack\r\na=rtcp-fb:103 nack pli\r\na=fmtp:103 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42001f\r\na=rtpmap:104 rtx/90000\r\na=fmtp:104 apt=103\r\na=rtpmap:107 H264/90000\r\na=rtcp-fb:107 goog-remb\r\na=rtcp-fb:107 transport-cc\r\na=rtcp-fb:107 ccm fir\r\na=rtcp-fb:107 nack\r\na=rtcp-fb:107 nack pli\r\na=fmtp:107 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42001f\r\na=rtpmap:108 rtx/90000\r\na=fmtp:108 apt=107\r\na=rtpmap:109 H264/90000\r\na=rtcp-fb:109 goog-remb\r\na=rtcp-fb:109 transport-cc\r\na=rtcp-fb:109 ccm fir\r\na=rtcp-fb:109 nack\r\na=rtcp-fb:109 nack pli\r\na=fmtp:109 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f\r\na=rtpmap:114 rtx/90000\r\na=fmtp:114 apt=109\r\na=rtpmap:115 H264/90000\r\na=rtcp-fb:115 goog-remb\r\na=rtcp-fb:115 transport-cc\r\na=rtcp-fb:115 ccm fir\r\na=rtcp-fb:115 nack\r\na=rtcp-fb:115 nack pli\r\na=fmtp:115 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42e01f\r\na=rtpmap:116 rtx/90000\r\na=fmtp:116 apt=115\r\na=rtpmap:117 H264/90000\r\na=rtcp-fb:117 goog-remb\r\na=rtcp-fb:117 transport-cc\r\na=rtcp-fb:117 ccm fir\r\na=rtcp-fb:117 nack\r\na=rtcp-fb:117 nack pli\r\na=fmtp:117 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=4d001f\r\na=rtpmap:118 rtx/90000\r\na=fmtp:118 apt=117\r\na=rtpmap:39 H264/90000\r\na=rtcp-fb:39 goog-remb\r\na=rtcp-fb:39 transport-cc\r\na=rtcp-fb:39 ccm fir\r\na=rtcp-fb:39 nack\r\na=rtcp-fb:39 nack pli\r\na=fmtp:39 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=4d001f\r\na=rtpmap:40 rtx/90000\r\na=fmtp:40 apt=39\r\na=rtpmap:45 AV1/90000\r\na=rtcp-fb:45 goog-remb\r\na=rtcp-fb:45 transport-cc\r\na=rtcp-fb:45 ccm fir\r\na=rtcp-fb:45 nack\r\na=rtcp-fb:45 nack pli\r\na=fmtp:45 level-idx=5;profile=0;tier=0\r\na=rtpmap:46 rtx/90000\r\na=fmtp:46 apt=45\r\na=rtpmap:98 VP9/90000\r\na=rtcp-fb:98 goog-remb\r\na=rtcp-fb:98 transport-cc\r\na=rtcp-fb:98 ccm fir\r\na=rtcp-fb:98 nack\r\na=rtcp-fb:98 nack pli\r\na=fmtp:98 profile-id=0\r\na=rtpmap:99 rtx/90000\r\na=fmtp:99 apt=98\r\na=rtpmap:100 VP9/90000\r\na=rtcp-fb:100 goog-remb\r\na=rtcp-fb:100 transport-cc\r\na=rtcp-fb:100 ccm fir\r\na=rtcp-fb:100 nack\r\na=rtcp-fb:100 nack pli\r\na=fmtp:100 profile-id=2\r\na=rtpmap:101 rtx/90000\r\na=fmtp:101 apt=100\r\na=rtpmap:119 H264/90000\r\na=rtcp-fb:119 goog-remb\r\na=rtcp-fb:119 transport-cc\r\na=rtcp-fb:119 ccm fir\r\na=rtcp-fb:119 nack\r\na=rtcp-fb:119 nack pli\r\na=fmtp:119 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=64001f\r\na=rtpmap:120 rtx/90000\r\na=fmtp:120 apt=119\r\na=rtpmap:49 H265/90000\r\na=rtcp-fb:49 goog-remb\r\na=rtcp-fb:49 transport-cc\r\na=rtcp-fb:49 ccm fir\r\na=rtcp-fb:49 nack\r\na=rtcp-fb:49 nack pli\r\na=fmtp:49 level-id=93;profile-id=1;tier-flag=0;tx-mode=SRST\r\na=rtpmap:50 rtx/90000\r\na=fmtp:50 apt=49\r\na=rtpmap:123 red/90000\r\na=rtpmap:124 rtx/90000\r\na=fmtp:124 apt=123\r\na=rtpmap:125 ulpfec/90000\r\na=ssrc-group:FID 3746892314 822236710\r\na=ssrc:3746892314 cname:tcfYxii359Px+p5/\r\na=ssrc:3746892314 msid:84f453ca-0dbd-4d92-8eec-6b671c88f990 7d0980a9-b60d-4ccc-a31c-2e148fb0b1fd\r\na=ssrc:822236710 cname:tcfYxii359Px+p5/\r\na=ssrc:822236710 msid:84f453ca-0dbd-4d92-8eec-6b671c88f990 7d0980a9-b60d-4ccc-a31c-2e148fb0b1fd\r\n"
};

void main() {
  final offer = parse(sdpOffer['sdp']!);

  print("offer: $offer");

  final answer = {
    "origin": {
      "username": 'a_user',
      "sessionId": offer["origin"]?["sessionId"],
      "sessionVersion": 2,
      "netType": "IN",
      "ipVer": 4,
      "address": '127.0.0.1'
    },
    "timing": {"start": 0, "stop": 0},
    "setup": 'actpass',
    "iceOptions": 'trickle',
    "media": (offer["media"] as List<dynamic>).map((mediaItemDynamic) {
      final Map<String, dynamic> mediaItem =
          mediaItemDynamic as Map<String, dynamic>;
      return {
        "mid": mediaItem["mid"].toString(),
        "type": mediaItem["type"],
        "port": 9,
        "rtcpMux": 'rtcp-mux',
        "protocol": 'UDP/TLS/RTP/SAVPF',
        "payloads": mediaItem["payloads"],
        "connection": {"version": 4, "ip": '0.0.0.0'},
        "iceUfrag": mediaItem["iceUfrag"],
        "icePwd": mediaItem["icePwd"],
        "fingerprint": {
          "type": mediaItem["fingerprint"]?["type"],
          "hash": mediaItem["fingerprint"]?["hash"],
        },
        "candidates":
            (mediaItem["candidates"] as List<dynamic>).map((candidateDynamic) {
          final Map<String, dynamic> candidate =
              candidateDynamic as Map<String, dynamic>;
          return {
            "foundation": '0',
            "component": 1,
            "transport": candidate["transport"],
            "priority": 2113667327,
            "ip": candidate["ip"],
            "port": candidate["port"],
            "type": candidate["type"]
          };
        }).toList(),
        "rtp": [
          {
            "payload":
                int.parse(mediaItem["rtp"]?[0]?["payload"]?.toString() ?? '0'),
            "codec": mediaItem["rtp"]?[0]?["codec"],
          }
        ],
        "fmtp": []
      };
    }).toList()
  };

  // print(answer);
}
