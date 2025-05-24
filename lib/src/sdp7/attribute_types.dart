

class Group {
  String semantic;
  List<String> identificationTag;
}

class FingerPrint {
  String hashFunction;
  String fingerprint;
}

enum Setup {
  active,
  passive,
  actpass,
  holdconn,
}

extension SetupExtension on Setup {
  String get value {
    switch (this) {
      case Setup.active:
        return 'active';
      case Setup.passive:
        return 'passive';
      case Setup.actpass:
        return 'actpass';
      case Setup.holdconn:
        return 'holdconn';
    }
  }

  static Setup? fromString(String input) {
    switch (input) {
      case 'active':
        return Setup.active;
      case 'passive':
        return Setup.passive;
      case 'actpass':
        return Setup.actpass;
      case 'holdconn':
        return Setup.holdconn;
      default:
        return null;
    }
  }
}

class Identity {
  String assertionValue;
  List<Map<String, String?>> extensions;
}

class Extmap {
  int entry;
  String extensionName;
  String? direction;
  String? extensionAttributes;
}

class Candidate {
  String foundation;
  String componentId;
  String transport;
  String priority;
  String connectionAddress;
  String port;
  String type;
  String? relAddr;
  String? relPort;
  Map<String, String> extension;

  Candidate({
    required this.foundation,
    required this.componentId,
    required this.transport,
    required this.priority,
    required this.connectionAddress,
    required this.port,
    required this.type,
    this.relAddr,
    this.relPort,
    required this.extension,
  });
}

class RemoteCandidate {
  String componentId;
  String connectionAddress;
  String port;
}

typedef RemoteCandidates = List<RemoteCandidate>;

class RTPMap {
  // payloadType: string;
  String encodingName;
  String clockRate;
  int? encodingParameters;
}

class Fmtp {
  // format: string;
  Map<String, String?> parameters;
}

enum Direction {
  sendrecv,
  sendonly,
  recvonly,
  inactive,
}

class SSRC {
  int ssrcId;
  Map<String, String?> attributes;
}

class SSRCGroup {
  String semantic;
  List<int> ssrcIds;
}

// class RTCPFeedback {
//   // payloadType: string;
//   feedback: FeedBack;
// }

abstract class RTCPFeedback {}

class ACKFeedback extends RTCPFeedback {
  String type = "ack";
  String? parameter; // "rpsi" | "app" | string
  String? additional;
}

class NACKFeedback extends RTCPFeedback {
  String type = "nack";
  String? parameter; // "pli" | "sli" | "rpsi" | "app" | string
  String? additional;
}

class TRRINTFeedback extends RTCPFeedback {
  String type = "trr-int";
  String interval;
  
  TRRINTFeedback({required this.interval});
}

class OtherFeedback extends RTCPFeedback {
  String type;
  String? parameter; // "app" | string
  String? additional;

  OtherFeedback({required this.type, this.parameter, this.additional});
}

class ACKFeedback {
  String type = "ack";
  String? parameter; // "rpsi" | "app" | string
  String? additional;
}

class NACKFeedback {
  final String type;
  final String? parameter;
  final String? additional;

  NACKFeedback({
    this.type = 'nack',
    this.parameter,
    this.additional,
  });
}

class TRRINTFeedback {
  final String type;
  final String interval;

  TRRINTFeedback({
    this.type = 'trr-int',
    required this.interval,
  });
}

class OtherFeedback {
  final String type;
  final String? parameter;
  final String? additional;

  OtherFeedback({
    required this.type,
    this.parameter,
    this.additional,
  });
}

class RTCP {
  final String port;
  final String? netType;
  final String? addressType;
  final String? address;

  RTCP({
    required this.port,
    this.netType,
    this.addressType,
    this.address,
  });
}

class MSID {
  final String id;
  final String? appdata;

  MSID({
    required this.id,
    this.appdata,
  });
}

abstract class RIDParam {}

class RIDWidthParam implements RIDParam {
  final String type = 'max-width';
  final String? val;

  RIDWidthParam({this.val});
}

class RIDHeightParam implements RIDParam {
  final String type = 'height-width';
  final String? val;

  RIDHeightParam({this.val});
}

class RIDFpsParam implements RIDParam {
  final String type = 'max-fps';
  final String? val;

  RIDFpsParam({this.val});
}

