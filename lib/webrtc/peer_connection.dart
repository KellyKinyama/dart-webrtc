import 'package:events_emitter/emitters/event_emitter.dart';
import 'package:uuid/v4.dart';

import 'parameter.dart';

class RTCPeerConnection extends EventEmitter {
  final cname = UuidV4().generate();
}

enum IceTransportPolicy {
  all,
  relay;
}

class RTCIceServer {
  List<String> urls;
  String? username; //?: string;
  String? credential; //?: string;
  RTCIceServer(this.urls);
}

class PeerConfig {
  Map<String, List<RTCRtpCodecParameters>> codecs = {};
  /**
     * When specifying a codec with a fixed payloadType such as PCMU,
     * it is necessary to set the correct PayloadType in RTCRtpCodecParameters in advance.
     */
  //   audio: RTCRtpCodecParameters[];
  //   video: RTCRtpCodecParameters[];
  // }>;
  Map<String, List<RTCRtpHeaderExtensionParameters>> headerExtensions =
      {}; // Partial<{
  //   audio: RTCRtpHeaderExtensionParameters[];
  //   video: RTCRtpHeaderExtensionParameters[];
  // }>;
  IceTransportPolicy? iceTransportPolicy;
  List<RTCIceServer>? iceServers;
  /**Minimum port and Maximum port must not be the same value */
  List<int>? icePortRange; //: [number, number] | undefined;
  // InterfaceAddresses iceInterfaceAddresses;//: InterfaceAddresses | undefined;
  /** Add additional host (local) addresses to use for candidate gathering.
   * Notably, you can include hosts that are normally excluded, such as loopback, tun interfaces, etc.
   */
  String? iceAdditionalHostAddresses; //: string[] | undefined;
  // bool iceUseIpv4;//: boolean;
  // bool iceUseIpv6;//: boolean;
  // bool forceTurnTCP;//: boolean;
  /** such as google cloud run */
  bool? iceUseLinkLocalAddress; //: boolean | undefined;
  /** If provided, is called on each STUN request.
   * Return `true` if a STUN response should be sent, false if it should be skipped. */
  Function? iceFilterStunResponse; //:
  // | ((message: Message, addr: Address, protocol: Protocol) => boolean)
  // | undefined;
  Function?
      iceFilterCandidatePair; //: ((pair: CandidatePair) => boolean) | undefined;
  // Map<String,DtlsKeys> dtls={};//: Partial<{
  //   keys: DtlsKeys;
  // }>;
  String? icePasswordPrefix; //: string | undefined;
  // BundlePolicy bundlePolicy;//: BundlePolicy;
  Map<String, dynamic> debug = {
    //: Partial<{
    /**% */
    // inboundPacketLoss: number;
    /**% */
    // outboundPacketLoss: number;
    /**ms */
    // receiverReportDelay: number;
    // disableSendNack: boolean;
    // disableRecvRetransmit: boolean;
  };
  bool? midSuffix; //: boolean;
}

// class DtlsKeys{
//   String certPem;
//  String keyPem;
//  SignatureHash signatureHash;

//  DtlsKeys()
// }
