import 'dart:typed_data';

import 'record/message/fragment.dart';

class DtlsSocket {
  final version = (major: 255 - 1, minor: 255 - 2);

  List<Handshake> lastFlight = [];
  List<Uint8List> lastMessage = [];
  int recordSequenceNumber = 0;
  int sequenceNumber = 0;
  int epoch = 0;
  int flight = 0;
  // handshakeCache: {
  //   [flight: number]: {
  //     isLocal: boolean;
  //     data: FragmentedHandshake[];
  //     flight: number;
  //   };
  // } = {};
  Uint8List? cookie;
  List<int> requestedCertificateTypes = [];
  // requestedSignatureAlgorithms: {
  //   hash: HashAlgorithms;
  //   signature: SignatureAlgorithms;
  // }[] = [];
  bool remoteExtendedMasterSecret = false;

  // constructor(
  //   public options: Options,
  //   public sessionType: SessionTypes,
  // ) {}

  // get sessionId() {
  //   return this.cookie ? this.cookie.toString("hex").slice(0, 10) : "";
  // }

  // get sortedHandshakeCache() {
  //   return Object.entries(this.handshakeCache)
  //     .sort(([a], [b]) => Number(a) - Number(b))
  //     .flatMap(([, { data }]) =>
  //       data.sort((a, b) => a.message_seq - b.message_seq),
  //     );
  // }

  // checkHandshakesExist = (handshakes: number[]) =>
  //   !handshakes.find(
  //     (type) =>
  //       this.sortedHandshakeCache.find((h) => h.msg_type === type) == undefined,
  //   );

  // bufferHandshakeCache(
  //   handshakes: FragmentedHandshake[],
  //   isLocal: boolean,
  //   flight: number,
  // ) {
  //   if (!this.handshakeCache[flight]) {
  //     this.handshakeCache[flight] = { data: [], isLocal, flight };
  //   }

  //   const filtered = handshakes.filter((h) => {
  //     const exist = this.handshakeCache[flight].data.find(
  //       (t) => t.msg_type === h.msg_type,
  //     );
  //     if (exist) {
  //       log(this.sessionId, "exist", exist.summary, isLocal, flight);
  //       return false;
  //     }
  //     return true;
  //   });

  //   this.handshakeCache[flight].data = [
  //     ...this.handshakeCache[flight].data,
  //     ...filtered,
  //   ];
  // }

  void handData(Uint8List buf, Function callback) {
    print("Received: ${buf}");
  }
}