class RIDFsParam implements RIDParam {
  final String type = 'max-fs';
  final String? val;

  RIDFsParam({this.val});
}

class RIDBrParam implements RIDParam {
  final String type = 'max-br';
  final String? val;

  RIDBrParam({this.val});
}

class RIDPpsParam implements RIDParam {
  final String type = 'max-pps';
  final String? val;

  RIDPpsParam({this.val});
}

class RIDBppParam implements RIDParam {
  final String type = 'max-bpp';
  final String? val;

  RIDBppParam({this.val});
}

class RIDDependParam implements RIDParam {
  final String type = 'depend';
  final List<String> rids;

  RIDDependParam({required this.rids});
}

class RIDOtherParam implements RIDParam {
  final String type;
  final String? val;

  RIDOtherParam({required this.type, this.val});
}
enum Direction { send, recv }

class RID {
  final String id;
  final Direction direction;
  final List<String>? payloads;
  final List<RIDParam> params;

  RID({
    required this.id,
    required this.direction,
    this.payloads,
    required this.params,
  });
}

class MsidSemantic {
  final String semantic;
  final bool? applyForAll;
  final List<String> identifierList;

  MsidSemantic({
    required this.semantic,
    this.applyForAll,
    required this.identifierList,
  });
}


export type ExtmapEntry = Record<string, Extmap>;

class PayloadAttribute {
  final RTPMap? rtpMap;
  final Fmtp? fmtp;
  final List<RTCPFeedback> rtcpFeedbacks;
  final int payloadType;

  PayloadAttribute({
    this.rtpMap,
    this.fmtp,
    required this.rtcpFeedbacks,
    required this.payloadType,
  });
}

export type PayloadMap = Record<string, PayloadAttribute>;

class SessionAttributes {
  final List<Group> groups;
  final bool? iceLite;
  final String? iceUfrag;
  final String? icePwd;
  final List<String>? iceOptions;
  final List<FingerPrint> fingerprints;
  final Setup? setup;
  final String? tlsId;
  final List<Identity> identities;
  final List<Extmap> extmaps;
  final List<Attribute> unrecognized;
  final MsidSemantic? msidSemantic;

  SessionAttributes({
    required this.groups,
    this.iceLite,
    this.iceUfrag,
    this.icePwd,
    this.iceOptions,
    required this.fingerprints,
    this.setup,
    this.tlsId,
    required this.identities,
    required this.extmaps,
    required this.unrecognized,
    this.msidSemantic,
  });
}

class Attribute {
  bool? ignored;
  String attField;
  String? attValue;
  num _cur;
}

class MediaAttributes {
  final String? mid;
  final String? iceUfrag;
  final String? icePwd;
  final List<String>? iceOptions;
  final List<Candidate> candidates;
  final List<RemoteCandidates> remoteCandidatesList;
  final bool? endOfCandidates;
  final List<FingerPrint> fingerprints;
  final String? ptime;
  final String? maxPtime;
  final Direction? direction;
  final List<SSRC> ssrcs;
  final List<Extmap> extmaps;
  final bool? rtcpMux;
  final bool? rtcpMuxOnly;
  final bool? rtcpRsize;
  final RTCP? rtcp;
  final List<MSID> msids;
  final List<String> imageattr;
  final List<RID> rids;
  final String? simulcast;
  final String? sctpPort;
  final String? maxMessageSize;
  final List<Attribute> unrecognized;
  final Setup? setup;
  final List<PayloadAttribute> payloads;
  final List<RTCPFeedback> rtcpFeedbackWildcards;
  final List<SSRCGroup> ssrcGroups;

  MediaAttributes({
    this.mid,
    this.iceUfrag,
    this.icePwd,
    this.iceOptions,
    required this.candidates,
    required this.remoteCandidatesList,
    this.endOfCandidates,
    required this.fingerprints,
    this.ptime,
    this.maxPtime,
    this.direction,
    required this.ssrcs,
    required this.extmaps,
    this.rtcpMux,
    this.rtcpMuxOnly,
    this.rtcpRsize,
    this.rtcp,
    required this.msids,
    required this.imageattr,
    required this.rids,
    this.simulcast,
    this.sctpPort,
    this.maxMessageSize,
    required this.unrecognized,
    this.setup,
    required this.payloads,
    required this.rtcpFeedbackWildcards,
    required this.ssrcGroups,
  });
}