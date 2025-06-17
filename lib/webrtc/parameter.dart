// import type { MediaDirection } from "./rtpTransceiver";

class RTCRtpParameters {
 List<RTCRtpCodecParameters> codecs;
 List<RTCRtpHeaderExtensionParameters> headerExtensions;
  String? muxId;
  String? rtpStreamId;
  String? repairedRtpStreamId;
 RTCRtcpParameters? rtcp;
}

enum RTCPFB{}// = { type: string; parameter?: string };
enum MediaDirection{
  all,
  send,recv;
}

class RTCRtpCodecParameters {
  /**
   * When specifying a codec with a fixed payloadType such as PCMU,
   * it is necessary to set the correct PayloadType in RTCRtpCodecParameters in advance.
   */
  int payloadType;
  String mimeType;
  int clockRate;
  int? channels;
  List<RTCPFB> rtcpFeedback = [];
  String? parameters;
  MediaDirection direction=MediaDirection.all;

  RTCRtpCodecParameters(this.mimeType,this.clockRate);

  // constructor(
  //   props: Pick<RTCRtpCodecParameters, "mimeType" | "clockRate"> &
  //     Partial<RTCRtpCodecParameters>,
  // ) {
  //   Object.assign(this, props);
  // }

  get name {
    return mimeType.split("/")[1];
  }

  get contentType {
    return mimeType.split("/")[0];
  }

  get str {
    String s = "$name/$clockRate";
    if (channels == 2) s += "/2";
    return s;
  }
}

class RTCRtpHeaderExtensionParameters {
  int id;
  int uri;

  // constructor(
  //   props: Partial<RTCRtpHeaderExtensionParameters> &
  //     Pick<RTCRtpHeaderExtensionParameters, "uri">,
  // ) {
  //   Object.assign(this, props);
  // }
}

class RTCRtcpParameters {
  String? cname;
  bool mux = false;
  int? ssrc;

//   constructor(props: Partial<RTCRtcpParameters> = {}) {
//     Object.assign(this, props);
//   }
}

class RTCRtcpFeedback {
  String type;
  String? parameter;

  // constructor(props: Partial<RTCRtcpFeedback> = {}) {
  //   Object.assign(this, props);
  // }
}
class RTCRtpRtxParameters {
  int ssrc;

  // constructor(props: Partial<RTCRtpRtxParameters> = {}) {
  //   Object.assign(this, props);
  // }
}

class RTCRtpCodingParameters {
  int ssrc;
  int payloadType;
 RTCRtpRtxParameters? rtx;

  // constructor(
  //   props: Partial<RTCRtpCodingParameters> &
  //     Pick<RTCRtpCodingParameters, "ssrc" | "payloadType">,
  // ) {
  //   Object.assign(this, props);
  // }
}

class RTCRtpReceiveParameters extends RTCRtpParameters {
 List<RTCRtpCodingParameters> encodings;
}

typedef RTCRtpSendParameters = RTCRtpParameters;

class RTCRtpSimulcastParameters {
  String rid;
 MediaDirection direction=MediaDirection.all;
  // constructor(props: RTCRtpSimulcastParameters) {
  //   Object.assign(this, props);
  // }
}
