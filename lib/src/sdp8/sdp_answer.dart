import 'package:sdp_transform/sdp_transform.dart';

final sdpAnswer = {
  "type": "answer",
  "sdp":
      "v=0\r\no=- 160236364142515951 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=msid-semantic: WMS 13c5a42f-e40a-417c-ab55-af176a7efccd\r\nm=audio 53991 UDP/TLS/RTP/SAVPF 9 0 8 13\r\nc=IN IP4 172.22.16.1\r\na=rtcp:9 IN IP4 0.0.0.0\r\na=candidate:2204784799 1 udp 2122260223 172.22.16.1 53991 typ host generation 0 network-id 1\r\na=candidate:4246406834 1 udp 2122194687 192.168.56.1 53992 typ host generation 0 network-id 3\r\na=candidate:4244227088 1 udp 2122129151 10.100.53.194 53993 typ host generation 0 network-id 2 network-cost 10\r\na=candidate:4255496711 1 tcp 1518280447 172.22.16.1 9 typ host tcptype active generation 0 network-id 1\r\na=candidate:2211767338 1 tcp 1518214911 192.168.56.1 9 typ host tcptype active generation 0 network-id 3\r\na=candidate:2184586888 1 tcp 1518149375 10.100.53.194 9 typ host tcptype active generation 0 network-id 2 network-cost 10\r\na=ice-ufrag:teX1\r\na=ice-pwd:mJOB8ZRJ4NUZyr0vvTlXuO69\r\na=ice-options:trickle\r\na=fingerprint:sha-256 DF:47:E4:C7:A2:85:53:B0:BF:1A:75:93:B7:34:AC:F5:4A:0B:BA:A8:25:FD:3C:14:0E:D3:8D:E5:CA:32:4D:35\r\na=setup:active\r\na=mid:0\r\na=sendrecv\r\na=msid:13c5a42f-e40a-417c-ab55-af176a7efccd 3a16ce16-1cce-4125-a98f-a296e9a27cd9\r\na=rtcp-mux\r\na=rtpmap:9 G722/8000\r\na=rtpmap:0 PCMU/8000\r\na=rtpmap:8 PCMA/8000\r\na=rtpmap:13 CN/8000\r\na=ssrc:2316108920 cname:EnOHFxoifKV/h3tR\r\n"
};

void main() {
  // Parse the SDP answer
  final parsedAnswer = parse(sdpAnswer['sdp']!);
  // print(parsedAnswer);

  // Write the parsed answer back to SDP format
  final sdpString = write(sdpOfferWithVideo, null);
  print(sdpString);
}

Map<String, dynamic> sdpAnswerMap = {
  'version': 0,
  'origin': {
    'username': '-',
    'sessionId': 160236364142515951,
    'sessionVersion': 2,
    'netType': 'IN',
    'ipVer': 4,
    'address': '127.0.0.1',
  },
  'name': '-',
  'timing': {
    'start': 0,
    'stop': 0,
  },
  'msidSemantic': {
    'semantic': 'WMS',
    'token': '13c5a42f-e40a-417c-ab55-af176a7efccd',
  },
  'media': [
    {
      'rtp': [
        {'payload': 9, 'codec': 'G722', 'rate': 8000, 'encoding': null},
        {'payload': 0, 'codec': 'PCMU', 'rate': 8000, 'encoding': null},
        {'payload': 8, 'codec': 'PCMA', 'rate': 8000, 'encoding': null},
        {'payload': 13, 'codec': 'CN', 'rate': 8000, 'encoding': null},
      ],
      'fmtp': [],
      'type': 'audio',
      'port': 53991,
      'protocol': 'UDP/TLS/RTP/SAVPF',
      'payloads': '9 0 8 13', // Stored as a string as given
      'connection': {
        'version': 4,
        'ip': '172.22.16.1',
      },
      'rtcp': {
        'port': 9,
        'netType': 'IN',
        'ipVer': 4,
        'address': '0.0.0.0',
      },
      'candidates': [
        {
          'foundation': 2204784799,
          'component': 1,
          'transport': 'udp',
          'priority': 2122260223,
          'ip': '172.22.16.1',
          'port': 53991,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': null,
          'generation': 0,
          'network-id': 1,
          'network-cost': null,
        },
        {
          'foundation': 4246406834,
          'component': 1,
          'transport': 'udp',
          'priority': 2122194687,
          'ip': '192.168.56.1',
          'port': 53992,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': null,
          'generation': 0,
          'network-id': 3,
          'network-cost': null,
        },
        {
          'foundation': 4244227088,
          'component': 1,
          'transport': 'udp',
          'priority': 2122129151,
          'ip': '10.100.53.194',
          'port': 53993,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': null,
          'generation': 0,
          'network-id': 2,
          'network-cost': 10,
        },
        {
          'foundation': 4255496711,
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
          'network-cost': null,
        },
        {
          'foundation': 2211767338,
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
          'network-cost': null,
        },
        {
          'foundation': 2184586888,
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
          'network-cost': 10,
        },
      ],
      'iceUfrag': 'teX1',
      'icePwd': 'mJOB8ZRJ4NUZyr0vvTlXuO69',
      'iceOptions': 'trickle',
      'fingerprint': {
        'type': 'sha-256',
        'hash':
            'DF:47:E4:C7:A2:85:53:B0:BF:1A:75:93:B7:34:AC:F5:4A:0B:BA:A8:25:FD:3C:14:0E:D3:8D:E5:CA:32:4D:35',
      },
      'setup': 'active',
      'mid': 0,
      'direction': 'sendrecv',
      'msid':
          '13c5a42f-e40a-417c-ab55-af176a7efccd 3a16ce16-1cce-4125-a98f-a296e9a27cd9',
      'rtcpMux': 'rtcp-mux',
      'ssrcs': [
        {
          'id': 2316108920,
          'attribute': 'cname',
          'value': 'EnOHFxoifKV/h3tR',
        }
      ],
    }
  ],
};

