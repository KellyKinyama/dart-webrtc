import 'package:sdp_transform/sdp_transform.dart';

final sdpOffer = {
  "sdp":
      "v=0\r\no=- 4215775240449105457 2 IN IP4 0.0.0.0\r\ns=-\r\nt=0 0\r\nm=audio 4444 UDP/TLS/RTP/SAVPF 111 63 9 0 8 13 110 126\r\nc=IN IP4 0.0.0.0\r\na=rtpmap:8 PCMA/8000\r\na=setup:passive\r\na=mid:0\r\na=ice-ufrag:yxYb\r\na=ice-pwd:05iMxO9GujD2fUWXSoi0ByNd\r\na=fingerprint:sha-256 2B:B7:82:67:53:4B:0C:35:52:57:0D:77:62:2A:B3:1F:BA:57:C0:FB:1C:F6:7A:19:E6:9C:F8:15:D1:C3:54:F1\r\na=rtcp-mux\r\na=candidate:1 1 udp 2113937151 192.168.56.1 4444 typ host\r\n",
  "type": "offer"
};

void main() {
  // print(parse(sdpOffer['sdp']!));
  print(write(parsed, null));
}

final Map<String, dynamic> parsed = {
  'version': 0,
  'origin': {
    'username': '-',
    'sessionId': 4215775240449105457,
    'sessionVersion': 2,
    'netType': 'IN',
    'ipVer': 4,
    'address': '0.0.0.0',
  },
  'name': '-',
  'timing': {
    'start': 0,
    'stop': 0,
  },
  'media': [
    {
      'rtp': [
        {
          'payload': 8,
          'codec': 'PCMA',
          'rate': 8000,
          'encoding': null,
        }
      ],
      'fmtp': [],
      'type': 'audio',
      'port': 4444,
      'protocol': 'UDP/TLS/RTP/SAVPF',
      'payloads': '111 63 9 0 8 13 110 126', // Stored as a string as given
      'connection': {
        'version': 4,
        'ip': '0.0.0.0',
      },
      'setup': 'passive',
      'mid': 0,
      'iceUfrag': 'yxYb',
      'icePwd': '05iMxO9GujD2fUWXSoi0ByNd',
      'fingerprint': {
        'type': 'sha-256',
        'hash':
            '2B:B7:82:67:53:4B:0C:35:52:57:0D:77:62:2A:B3:1F:BA:57:C0:FB:1C:F6:7A:19:E6:9C:F8:15:D1:C3:54:F1',
      },
      'rtcpMux': 'rtcp-mux',
      'candidates': [
        {
          'foundation': 1,
          'component': 1,
          'transport': 'udp',
          'priority': 2113937151,
          'ip': '192.168.56.1',
          'port': 4444,
          'type': 'host',
          'raddr': null,
          'rport': null,
          'tcptype': null,
          'generation': null,
          'network-id': null,
          'network-cost': null,
        }
      ],
    }
  ],
};
