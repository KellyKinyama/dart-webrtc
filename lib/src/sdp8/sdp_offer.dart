import 'package:dartls/src/sdp8/server_agent.dart';

import '../sdp/sdp_transform.dart';
import 'sdp.dart';

String generateSdpOffer() {
  final offferMap = {
    "origin": {
      "username": 'a_user',
      "sessionId": "1234",
      "sessionVersion": 2,
      "netType": "IN",
      "ipVer": 4,
      "address": '127.0.0.1'
    },
    "timing": {"start": 0, "stop": 0},
    "setup": 'actpass',
    "iceOptions": 'trickle',
    "media": [
      {
        "mid": 0.toString(),
        "type": MediaType.video.toString(),
        "port": 9,
        "rtcpMux": 'rtcp-mux',
        "protocol": 'UDP/TLS/RTP/SAVPF',
        "payloads": 'VP8/90000',
        "connection": {"version": 4, "ip": '0.0.0.0'},
        "iceUfrag": generateICEUfrag(),
        "icePwd": generateICEPwd(),
        "fingerprint": {
          "type": FingerprintType.sha_256.toString(),
          "hash": "mediaItem.fingerprintHash",
        },
        "candidates": [
          {
            "foundation": '0',
            "component": 1,
            "transport": TransportType.udp.toString(),
            "priority": 2113667327,
            "ip": "0.0.0.0",
            "port": "56093",
            "type": CandidateType.host.toString()
          }
        ],
        "rtp": [
          {
            "payload": int.parse("96"),
            "codec": 'VP8/90000',
          }
        ],
        "fmtp": []
      }
    ],
  };

  // final media= {
  //                           "mid": mediaItem.mediaId.toString(),
  //                           "type": mediaItem.type,
  //                           port: 9,
  //                           rtcpMux: 'rtcp-mux',
  //                           protocol: 'UDP/TLS/RTP/SAVPF',
  //                           payloads: mediaItem.payloads,
  //                           connection: {
  //                               version: 4,
  //                               ip: '0.0.0.0'
  //                           },
  //                           iceUfrag: mediaItem.ufrag,
  //                           icePwd: mediaItem.pwd,
  //                           fingerprint: {
  //                               type: mediaItem.fingerprintType,
  //                               hash: mediaItem.fingerprintHash,
  //                           },
  //                           candidates: mediaItem.candidates.map(candidate => {
  //                               return {
  //                                   foundation: '0',
  //                                   component: 1,
  //                                   transport: candidate.transport,
  //                                   priority: 2113667327,
  //                                   ip: candidate.ip,
  //                                   port: candidate.port,
  //                                   type: candidate.type
  //                               };
  //                           }),

  //                           rtp: [{
  //                               payload: parseInt(mediaItem.payloads),
  //                               codec: mediaItem.rtpCodec,
  //                           }],
  //                           fmtp: []
  //                       };

  print("offer media: ${offferMap['media']}");

  final offer = write(offferMap, null);

  return offer;
}

void main() {
  print("Sdp offer: ${generateSdpOffer()}");
}