// You can print it to verify
// import 'dart:convert';
// print(jsonEncode(sdpOffer2));

Map<String, dynamic> sdpOfferWithVideo = {
  'version': 0,
  'origin': {
    'username': '-',
    'sessionId': 160236364142515951,
    'sessionVersion': 2,
    'netType': 'IN',
    'ipVer': 4,
    'address': '127.0.0.1',
  },
  'name': '-',
  'timing': {
    'start': 0,
    'stop': 0,
  },
  'msidSemantic': {
    'semantic': 'WMS',
    'token': '13c5a42f-e40a-417c-ab55-af176a7efccd',
  },
  'media': [
    // Existing Audio Media Section
    {
      'rtp': [
        {'payload': 9, 'codec': 'G722', 'rate': 8000, 'encoding': null},
        {'payload': 0, 'codec': 'PCMU', 'rate': 8000, 'encoding': null},
        {'payload': 8, 'codec': 'PCMA', 'rate': 8000, 'encoding': null},
        {'payload': 13, 'codec': 'CN', 'rate': 8000, 'encoding': null},
      ],
      'fmtp': [],
      'type': 'audio',
      'port': 53991, // Audio port
      'protocol': 'UDP/TLS/RTP/SAVPF',
      'payloads': '9 0 8 13',
      'connection': {
        'version': 4,
        'ip': '172.22.16.1',
      },
      'rtcp': {
        'port': 9,
        'netType': 'IN',
        'ipVer': 4,
        'address': '0.0.0.0',
      },
      'candidates': [
        {
          'foundation': 2204784799,
          'component': 1,
          'transport': 'udp',
          'priority': 2122260223,
          'ip': '172.22.16.1',
          'port': 53991,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': null,
          'generation': 0,
          'network-id': 1,
          'network-cost': null,
        },
        {
          'foundation': 4246406834,
          'component': 1,
          'transport': 'udp',
          'priority': 2122194687,
          'ip': '192.168.56.1',
          'port': 53992,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': null,
          'generation': 0,
          'network-id': 3,
          'network-cost': null,
        },
        {
          'foundation': 4244227088,
          'component': 1,
          'transport': 'udp',
          'priority': 2122129151,
          'ip': '10.100.53.194',
          'port': 53993,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': null,
          'generation': 0,
          'network-id': 2,
          'network-cost': 10,
        },
        {
          'foundation': 4255496711,
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
          'network-cost': null,
        },
        {
          'foundation': 2211767338,
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
          'network-cost': null,
        },
        {
          'foundation': 2184586888,
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
          'network-cost': 10,
        },
      ],
      'iceUfrag': 'teX1',
      'icePwd': 'mJOB8ZRJ4NUZyr0vvTlXuO69',
      'iceOptions': 'trickle',
      'fingerprint': {
        'type': 'sha-256',
        'hash':
            'DF:47:E4:C7:A2:85:53:B0:BF:1A:75:93:B7:34:AC:F5:4A:0B:BA:A8:25:FD:3C:14:0E:D3:8D:E5:CA:32:4D:35',
      },
      'setup': 'active',
      'mid': 0,
      'direction': 'sendrecv',
      // Assuming video track shares the same MSID but gets a new track ID
      'msid':
          '13c5a42f-e40a-417c-ab55-af176a7efccd 3a16ce16-1cce-4125-a98f-a296e9a27cd9', // Original MSID, can be changed for a new track ID if needed
      'rtcpMux': 'rtcp-mux',
      'ssrcs': [
        {'id': 2316108920, 'attribute': 'cname', 'value': 'EnOHFxoifKV/h3tR'}
      ],
    },
    // New Video Media Section
    {
      'rtp': [
        {'payload': 96, 'codec': 'VP8', 'rate': 90000, 'encoding': null},
        {'payload': 97, 'codec': 'H264', 'rate': 90000, 'encoding': null},
      ],
      'fmtp': [
        // H264 parameters are commonly defined
        {
          'payload': 97,
          'config':
              'profile-level-id=42e01f;packetization-mode=1;level-asymmetry-allowed=1'
        },
        // VP8 typically has fewer or no fmtp
      ],
      'type': 'video',
      'port': 4446, // Distinct port for video
      'protocol': 'UDP/TLS/RTP/SAVPF',
      'payloads': '96 97', // List of video payload types
      'connection': {
        'version': 4,
        'ip': '172.22.16.1', // Assuming same local IP as audio
      },
      'rtcp': {
        'port': 9, // Often same RTCP port as audio if RTCP-MUX is used
        'netType': 'IN',
        'ipVer': 4,
        'address': '0.0.0.0',
      },
      'candidates': [
        {
          'foundation': 2204784799, 'component': 1, 'transport': 'udp',
          'priority': 2122260222, // Adjusted priority
          'ip': '172.22.16.1', 'port': 4446, 'type': 'host', 'raddr': null,
          'rport': null,
          'tcptype': null, 'generation': 0, 'network-id': 1,
          'network-cost': null
        },
        {
          'foundation': 4246406834, 'component': 1, 'transport': 'udp',
          'priority': 2122194686, // Adjusted priority
          'ip': '192.168.56.1',
          'port': 4447, // Use a new port for this candidate too
          'type': 'host', 'raddr': null, 'rport': null,
          'tcptype': null, 'generation': 0, 'network-id': 3,
          'network-cost': null
        },
        {
          'foundation': 4244227088, 'component': 1, 'transport': 'udp',
          'priority': 2122129150, // Adjusted priority
          'ip': '10.100.53.194',
          'port': 4448, // Use a new port for this candidate too
          'type': 'host', 'raddr': null, 'rport': null,
          'tcptype': null, 'generation': 0, 'network-id': 2, 'network-cost': 10
        },
        {
          'foundation': 4255496711, 'component': 1, 'transport': 'tcp',
          'priority': 1518280446, // Adjusted priority
          'ip': '172.22.16.1', 'port': 9, 'type': 'host', 'raddr': null,
          'rport': null,
          'tcptype': 'active', 'generation': 0, 'network-id': 1,
          'network-cost': null
        },
        {
          'foundation': 2211767338, 'component': 1, 'transport': 'tcp',
          'priority': 1518214910, // Adjusted priority
          'ip': '192.168.56.1', 'port': 9, 'type': 'host', 'raddr': null,
          'rport': null,
          'tcptype': 'active', 'generation': 0, 'network-id': 3,
          'network-cost': null
        },
        {
          'foundation': 2184586888, 'component': 1, 'transport': 'tcp',
          'priority': 1518149374, // Adjusted priority
          'ip': '10.100.53.194', 'port': 9, 'type': 'host', 'raddr': null,
          'rport': null,
          'tcptype': 'active', 'generation': 0, 'network-id': 2,
          'network-cost': 10
        },
      ],
      'iceUfrag':
          'teX1', // Can be shared if ICE Lite is used for both media streams
      'icePwd': 'mJOB8ZRJ4NUZyr0vvTlXuO69', // Can be shared
      'iceOptions': 'trickle',
      'fingerprint': {
        'type': 'sha-256',
        'hash':
            'DF:47:E4:C7:A2:85:53:B0:BF:1A:75:93:B7:34:AC:F5:4A:0B:BA:A8:25:FD:3C:14:0E:D3:8D:E5:CA:32:4D:35', // Usually shared for the entire session
      },
      'setup': 'active',
      'mid': 1, // Unique mid for video
      'direction': 'sendrecv',
      // If video is a new track within the same 'msid', use the same UUID for the first part
      // and a new UUID for the second part (track ID). I've generated a placeholder UUID here.
      'msid':
          '13c5a42f-e40a-417c-ab55-af176a7efccd a7b8c9d0-e1f2-3456-7890-abcdef123456',
      'rtcpMux': 'rtcp-mux',
      'ssrcs': [
        // Example SSRC for video, typically a new, unique SSRC ID
        {'id': 1234567890, 'attribute': 'cname', 'value': 'EnOHFxoifKV/h3tR'},
      ],
    },
  ],
};

// To verify the structure (requires import 'dart:convert';)
// print(jsonEncode(sdpOfferWithVideo));
