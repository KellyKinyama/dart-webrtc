import 'package:dartls/src/sdp/sdp_transform.dart';

final sdpOfferMap = {
  "version": 0,
  "origin": {
    "username": "-",
    "sessionId": "4215775240449105457",
    "sessionVersion": 2,
    "netType": "IN",
    "ipVer": 4,
    "address": "127.0.0.1"
  },
  "name": "-",
  "timing": {"start": 0, "stop": 0},
  // "groups": [
  //   {"type": "BUNDLE", "mids": "0 1"}
  // ],
  // "extmapAllowMixed": [
  //   {"extmap-allow-mixed": "extmap-allow-mixed"}
  // ],
  // "msidSemantic": {
  //   "semantic": "WMS",
  //   "token": "160d6347-77ea-40b8-aded-2b586daf50ea"
  // },
  "media": [
    {
      "rtp": [
        //   {"payload": 111, "codec": "opus", "rate": 48000, "encoding": 2},
        //  {"payload": 63, "codec": red, "rate": 48000, "encoding": 2},
        //  {"payload": 9, "codec": "G722", "rate": 8000, "encoding": null},
        //  {payload: 0, codec: PCMU, rate: 8000, encoding: null},
        {"payload": 8, "codec": "PCMA", "rate": 8000, "encoding": null},
        //  {payload: 13, codec: CN, rate: 8000, encoding: null},
        //  {payload: 110, codec: telephone-event, rate: 48000, encoding: null},
        // {payload: 126, codec: telephone-event, rate: 8000, encoding: null}
      ],
      "fmtp": [
        // {"payload": 111, "config": "minptime=10;useinbandfec=1"},
        // {"payload": 63, "config": "111/111"}
      ],
      "type": "audio",
      // "port":9,
      "port": 4444,
      "protocol": "UDP/TLS/RTP/SAVPF",
      "payloads": "111 63 9 0 8 13 110 126",
      "connection": {"version": 4, "ip": "127.0.0.1"},
      // "rtcp": {"port": 9, "netType": "IN", "ipVer": 4, "address": "0.0.0.0"},
      "iceUfrag": "yxYb",
      "icePwd": "05iMxO9GujD2fUWXSoi0ByNd",
      // "iceOptions": "trickle",
      "fingerprint": {
        "type": "sha-256",
        "hash":
            "B4:C4:F9:49:A6:5A:11:49:3E:66:BD:1F:B3:43:E3:54:A9:3E:1D:11:71:5B:E0:4D:5F:F4:BC:D2:19:3B:84:E5"
      },
      "setup": "actpass",
      "mid": 0.toString(),
      // "ext": [
      //   {
      //     "value": 1,
      //     "direction": null,
      //     "uri": "urn:ietf:params:rtp-hdrext:ssrc-audio-level",
      //     "config": null
      //   },
      //   {
      //     "value": 2,
      //     "direction": null,
      //     "uri": "http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time",
      //     "config": null
      //   },
      //   {
      //     "value": 3,
      //     "direction": null,
      //     "uri":
      //         "http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01",
      //     "config": null
      //   },
      //   {
      //     "value": 4,
      //     "direction": null,
      //     "uri": "urn:ietf:params:rtp-hdrext:sdes:mid",
      //     "config": null
      //   }
      // ],
      // "direction": "sendrecv",
      // "msid":
      //     "160d6347-77ea-40b8-aded-2b586daf50ea ebe4768c-cec1-4e71-bc80-099c1e6c1f10",
      "rtcpMux": "rtcp-mux",
      // "rtcpFb": [
      //   {"payload": 111, "type": "transport-cc", "subtype": null}
      // ],
      // "ssrcs": [
      //   {"id": "3485940486", "attribute": "cname", "value": "Dm9nmXDg4q8eNPqz"},
      //   {
      //     "id": "3485940486",
      //     "attribute": "msid",
      //     "value":
      //         "160d6347-77ea-40b8-aded-2b586daf50ea ebe4768c-cec1-4e71-bc80-099c1e6c1f10"
      //   }
      // ]
    },
    {
      "rtp": [
        {"payload": 96, "codec": "VP8", "rate": "90000", "encoding": null},
      ],
      "fmtp": [
        // {"payload": 111, "config": "minptime=10;useinbandfec=1"},
        // {"payload": 63, "config": "111/111"}
      ],
      "type": "video",
      "port": 4444,
      "protocol": "UDP/TLS/RTP/SAVPF",
      "payloads": "96",
      "connection": {"version": 4, "ip": "127.0.0.1"},
      // "rtcp": {"port": 9, "netType": "IN", "ipVer": 4, "address": "0.0.0.0"},
      "iceUfrag": "yxYb",
      "icePwd": "05iMxO9GujD2fUWXSoi0ByNd",
      // "iceOptions": "trickle",
      "fingerprint": {
        "type": "sha-256",
        "hash":
            "B4:C4:F9:49:A6:5A:11:49:3E:66:BD:1F:B3:43:E3:54:A9:3E:1D:11:71:5B:E0:4D:5F:F4:BC:D2:19:3B:84:E5"
      },
      "setup": "actpass",
      "mid": 1.toString(),
      "rtcpMux": "rtcp-mux",
    }
  ]
};

void main() {
  print(write(sdpOfferMap, null));
}
