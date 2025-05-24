import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import '../stun/stun.dart';
import 'dart:math';

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
        final localSocket = await RawDatagramSocket.bind(address, 0);
        candidates.add(
          IceCandidate(
            foundation: generateFoundation(),
            component: 1,
            protocol: 'udp',
            priority: calculatePriority(CandidateType.host, 1, 0),
            ip: address.address,
            port: localSocket.port,
            type: 'host',
          ),
        );
        localSocket.close();
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

Future<void> performConnectivityChecks(
  List<IceCandidate> localCandidates,
  List<IceCandidate> remoteCandidates,
  StunProtocol stunProtocol,
) async {
  print('\nPerforming Real STUN Connectivity Checks (UDP only):');

  final random = Random.secure();

  // Find a local host candidate IP to bind to for sending
  String? sendingLocalIp;
  for (var candidate in localCandidates) {
    if (candidate.type == 'host' && candidate.protocol == 'udp') {
      sendingLocalIp = candidate.ip;
      break;
    }
  }

  if (sendingLocalIp == null) {
    print('Warning: No local host candidate found to bind for sending.');
    return;
  }

  for (var local in localCandidates) {
    if (local.protocol == 'udp') {
      for (var remote in remoteCandidates) {
        if (remote.protocol == 'udp') {
          print(
              'Trying to connect from ${local.ip}:${local.port} to ${remote.ip}:${remote.port} (${remote.type}) via udp');

          try {
            final localAddressForBinding = InternetAddress(
                sendingLocalIp); // Always use a local host IP for binding
            final remoteAddress = InternetAddress(remote.ip);
            final remotePort = remote.port;
            final localPortForBinding =
                generateRandomPort(); // Use a random local port for sending

            final socket = await RawDatagramSocket.bind(
                localAddressForBinding, localPortForBinding);

            final transactionId = Uint8List(12);
            for (var i = 0; i < 12; i++) {
              transactionId[i] = random.nextInt(256);
            }
            final message = StunMessage.create(
              StunMessage.HEAD,
              StunMessage.METHOD_BINDING | StunMessage.CLASS_REQUEST,
              0,
              StunMessage.MAGIC_COOKIE,
              transactionId.buffer.asInt64List().first ^
                  transactionId.buffer.asInt64List(8).first,
              [],
              stunProtocol,
            );

            final requestBytes = message.toUInt8List();
            socket.send(requestBytes, remoteAddress, remotePort);
            print(
                '  Sent STUN Binding Request from ${socket.address.address}:${socket.port} (bound to $sendingLocalIp:${localPortForBinding}) to ${remote.ip}:${remote.port}');

            Datagram? receivedDatagram;
            StreamSubscription<RawSocketEvent>? subscription;
            final completer = Completer<void>();

            subscription = socket.listen((event) {
              if (event == RawSocketEvent.read) {
                receivedDatagram = socket.receive();
                if (!completer.isCompleted) {
                  completer.complete();
                }
              }
            });

            Future.delayed(Duration(seconds: 2), () {
              if (!completer.isCompleted) {
                completer.completeError(
                    TimeoutException('No response within 2 seconds'));
              }
            });

            try {
              await completer.future;
              if (receivedDatagram != null) {
                print(
                    '  Received UDP data from ${receivedDatagram!.address.address}:${receivedDatagram!.port} for remote ${remote.ip}:${remote.port}');
                try {
                  final responseMessage =
                      StunMessage.form(receivedDatagram!.data, stunProtocol);
                  if (responseMessage.type ==
                          (StunMessage.METHOD_BINDING |
                              StunMessage.CLASS_RESPONSE_SUCCESS) &&
                      (responseMessage.transactionId ==
                          (transactionId.buffer.asInt64List().first ^
                              transactionId.buffer.asInt64List(8).first))) {
                    print(
                        '  Successfully received and parsed a STUN Binding Response!');
                  } else if (responseMessage.type ==
                      (StunMessage.METHOD_BINDING |
                          StunMessage.CLASS_RESPONSE_ERROR)) {
                    print(
                        '  Received a STUN Binding Error Response: ${responseMessage}');
                  } else {
                    print(
                        '  Received a STUN message but it was not a Binding Success or Error Response.');
                  }
                } catch (e) {
                  print(
                      '  Received UDP data, but it could not be parsed as a STUN message: $e');
                }
              } else {
                print(
                    '  No UDP response received from ${remote.ip}:${remote.port} within timeout.');
              }
            } catch (e) {
              if (e is TimeoutException) {
                print(
                    '  No UDP response received from ${remote.ip}:${remote.port} within timeout.');
              } else {
                print('  Error during receive operation: $e');
              }
            } finally {
              await subscription?.cancel();
              socket.close();
            }
          } catch (e) {
            print(
                '  Error during STUN connectivity check to ${remote.ip}:${remote.port}: $e');
          }
        }
      }
    }
  }
  print('STUN Connectivity checks complete.');
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
    ];

    if (remoteCandidates.isNotEmpty) {
      await performConnectivityChecks(
          localCandidates, remoteCandidates, StunProtocol.RFC5389);
      // After connectivity checks, you would select the best working candidate pair.
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

// (The rest of your utility functions: generateFoundation, calculatePriority, exchangeCandidates, getIceCandidateFromStun remain the same)
