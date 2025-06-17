import 'package:events_emitter/emitters/event_emitter.dart';
import 'package:uuid/v4.dart';

class RTCPeerConnection extends EventEmitter {
  final cname = UuidV4().generate();
}

class PeerConfig {
  codecs: Partial<{
    /**
     * When specifying a codec with a fixed payloadType such as PCMU,
     * it is necessary to set the correct PayloadType in RTCRtpCodecParameters in advance.
     */
    audio: RTCRtpCodecParameters[];
    video: RTCRtpCodecParameters[];
  }>;
  headerExtensions: Partial<{
    audio: RTCRtpHeaderExtensionParameters[];
    video: RTCRtpHeaderExtensionParameters[];
  }>;
  iceTransportPolicy: "all" | "relay";
  iceServers: RTCIceServer[];
  /**Minimum port and Maximum port must not be the same value */
  icePortRange: [number, number] | undefined;
  iceInterfaceAddresses: InterfaceAddresses | undefined;
  /** Add additional host (local) addresses to use for candidate gathering.
   * Notably, you can include hosts that are normally excluded, such as loopback, tun interfaces, etc.
   */
  iceAdditionalHostAddresses: string[] | undefined;
  iceUseIpv4: boolean;
  iceUseIpv6: boolean;
  forceTurnTCP: boolean;
  /** such as google cloud run */
  iceUseLinkLocalAddress: boolean | undefined;
  /** If provided, is called on each STUN request.
   * Return `true` if a STUN response should be sent, false if it should be skipped. */
  iceFilterStunResponse:
    | ((message: Message, addr: Address, protocol: Protocol) => boolean)
    | undefined;
  iceFilterCandidatePair: ((pair: CandidatePair) => boolean) | undefined;
  dtls: Partial<{
    keys: DtlsKeys;
  }>;
  icePasswordPrefix: string | undefined;
  bundlePolicy: BundlePolicy;
  debug: Partial<{
    /**% */
    inboundPacketLoss: number;
    /**% */
    outboundPacketLoss: number;
    /**ms */
    receiverReportDelay: number;
    disableSendNack: boolean;
    disableRecvRetransmit: boolean;
  }>;
  midSuffix: boolean;
}