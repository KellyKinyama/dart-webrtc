import 'dart:io';
import 'dart:typed_data';

import '../stun.dart';

Future<Map<String, dynamic>> getIceCandidateFromStun() async {
  // Bind a local UDP socket to any available port
  final rawSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final localAddress = rawSocket.address.address;
  final localPort = rawSocket.port;

  final stunClient = StunClient.create(
    transport: Transport.udp,
    serverHost: 'stun.l.google.com',
    serverPort: 19302,
    localIp: localAddress,
    localPort: 54321,
    // rawSocket: rawSocket,
    stunProtocol: StunProtocol.RFC5389,
  );

  final bindingRequest = stunClient.createBindingStunMessage();
  final response =
      await stunClient.sendAndAwait(bindingRequest, isAutoClose: true);

  final xorMappedAddress = response.attributes.firstWhere(
    (attr) => attr.type == 0x0020,
    orElse: () =>
        throw Exception('No XOR-MAPPED-ADDRESS found in STUN response'),
  ) as AddressAttribute;

  final ip = xorMappedAddress.addressDisplayName;
  final port = xorMappedAddress.port;

  print(xorMappedAddress);

  return {
    'foundation': '1',
    'component': 1,
    'protocol': 'udp',
    'priority': 2130706431,
    'ip': ip,
    'port': port,
    'type': 'srflx',
    'raddr': ip,
    'rport': port,
  };
}

void main() async {
  try {
    final iceCandidate = await getIceCandidateFromStun();
    print('ICE Candidate: $iceCandidate');
  } catch (e) {
    print('Error: $e');
  }
}
