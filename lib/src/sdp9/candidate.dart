enum TransportType {
  udp("udp"),
  tcp("tcp");

  const TransportType(this.value);
  final String value;

  @override
  String toString() {
    return value;
  }

  factory TransportType.fromString(String key) {
    return values.firstWhere((element) => element.value == key);
  }
}

class Candidate {
  int foundation;
  int component;
  TransportType transport;
  int priority;
  String ip;
  int port;
  String type;
  String? raddr;
  int? rport;
  String? tcptype;
  int generation;
  int networkId;
  int? networkCost;

  Candidate(
      {required this.foundation,
      required this.component,
      required this.transport,
      required this.priority,
      required this.ip,
      required this.port,
      required this.type,
      this.raddr,
      this.rport,
      this.tcptype,
      required this.generation,
      required this.networkId,
      this.networkCost});

  @override
  String toString() {
    return toJson().toString();
  }

  factory Candidate.fromJson(dynamic candidate) {
    TransportType transport = TransportType.fromString(candidate['transport']);
    // print("${transport}");
    return Candidate(
        foundation: candidate['foundation'],
        component: candidate['component'],
        transport: transport,
        priority: candidate['priority'],
        ip: candidate['ip'],
        port: candidate['port'],
        type: candidate['type'],
        raddr: candidate['raddr'],
        rport: candidate['rport'],
        tcptype: candidate['tcptype'],
        generation: candidate['generation'],
        networkId: candidate['network-id'],
        networkCost: candidate['network-cost']);
  }

  dynamic toJson() {
    return {
      'foundation': foundation,
      'component': component,
      'transport': transport.toString(),
      'priority': priority,
      'ip': ip,
      'port': port,
      'type': type,
      'raddr': raddr,
      'rport': rport,
      'tcptype': tcptype,
      'generation': generation,
      'network-id': networkId,
      'network-cost': networkCost
    };
  }
}
