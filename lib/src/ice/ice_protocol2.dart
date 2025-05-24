import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:collection/collection.dart';

// Assuming 'stun.dart' contains the StunClient and related classes
import '../stun/stun.dart';

class IceCandidate {
  final String foundation;
  final int component;
  final String protocol;
  final int priority;
  final String ip;
  final int port;
  final String type; // 'host', 'srflx', 'relay'
  final String? raddr;
  final int? rport;

  IceCandidate({
    required this.foundation,
    required this.component,
    required this.protocol,
    required this.priority,
    required this.ip,
    required this.port,
    required this.type,
    this.raddr,
    this.rport,
  });

  @override
  String toString() {
    return 'IceCandidate(foundation: $foundation, component: $component, protocol: $protocol, priority: $priority, ip: $ip, port: $port, type: $type, raddr: $raddr, rport: $rport)';
  }

  Map<String, dynamic> toSdpAttribute() {
    final sb = StringBuffer();
    sb.write(
        'candidate:$foundation $component $protocol $priority $ip $port typ $type');
    if (raddr != null && rport != null) {
      sb.write(' raddr $raddr rport $rport');
    }
    return {'a': sb.toString()};
  }
}

Future<List<IceCandidate>> gatherIceCandidates() async {
  final candidates = <IceCandidate>[];

  // 1. Gather Host Candidates (UDP only)
  for (var interface in await NetworkInterface.list()) {
    for (var address in interface.addresses) {
      if (address.type == InternetAddressType.IPv4) {
        candidates.add(
          IceCandidate(
            foundation: generateFoundation(),
            component: 1,
            protocol: 'udp',
            priority: calculatePriority(CandidateType.host, 1, 0),
            ip: address.address,
            port:
                generateRandomPort(), // You might want to bind a specific port range
            type: 'host',
          ),
        );
      }
    }
  }

  // 2. Gather Server Reflexive Candidate (STUN)
  try {
    final srflxCandidateMap = await getIceCandidateFromStun();
    candidates.add(
      IceCandidate(
        foundation: srflxCandidateMap['foundation'] as String,
        component: srflxCandidateMap['component'] as int,
        protocol: srflxCandidateMap['protocol'] as String,
        priority: calculatePriority(CandidateType.srflx, 1, 0),
        ip: srflxCandidateMap['ip'] as String,
        port: srflxCandidateMap['port'] as int,
        type: srflxCandidateMap['type'] as String,
        raddr: srflxCandidateMap['raddr'] as String,
        rport: srflxCandidateMap['rport'] as int,
      ),
    );
  } catch (e) {
    print('Error getting STUN candidate: $e');
  }

  // 3. Gather Relayed Candidates (TURN - Placeholder, likely UDP)
  // If you were to implement TURN over UDP, it would go here.
  // For this UDP-only focus, we'll keep it as a placeholder.
  // candidates.add(...);

  return candidates;
}

enum CandidateType { host, srflx, relay }

int calculatePriority(CandidateType type, int component, int preference) {
  int typePreference;
  switch (type) {
    case CandidateType.host:
      typePreference = 126;
      break;
    case CandidateType.srflx:
      typePreference = 100;
      break;
    case CandidateType.relay:
      typePreference = 0;
      break;
  }
  return (typePreference << 24) + (component << 8) + (256 - preference);
}

String generateFoundation() {
  final random = Random();
  return random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
}

int generateRandomPort() {
  final random = Random();
  return 1024 + random.nextInt(64511); // Ports between 1024 and 65535
}

// --- Signaling (Conceptual) ---
// In a real application, you would use a signaling server (e.g., WebSocket)
// to exchange these candidates with the remote peer.

void exchangeCandidates(
  List<IceCandidate> localCandidates,
  /* Remote peer signaling mechanism */
) async {
  print('Local ICE Candidates (UDP only):');
  for (var candidate in localCandidates) {
    print(candidate.toSdpAttribute());
    // Send this SDP attribute to the remote peer via your signaling mechanism
  }
  // You would also need to receive remote candidates from the peer.
}

// --- Connectivity Checks (Conceptual - UDP assumed) ---
// Once candidates are exchanged, both peers will attempt to establish
// connections to each other's candidates using UDP.

Future<void> performConnectivityChecks(List<IceCandidate> localCandidates,
    List<IceCandidate> remoteCandidates) async {
  print('\nPerforming Connectivity Checks (Conceptual - UDP only):');
  for (var local in localCandidates) {
    for (var remote in remoteCandidates) {
      if (local.protocol == 'udp' && remote.protocol == 'udp') {
        print(
            'Trying to connect from ${local.ip}:${local.port} to ${remote.ip}:${remote.port} (${remote.type}) via udp');
        // In a real implementation, you would attempt to send STUN-like
        // packets over UDP to this candidate pair and listen for responses.
        await Future.delayed(
            Duration(milliseconds: 100)); // Simulate network activity
      }
    }
  }
  print('Connectivity checks complete (conceptual - UDP only).');
}

Future<Map<String, dynamic>> getIceCandidateFromStun() async {
  // (The original getIceCandidateFromStun function remains the same and uses UDP)
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

  rawSocket.close(); // Ensure the socket is closed here

  return {
    'foundation': '1',
    'component': 1,
    'protocol': 'udp',
    'priority': calculatePriority(CandidateType.srflx, 1, 0),
    'ip': ip,
    'port': port,
    'type': 'srflx',
    'raddr': ip,
    'rport': port,
  };
}

void main() async {
  try {
    final localCandidates = await gatherIceCandidates();
    exchangeCandidates(
      localCandidates, /* Your signaling mechanism */
    );

    // In a real scenario, you would receive remote candidates here.
    final remoteCandidates = <IceCandidate>[
      // Example remote candidate (replace with actual received candidates)
      IceCandidate(
          foundation: 'remote1',
          component: 1,
          protocol: 'udp',
          priority: calculatePriority(CandidateType.host, 1, 0),
          ip: '192.168.1.100',
          port: 12345,
          type: 'host'),
      IceCandidate(
          foundation: 'remote2',
          component: 1,
          protocol: 'udp',
          priority: calculatePriority(CandidateType.srflx, 1, 0),
          ip: '78.90.12.34',
          port: 6789,
          type: 'srflx',
          raddr: '78.90.12.34',
          rport: 6789),
      // Example TCP candidate (will be ignored in connectivity checks)
      IceCandidate(
          foundation: 'remote3',
          component: 1,
          protocol: 'tcp',
          priority: calculatePriority(CandidateType.host, 1, 1),
          ip: '192.168.1.101',
          port: 54321,
          type: 'host'),
    ];

    if (remoteCandidates.isNotEmpty) {
      await performConnectivityChecks(localCandidates, remoteCandidates);
      // After connectivity checks, you would select the best working candidate pair (UDP in this case).
    } else {
      print('No remote candidates to check.');
    }

    print('\nAll gathered ICE Candidates (UDP focused):');
    for (var candidate in localCandidates) {
      print(candidate);
    }
  } catch (e) {
    print('Error during ICE gathering: $e');
  }
}
