import 'dart:convert';

import 'package:sdp_transform/sdp_transform.dart'; // For jsonEncode to pretty-print the map

void main() {
  // This is your provided offer template, which we'll use as the input.
  final Map<String, dynamic> offerTemplate = {
    'version': 0,
    'origin': {
      'username': '-',
      'sessionId': '3822856948944450794',
      'sessionVersion': 2,
      'netType': 'IN',
      'ipVer': 4,
      'address': '127.0.0.1'
    },
    'name': '-',
    'timing': {'start': 0, 'stop': 0},
    'groups': [
      {'type': 'BUNDLE', 'mids': '0 1'}
    ],
    'extmapAllowMixed': [
      {'extmap-allow-mixed': 'extmap-allow-mixed'}
    ],
    'msidSemantic': {
      'semantic': 'WMS',
      'token': '84f453ca-0dbd-4d92-8eec-6b671c88f990'
    },
    'media': [
      {
        'rtp': [
          {'payload': 111, 'codec': 'opus', 'rate': 48000, 'encoding': 2},
          {'payload': 63, 'codec': 'red', 'rate': 48000, 'encoding': 2},
          {'payload': 9, 'codec': 'G722', 'rate': 8000, 'encoding': null},
          {'payload': 0, 'codec': 'PCMU', 'rate': 8000, 'encoding': null},
          {'payload': 8, 'codec': 'PCMA', 'rate': 8000, 'encoding': null},
          {'payload': 13, 'codec': 'CN', 'rate': 8000, 'encoding': null},
          {
            'payload': 110,
            'codec': 'telephone-event',
            'rate': 48000,
            'encoding': null
          },
          {
            'payload': 126,
            'codec': 'telephone-event',
            'rate': 8000,
            'encoding': null
          }
        ],
        'fmtp': [
          {'payload': 111, 'config': 'minptime=10;useinbandfec=1'},
          {'payload': 63, 'config': '111/111'}
        ],
        'type': 'audio',
        'port': 51584,
        'protocol': 'UDP/TLS/RTP/SAVPF',
        'payloads': '111 63 9 0 8 13 110 126',
        'connection': {'version': 4, 'ip': '102.67.160.2'},
        'rtcp': {'port': 9, 'netType': 'IN', 'ipVer': 4, 'address': '0.0.0.0'},
        'candidates': [
          {
            'foundation': '4057065925',
            'component': 1,
            'transport': 'udp',
            'priority': 2122260223,
            'ip': '172.22.16.1',
            'port': 51582,
            'type': 'host',
            'raddr': null,
            'rport': null,
            'tcptype': null,
            'generation': 0,
            'network-id': 1,
            'network-cost': null
          },
          {
            'foundation': '3027289326',
            'component': 1,
            'transport': 'udp',
            'priority': 2122194687,
            'ip': '192.168.56.1',
            'port': 51583,
            'type': 'host',
            'raddr': null,
            'rport': null,
            'tcptype': null,
            'generation': 0,
            'network-id': 3,
            'network-cost': null
          },
          {
            'foundation': '2359944424',
            'component': 1,
            'transport': 'udp',
            'priority': 2122129151,
            'ip': '10.100.53.194',
            'port': 51584,
            'type': 'host',
            'raddr': null,
            'rport': null,
            'tcptype': null,
            'generation': 0,
            'network-id': 2,
            'network-cost': 10
          },
          {
            'foundation': '259734865',
            'component': 1,
            'transport': 'tcp',
            'priority': 1518280447,
            'ip': '172.22.16.1',
            'port': 9,
            'type': 'host',
            'raddr': null,
            'rport': null,
            'tcptype': 'active',
            'generation': 0,
            'network-id': 1,
            'network-cost': null
          },
          {
            'foundation': '1255805050',
            'component': 1,
            'transport': 'tcp',
            'priority': 1518214911,
            'ip': '192.168.56.1',
            'port': 9,
            'type': 'host',
            'raddr': null,
            'rport': null,
            'tcptype': 'active',
            'generation': 0,
            'network-id': 3,
            'network-cost': null
          },
          {
            'foundation': '1912811644',
            'component': 1,
            'transport': 'tcp',
            'priority': 1518149375,
            'ip': '10.100.53.194',
            'port': 9,
            'type': 'host',
            'raddr': null,
            'rport': null,
            'tcptype': 'active',
            'generation': 0,
            'network-id': 2,
            'network-cost': 10
          },
          {
            'foundation': '1298641826',
            'component': 1,
            'transport': 'udp',
            'priority': 1685921535,
            'ip': '102.67.160.2',
            'port': 51584,
            'type': 'srflx',
            'raddr': '10.100.53.194',
            'rport': 51584,
            'tcptype': null,
            'generation': 0,
            'network-id': 2,
            'network-cost': 10
          }
        ],
        'iceUfrag': 'OaAE',
        'icePwd': 'x/xqQ5Oiwcn41g5m7kUJ3O2+',
        'iceOptions': 'trickle',
        'fingerprint': {
          'type': 'sha-256',
          'hash':
              '4F:AC:D4:CF:2C:76:3A:A1:B8:1B:F3:83:31:2F:C5:BC:30:21:E0:A4:44:DE:2D:81:B9:BB:99:BC:91:7F:8A:39'
        },
        'setup': 'actpass',
        'mid': '0',
        'ext': [
          {
            'value': 1,
            'direction': null,
            'uri': 'urn:ietf:params:rtp-hdrext:ssrc-audio-level',
            'config': null
          },
          {
            'value': 2,
            'direction': null,
            'uri': 'http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time',
            'config': null
          },
          {
            'value': 3,
            'direction': null,
            'uri':
                'http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01',
            'config': null
          },
          {
            'value': 4,
            'direction': null,
            'uri': 'urn:ietf:params:rtp-hdrext:sdes:mid',
            'config': null
          }
        ],
        'direction': 'sendrecv',
        'msid':
            '84f453ca-0dbd-4d92-8eec-6b671c88f990 660e6102-24a7-43a5-9e01-a733f091341d',
        'rtcpMux': 'rtcp-mux',
        'rtcpRsize': 'rtcp-rsize',
        'rtcpFb': [
          {'payload': 111, 'type': 'transport-cc', 'subtype': null}
        ],
        'ssrcs': [
          {'id': 1227153705, 'attribute': 'cname', 'value': 'tcfYxii359Px+p5/'},
          {
            'id': 1227153705,
            'attribute': 'msid',
            'value':
                '84f453ca-0dbd-4d92-8eec-6b671c88f990 660e6102-24a7-43a5-9e01-a733f091341d'
          }
        ]
      },
      {
        'rtp': [
          {'payload': 96, 'codec': 'VP8', 'rate': 90000, 'encoding': null},
          {'payload': 97, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
          {'payload': 103, 'codec': 'H264', 'rate': 90000, 'encoding': null},
          {'payload': 104, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
          {'payload': 107, 'codec': 'H264', 'rate': 90000, 'encoding': null},
          {'payload': 108, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
          {'payload': 109, 'codec': 'H264', 'rate': 90000, 'encoding': null},
          {'payload': 114, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
          {'payload': 115, 'codec': 'H264', 'rate': 90000, 'encoding': null},
          {'payload': 116, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
          {'payload': 117, 'codec': 'H264', 'rate': 90000, 'encoding': null},
          {'payload': 118, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
          {'payload': 39, 'codec': 'H264', 'rate': 90000, 'encoding': null},
          {'payload': 40, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
          {'payload': 45, 'codec': 'AV1', 'rate': 90000, 'encoding': null},
          {'payload': 46, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
          {'payload': 98, 'codec': 'VP9', 'rate': 90000, 'encoding': null},
          {'payload': 99, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
          {'payload': 100, 'codec': 'VP9', 'rate': 90000, 'encoding': null},
          {'payload': 101, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
          {'payload': 119, 'codec': 'H264', 'rate': 90000, 'encoding': null},
          {'payload': 120, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
          {'payload': 49, 'codec': 'H265', 'rate': 90000, 'encoding': null},
          {'payload': 50, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
          {'payload': 123, 'codec': 'red', 'rate': 90000, 'encoding': null},
          {'payload': 124, 'codec': 'rtx', 'rate': 90000, 'encoding': null},
          {'payload': 125, 'codec': 'ulfec', 'rate': 90000, 'encoding': null}
        ],
        'fmtp': [
          {'payload': 97, 'config': 'apt=96'},
          {
            'payload': 103,
            'config':
                'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42001f'
          },
          {'payload': 104, 'config': 'apt=103'},
          {
            'payload': 107,
            'config':
                'level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42001f'
          },
          {'payload': 108, 'config': 'apt=107'},
          {
            'payload': 109,
            'config':
                'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f'
          },
          {'payload': 114, 'config': 'apt=109'},
          {
            'payload': 115,
            'config':
                'level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42e01f'
          },
          {'payload': 116, 'config': 'apt=115'},
          {
            'payload': 117,
            'config':
                'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=4d001f'
          },
          {'payload': 118, 'config': 'apt=117'},
          {
            'payload': 39,
            'config':
                'level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=4d001f'
          },
          {'payload': 40, 'config': 'apt=39'},
          {'payload': 45, 'config': 'level-idx=5;profile=0;tier=0'},
          {'payload': 46, 'config': 'apt=45'},
          {'payload': 98, 'config': 'profile-id=0'},
          {'payload': 99, 'config': 'apt=98'},
          {'payload': 100, 'config': 'profile-id=2'},
          {'payload': 101, 'config': 'apt=100'},
          {
            'payload': 119,
            'config':
                'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=64001f'
          },
          {'payload': 120, 'config': 'apt=119'},
          {
            'payload': 49,
            'config': 'level-id=93;profile-id=1;tier-flag=0;tx-mode=SRST'
          },
          {'payload': 50, 'config': 'apt=49'},
          {'payload': 124, 'config': 'apt=123'}
        ],
        'type': 'video',
        'port': 51587,
        'protocol': 'UDP/TLS/RTP/SAVPF',
        'payloads':
            '96 97 103 104 107 108 109 114 115 116 117 118 39 40 45 46 98 99 100 101 119 120 49 50 123 124 125',
        'connection': {'version': 4, 'ip': '102.67.160.2'},
        'rtcp': {'port': 9, 'netType': 'IN', 'ipVer': 4, 'address': '0.0.0.0'},
        'candidates': [
          {
            'foundation': '4057065925',
            'component': 1,
            'transport': 'udp',
            'priority': 2122260223,
            'ip': '172.22.16.1',
            'port': 51585,
            'type': 'host',
            'raddr': null,
            'rport': null,
            'tcptype': null,
            'generation': 0,
            'network-id': 1,
            'network-cost': null
          },
          {
            'foundation': '3027289326',
            'component': 1,
            'transport': 'udp',
            'priority': 2122194687,
            'ip': '192.168.56.1',
            'port': 51586,
            'type': 'host',
            'raddr': null,
            'rport': null,
            'tcptype': null,
            'generation': 0,
            'network-id': 3,
            'network-cost': null
          },
          {
            'foundation': '2359944424',
            'component': 1,
            'transport': 'udp',
            'priority': 2122129151,
            'ip': '10.100.53.194',
            'port': 51587,
            'type': 'host',
            'raddr': null,
            'rport': null,
            'tcptype': null,
            'generation': 0,
            'network-id': 2,
            'network-cost': 10
          },
          {
            'foundation': '259734865',
            'component': 1,
            'transport': 'tcp',
            'priority': 1518280447,
            'ip': '172.22.16.1',
            'port': 9,
            'type': 'host',
            'raddr': null,
            'rport': null,
            'tcptype': 'active',
            'generation': 0,
            'network-id': 1,
            'network-cost': null
          },
          {
            'foundation': '1255805050',
            'component': 1,
            'transport': 'tcp',
            'priority': 1518214911,
            'ip': '192.168.56.1',
            'port': 9,
            'type': 'host',
            'raddr': null,
            'rport': null,
            'tcptype': 'active',
            'generation': 0,
            'network-id': 3,
            'network-cost': null
          },
          {
            'foundation': '1912811644',
            'component': 1,
            'transport': 'tcp',
            'priority': 1518149375,
            'ip': '10.100.53.194',
            'port': 9,
            'type': 'host',
            'raddr': null,
            'rport': null,
            'tcptype': 'active',
            'generation': 0,
            'network-id': 2,
            'network-cost': 10
          },
          {
            'foundation': '1298641826',
            'component': 1,
            'transport': 'udp',
            'priority': 1685921535,
            'ip': '102.67.160.2',
            'port': 51587,
            'type': 'srflx',
            'raddr': '10.100.53.194',
            'rport': 51587,
            'tcptype': null,
            'generation': 0,
            'network-id': 2,
            'network-cost': 10
          }
        ],
        'iceUfrag': 'OaAE',
        'icePwd': 'x/xqQ5Oiwcn41g5m7kUJ3O2+',
        'iceOptions': 'trickle',
        'fingerprint': {
          'type': 'sha-256',
          'hash':
              '4F:AC:D4:CF:2C:76:3A:A1:B8:1B:F3:83:31:2F:C5:BC:30:21:E0:A4:44:DE:2D:81:B9:BB:99:BC:91:7F:8A:39'
        },
        'setup': 'actpass',
        'mid': '1',
        'ext': [
          {
            'value': 14,
            'direction': null,
            'uri': 'urn:ietf:params:rtp-hdrext:toffset',
            'config': null
          },
          {
            'value': 2,
            'direction': null,
            'uri': 'http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time',
            'config': null
          },
          {
            'value': 13,
            'direction': null,
            'uri': 'urn:3gpp:video-orientation',
            'config': null
          },
          {
            'value': 3,
            'direction': null,
            'uri':
                'http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01',
            'config': null
          },
          {
            'value': 5,
            'direction': null,
            'uri': 'http://www.webrtc.org/experiments/rtp-hdrext/playout-delay',
            'config': null
          },
          {
            'value': 6,
            'direction': null,
            'uri':
                'http://www.webrtc.org/experiments/rtp-hdrext/video-content-type',
            'config': null
          },
          {
            'value': 7,
            'direction': null,
            'uri': 'http://www.webrtc.org/experiments/rtp-hdrext/video-timing',
            'config': null
          },
          {
            'value': 8,
            'direction': null,
            'uri': 'http://www.webrtc.org/experiments/rtp-hdrext/color-space',
            'config': null
          },
          {
            'value': 4,
            'direction': null,
            'uri': 'urn:ietf:params:rtp-hdrext:sdes:mid',
            'config': null
          },
          {
            'value': 10,
            'direction': null,
            'uri': 'urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id',
            'config': null
          },
          {
            'value': 11,
            'direction': null,
            'uri': 'urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id',
            'config': null
          }
        ],
        'direction': 'sendrecv',
        'msid':
            '84f453ca-0dbd-4d92-8eec-6b671c88f990 7d0980a9-b60d-4ccc-a31c-2e148fb0b1fd',
        'rtcpMux': 'rtcp-mux',
        'rtcpRsize': 'rtcp-rsize',
        'rtcpFb': [
          {'payload': 96, 'type': 'goog-remb', 'subtype': null},
          {'payload': 96, 'type': 'transport-cc', 'subtype': null},
          {'payload': 96, 'type': 'ccm', 'subtype': 'fir'},
          {'payload': 96, 'type': 'nack', 'subtype': null},
          {'payload': 96, 'type': 'nack', 'subtype': 'pli'},
          {'payload': 103, 'type': 'goog-remb', 'subtype': null},
          {'payload': 103, 'type': 'transport-cc', 'subtype': null},
          {'payload': 103, 'type': 'ccm', 'subtype': 'fir'},
          {'payload': 103, 'type': 'nack', 'subtype': null},
          {'payload': 103, 'type': 'nack', 'subtype': 'pli'},
          {'payload': 107, 'type': 'goog-remb', 'subtype': null},
          {'payload': 107, 'type': 'transport-cc', 'subtype': null},
          {'payload': 107, 'type': 'ccm', 'subtype': 'fir'},
          {'payload': 107, 'type': 'nack', 'subtype': null},
          {'payload': 107, 'type': 'nack', 'subtype': 'pli'},
          {'payload': 109, 'type': 'goog-remb', 'subtype': null},
          {'payload': 109, 'type': 'transport-cc', 'subtype': null},
          {'payload': 109, 'type': 'ccm', 'subtype': 'fir'},
          {'payload': 109, 'type': 'nack', 'subtype': null},
          {'payload': 109, 'type': 'nack', 'subtype': 'pli'},
          {'payload': 115, 'type': 'goog-remb', 'subtype': null},
          {'payload': 115, 'type': 'transport-cc', 'subtype': null},
          {'payload': 115, 'type': 'ccm', 'subtype': 'fir'},
          {'payload': 115, 'type': 'nack', 'subtype': null},
          {'payload': 115, 'type': 'nack', 'subtype': 'pli'},
          {'payload': 117, 'type': 'goog-remb', 'subtype': null},
          {'payload': 117, 'type': 'transport-cc', 'subtype': null},
          {'payload': 117, 'type': 'ccm', 'subtype': 'fir'},
          {'payload': 117, 'type': 'nack', 'subtype': null},
          {'payload': 117, 'type': 'nack', 'subtype': 'pli'},
          {'payload': 39, 'type': 'goog-remb', 'subtype': null},
          {'payload': 39, 'type': 'transport-cc', 'subtype': null},
          {'payload': 39, 'type': 'ccm', 'subtype': 'fir'},
          {'payload': 39, 'type': 'nack', 'subtype': null},
          {'payload': 39, 'type': 'nack', 'subtype': 'pli'},
          {'payload': 45, 'type': 'goog-remb', 'subtype': null},
          {'payload': 45, 'type': 'transport-cc', 'subtype': null},
          {'payload': 45, 'type': 'ccm', 'subtype': 'fir'},
          {'payload': 45, 'type': 'nack', 'subtype': null},
          {'payload': 45, 'type': 'nack', 'subtype': 'pli'},
          {'payload': 98, 'type': 'goog-remb', 'subtype': null},
          {'payload': 98, 'type': 'transport-cc', 'subtype': null},
          {'payload': 98, 'type': 'ccm', 'subtype': 'fir'},
          {'payload': 98, 'type': 'nack', 'subtype': null},
          {'payload': 98, 'type': 'nack', 'subtype': 'pli'},
          {'payload': 100, 'type': 'goog-remb', 'subtype': null},
          {'payload': 100, 'type': 'transport-cc', 'subtype': null},
          {'payload': 100, 'type': 'ccm', 'subtype': 'fir'},
          {'payload': 100, 'type': 'nack', 'subtype': null},
          {'payload': 100, 'type': 'nack', 'subtype': 'pli'},
          {'payload': 119, 'type': 'goog-remb', 'subtype': null},
          {'payload': 119, 'type': 'transport-cc', 'subtype': null},
          {'payload': 119, 'type': 'ccm', 'subtype': 'fir'},
          {'payload': 119, 'type': 'nack', 'subtype': null},
          {'payload': 119, 'type': 'nack', 'subtype': 'pli'},
          {'payload': 49, 'type': 'goog-remb', 'subtype': null},
          {'payload': 49, 'type': 'transport-cc', 'subtype': null},
          {'payload': 49, 'type': 'ccm', 'subtype': 'fir'},
          {'payload': 49, 'type': 'nack', 'subtype': null},
          {'payload': 49, 'type': 'nack', 'subtype': 'pli'}
        ],
        'ssrcGroups': [
          {'semantics': 'FID', 'ssrcs': '3746892314 822236710'}
        ],
        'ssrcs': [
          {'id': 3746892314, 'attribute': 'cname', 'value': 'tcfYxii359Px+p5/'},
          {
            'id': 3746892314,
            'attribute': 'msid',
            'value':
                '84f453ca-0dbd-4d92-8eec-6b671c88f990 7d0980a9-b60d-4ccc-a31c-2e148fb0b1fd'
          },
          {'id': 822236710, 'attribute': 'cname', 'value': 'tcfYxii359Px+p5/'},
          {
            'id': 822236710,
            'attribute': 'msid',
            'value':
                '84f453ca-0dbd-4d92-8eec-6b671c88f990 7d0980a9-b60d-4ccc-a31c-2e148fb0b1fd'
          }
        ]
      }
    ]
  };

  // Construct the answer map
  final Map<String, dynamic> answer = {
    "origin": {
      "username": 'a_user', // Example username for the answer
      "sessionId": offerTemplate["origin"]?["sessionId"],
      "sessionVersion": 2, // You might increment this based on offer's version
      "netType": "IN",
      "ipVer": 4,
      "address": '127.0.0.1' // Localhost or a suitable IP for the answerer
    },
    "timing": {"start": 0, "stop": 0},
    "setup":
        'actpass', // Typically 'actpass' or 'passive' if acting as answerer
    "iceOptions": 'trickle',
    "media": (offerTemplate["media"] as List<dynamic>).map((mediaItemDynamic) {
      final Map<String, dynamic> mediaItem =
          mediaItemDynamic as Map<String, dynamic>;

      // Create a mutable list of candidates from the offer
      final List<Map<String, dynamic>> updatedCandidates = (mediaItem[
              "candidates"] as List<dynamic>)
          .map((candidateDynamic) => candidateDynamic as Map<String, dynamic>)
          .toList();

      // --- Add the specific ICE candidate ---
      // For demonstration, we'll assign a placeholder foundation and priority.
      // In a real WebRTC scenario, these would be properly generated.
      updatedCandidates.add({
        "foundation":
            'custom-candidate-1', // A unique foundation for this candidate
        "component": 1,
        "transport": 'udp',
        "priority": 200, // A priority that makes sense in your ICE negotiation
        "ip": '192.168.56.1',
        "port": 4444,
        "type": 'host' // This is a host candidate
      });
      // --- End of adding specific ICE candidate ---

      return {
        "mid": mediaItem["mid"].toString(),
        "type": mediaItem["type"],
        "port": 9, // This is a common practice for answers or a specific port
        "rtcpMux": 'rtcp-mux',
        "protocol": 'UDP/TLS/RTP/SAVPF',
        "payloads": mediaItem["payloads"], // Echoing payloads from the offer
        "connection": {
          "version": 4,
          "ip":
              '0.0.0.0' // Generally '0.0.0.0' for candidates to dictate connection
        },
        "iceUfrag": mediaItem["iceUfrag"],
        "icePwd": mediaItem["icePwd"],
        "fingerprint": {
          "type": mediaItem["fingerprint"]?["type"],
          "hash": mediaItem["fingerprint"]?["hash"],
        },
        "candidates":
            updatedCandidates, // Use the list with the newly added candidate
        "rtp": [
          {
            // Take the first RTP codec from the offer's media description
            "payload":
                int.parse(mediaItem["rtp"]?[0]?["payload"]?.toString() ?? '0'),
            "codec": mediaItem["rtp"]?[0]?["codec"],
          }
        ],
        "fmtp": [] // This is empty in your original example; add if needed
      };
    }).toList()
  };

  // Output the generated answer map in a readable JSON format
  print("---");
  // print("Generated Answer Map (as JSON):\n${jsonEncode(answer)}");
  print("Generated Answer Map (as JSON):\n${write(answer, null)}");
  print("---");
}
