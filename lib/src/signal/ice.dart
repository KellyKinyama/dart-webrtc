import '../stun/src/stun_client.dart';

Future<List<String>> gatherLocalIceCandidates(String stunServer, int port) async {
  List<String> candidates = [];

  // Add host candidate (local IP)
  String localIp = '192.168.1.100'; // Replace with your actual local IP
  candidates.add('candidate:0 1 UDP 2122260223 $localIp $port typ host');

  // Get server reflexive candidate from STUN
  try {
    var stunClient = StunClient(stunServer, 3478);
    var response = await stunClient.discover();
    if (response != null) {
      String publicIp = response.mappedAddress.address;
      int publicPort = response.mappedAddress.port;
      candidates.add('candidate:1 1 UDP 1686052607 $publicIp $publicPort typ srflx');
    }
  } catch (e) {
    print('STUN discovery failed: $e');
  }

  return candidates;
}

String generateSdpAnswer(List<String> candidates, String dtlsFingerprint) {
  String sdp = '''
v=0
o=- 0 0 IN IP4 0.0.0.0
s=-
t=0 0
a=ice-ufrag:abcd1234
a=ice-pwd:efgh5678
a=fingerprint:sha-256 $dtlsFingerprint
a=setup:actpass
''';

  for (var candidate in candidates) {
    sdp += 'a=$candidate\n';
  }

  sdp += '''
m=audio 1234 RTP/SAVP 0
a=sendrecv
a=rtcp-mux
''';

  return sdp;
}

Future<bool> iceConnectivityCheck(String remoteIp, int remotePort) async {
  var stunClient = StunClient(remoteIp, remotePort);
  try {
    var response = await stunClient.sendBindingRequest();
    return response != null;
  } catch (e) {
    print('ICE connectivity check failed: $e');
    return false;
  }
}
