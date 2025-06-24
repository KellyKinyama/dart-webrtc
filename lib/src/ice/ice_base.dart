class IceConnection {
  bool iceControlling;//: boolean;
  bool localUsername;//: string;
  String localPassword;//: string;
  String remotePassword;//: string;
  String remoteUsername;//: string;
  bool remoteIsLite;//: boolean;
  List<CandidatePair> checkList;//: CandidatePair[];
  List<Candidate> localCandidates;//: Candidate[];
  List<Candidate> remoteCandidates;//: Candidate[];
  List<CandidatePair> candidatePairs;//: CandidatePair[];
  Address? stunServer;//?: Address;
  Address? turnServer;//?: Address;
  int generation;//: number;
  IceOptions options;//: IceOptions;
  bool remoteCandidatesEnd;//: boolean;
  bool localCandidatesEnd;//: boolean;
  IceState state;//: IceState;
  MdnsLookup? lookup;//?: MdnsLookup;
  CandidatePair? nominated;//?: CandidatePair;

  // readonly onData: Event<[Buffer]>;
  // readonly stateChanged: Event<[IceState]>;
  // readonly onIceCandidate: Event<[Candidate]>;

  Function restart;//(): void;

  Function setRemoteParams;//(params: {
  //   iceLite: boolean;
  //   usernameFragment: string;
  //   password: string;
  // }): void;

 Future<void> gatherCandidates;//(): Promise<void>;

  Future<void> connect;//: Promise<void>;

  Future<void> close;//(): Promise<void>;

  Future<void> addRemoteCandidate;//(remoteCandidate: Candidate | undefined): Promise<void>;

  Future<void> send;//(data: Buffer): Promise<void>;

 Function getDefaultCandidate;//(): Candidate | undefined;
 Function resetNominatedPair;//(): void;
}

abstract class CandidatePairStats {
 int packetsSent;//: number;
 int packetsReceived;//: number;
 int bytesSent;//: number;
 int bytesReceived;//: number;
 int? rtt;//?: number;
 int totalRoundTripTime;//: number;
 int roundTripTimeMeasurements;//: number;
}

class CandidatePair implements CandidatePairStats {
  final id = UUID();
  handle?: Cancelable<void>;
  bool nominated = false;
  bool remoteNominated = false;
  // 5.7.4.  Computing States
  CandidatePairState _state = CandidatePairState.FROZEN;
  get state {
    return _state;
  }

  // Statistics tracking
  int packetsSent = 0;
  int packetsReceived = 0;
  int bytesSent = 0;
  int bytesReceived = 0;
  int? rtt;//?: number;
  int totalRoundTripTime = 0;
  int roundTripTimeMeasurements = 0;

  toJSON() {
    return json;
  }

  get json {
    return {
      "protocol": protocol.type,
      "localCandidate": localCandidate.toSdp(),
      "remoteCandidate": remoteCandidate.toSdp(),
    };
  }

  // constructor(
  //   public protocol: Protocol,
  //   public remoteCandidate: Candidate,
  //   public iceControlling: boolean,
  // ) {}

  updateState(CandidatePairState state) {
    _state = state;
  }

  get localCandidate {
    if (!protocol.localCandidate) {
      throw Exception("localCandidate not exist");
    }
    return protocol.localCandidate;
  }

  get remoteAddr {
    return [remoteCandidate.host, remoteCandidate.port];
  }

  get component() {
    return this.localCandidate.component;
  }

  get priority() {
    return candidatePairPriority(
      localCandidate,
      remoteCandidate,
      iceControlling,
    );
  }

  get foundation() {
    return localCandidate.foundation;
  }
}

const ICE_COMPLETED = 1;
const ICE_FAILED = 2 ;

const CONSENT_INTERVAL = 5;
const CONSENT_FAILURES = 6;
enum CandidatePairState {
  FROZEN(0),
  WAITING(1),
  IN_PROGRESS(2),
  SUCCEEDED(3),
  FAILED(4);

  const CandidatePairState(this.value);
  final int value;
}

enum IceState{
  disconnected,
  closed,
  completed,
  iceStatenew,
  connected;
  }

class IceOptions {
  Address? stunServer;
  Address? turnServer;
  String? turnUsername;
  String? turnPassword;
  turnTransport?: "udp" | "tcp";
  bool? forceTurn;
  String? localPasswordPrefix;
  bool useIpv4: boolean;
  bool useIpv6: boolean;
  bool? useLinkLocalAddress;
  List<int>? portRange;
  InterfaceAddresses? interfaceAddresses;
  List<String>? additionalHostAddresses;
  Function filterStunResponse;// (
  //   message: Message,
  //   addr: Address,
  //   protocol: Protocol,
  // ) => boolean;
  Function filterCandidatePair;//?: (pair: CandidatePair) => boolean;
}

final IceOptions defaultOptions = IceOptions(
  useIpv4: true,
  useIpv6: true,
);

Candidate validateRemoteCandidate(Candidate candidate) {
  // """
  // Check the remote candidate is supported.
  // """
  if (!["host", "relay", "srflx"].includes(candidate.type))
    throw new Error(`Unexpected candidate type "${candidate.type}"`);

  // ipaddress.ip_address(candidate.host)
  return candidate;
}

export function sortCandidatePairs(
  pairs: {
    localCandidate: Pick<Candidate, "priority">;
    remoteCandidate: Pick<Candidate, "priority">;
  }[],
  iceControlling: boolean,
) {
  return pairs
    .sort(
      (a, b) =>
        candidatePairPriority(
          a.localCandidate,
          a.remoteCandidate,
          iceControlling,
        ) -
        candidatePairPriority(
          b.localCandidate,
          b.remoteCandidate,
          iceControlling,
        ),
    )
    .reverse();
}

// 5.7.2.  Computing Pair Priority and Ordering Pairs
export function candidatePairPriority(
  local: Pick<Candidate, "priority">,
  remote: Pick<Candidate, "priority">,
  iceControlling: boolean,
) {
  const G = (iceControlling && local.priority) || remote.priority;
  const D = (iceControlling && remote.priority) || local.priority;
  return (1 << 32) * Math.min(G, D) + 2 * Math.max(G, D) + (G > D ? 1 : 0);
}

export async function serverReflexiveCandidate(
  protocol: Protocol,
  stunServer: Address,
) {
  // """
  // Query STUN server to obtain a server-reflexive candidate.
  // """

  // # perform STUN query
  const request = new Message(methods.BINDING, classes.REQUEST);
  try {
    const [response] = await protocol.request(request, stunServer);

    const localCandidate = protocol.localCandidate;
    if (!localCandidate) {
      throw new Error("not exist");
    }

    const candidate = new Candidate(
      candidateFoundation("srflx", "udp", localCandidate.host),
      localCandidate.component,
      localCandidate.transport,
      candidatePriority("srflx"),
      response.getAttributeValue("XOR-MAPPED-ADDRESS")[0],
      response.getAttributeValue("XOR-MAPPED-ADDRESS")[1],
      "srflx",
      localCandidate.host,
      localCandidate.port,
    );
    return candidate;
  } catch (error) {
    // todo fix
    log("error serverReflexiveCandidate", error);
  }
}

export function validateAddress(addr?: Address): Address | undefined {
  if (addr && Number.isNaN(addr[1])) {
    return [addr[0], 443];
  }
  return addr;
}
