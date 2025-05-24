

class MediaType {
  static const String video = "video";
  static const String audio = "audio";
}

class CandidateType {
  static const String host = "host";
}

class TransportType {
  static const String udp = "udp";
  static const String tcp = "tcp";
}

class FingerprintType {
  static const String sha256 = "sha-256";
}

class SdpMessage {
  String conferenceName;
  String sessionID;
  List<SdpMedia> mediaItems;

  SdpMessage({
    required this.conferenceName,
    required this.sessionID,
    required this.mediaItems,
  });

  @override
  String toString() {
    String mediaItemsStr =
        mediaItems.map((media) => media.toString()).join('\r\n');
    return 'v=0\r\n'
        'o=- $sessionID 3 IN IP4 127.0.0.1\r\n'
        's=-\r\n'
        't=0 0\r\n'
        'a=group:BUNDLE 0\r\n'
        'a=extmap-allow-mixed\r\n'
        'a=msid-semantic: WMS b7698b5d-fc96-465e-9505-bd9347113a40\r\n'
        '$mediaItemsStr';
  }
}

class SdpMedia {
  int mediaId;
  String type;
  String ufrag;
  String pwd;
  String fingerprintType;
  String fingerprintHash;
  List<SdpMediaCandidate> candidates;
  String payloads;
  String rtpCodec;
  List<String> extmaps;
  String setup;
  String mid;

  SdpMedia({
    required this.mediaId,
    required this.type,
    required this.ufrag,
    required this.pwd,
    required this.fingerprintType,
    required this.fingerprintHash,
    required this.candidates,
    required this.payloads,
    required this.rtpCodec,
    required this.extmaps,
    required this.setup,
    required this.mid,
  });
}
SdpMessage ParseSdpOfferAnswer(offer map[string]interface{}) *SdpMessage {
	sdpMessage := &SdpMessage{}
	sdpMessage.SessionID = offer["origin"].(map[string]interface{})["sessionId"].(string)

	mediaItems := offer["media"].([]interface{})

	for _, mediaItemObj := range mediaItems {
		sdpMedia := SdpMedia{}
		mediaItem := mediaItemObj.(map[string]interface{})
		//mediaId := mediaItem["mid"].(float64)
		sdpMedia.Type = MediaType(mediaItem["type"].(string))
		candidates := make([]interface{}, 0)
		if mediaItem["candidates"] != nil {
			candidates = mediaItem["candidates"].([]interface{})
		}
		sdpMedia.Ufrag = mediaItem["iceUfrag"].(string)
		sdpMedia.Pwd = mediaItem["icePwd"].(string)
		//iceOptions := mediaItem["iceOptions"].(string)
		fingerprintRaw, ok := mediaItem["fingerprint"]
		if !ok {
			fingerprintRaw = offer["fingerprint"]
		}
		fingerprint := fingerprintRaw.(map[string]interface{})
		sdpMedia.FingerprintType = FingerprintType(fingerprint["type"].(string))
		sdpMedia.FingerprintHash = fingerprint["hash"].(string)
		//direction := mediaItem["direction"].(string)
		for _, candidateObj := range candidates {
			sdpMediaCandidate := SdpMediaCandidate{}
			candidate := candidateObj.(map[string]interface{})
			//foundation := candidate["foundation"].(float64)
			sdpMediaCandidate.Type = CandidateType(candidate["type"].(string))
			sdpMediaCandidate.Transport = TransportType(candidate["transport"].(string))
			sdpMediaCandidate.Ip = candidate["ip"].(string)
			sdpMediaCandidate.Port = int(candidate["port"].(float64))
			sdpMedia.Candidates = append(sdpMedia.Candidates, sdpMediaCandidate)
		}
		sdpMessage.MediaItems = append(sdpMessage.MediaItems, sdpMedia)
	}
	logging.Descf(logging.ProtoSDP, "It seems the client has received our SDP Offer, processed it, accepted it, initialized it's media devices (webcam, microphone, etc...), started it's UDP listener, and sent us this SDP Answer. In this project, we don't use the client's candidates, because we has implemented only receiver functionalities, so we don't have any media stream to send :)")
	logging.Infof(logging.ProtoSDP, "Processing Incoming SDP: %s", sdpMessage)
	logging.LineSpacer(2)
	return sdpMessage
}

func GenerateSdpOffer(iceAgent *agent.ServerAgent) *SdpMessage {
	candidates := []SdpMediaCandidate{}
	for _, agentCandidate := range iceAgent.IceCandidates {
		candidates = append(candidates, SdpMediaCandidate{
			Ip:        agentCandidate.Ip,
			Port:      agentCandidate.Port,
			Type:      "host",
			Transport: TransportTypeUdp,
		})
	}
	offer := &SdpMessage{
		SessionID: "1234",
		MediaItems: []SdpMedia{
			{
				MediaId:  0,
				Type:     MediaTypeVideo,
				Payloads: rtp.PayloadTypeVP8.CodecCodeNumber(), //96
				RTPCodec: rtp.PayloadTypeVP8.CodecName(),       //VP8/90000
				Ufrag:    iceAgent.Ufrag,
				Pwd:      iceAgent.Pwd,
				/*
					https://webrtcforthecurious.com/docs/04-securing/
					Certificate #
					Certificate contains the certificate for the Client or Server.
					This is used to uniquely identify who we were communicating with.
					After the handshake is over we will make sure this certificate
					when hashed matches the fingerprint in the SessionDescription.
				*/
				FingerprintType: FingerprintTypeSHA256,
				FingerprintHash: iceAgent.FingerprintHash,
				Candidates:      candidates,
			},
		},
	}
	if config.Val.Server.RequestAudio {
		offer.MediaItems = append(offer.MediaItems, SdpMedia{
			MediaId:  1,
			Type:     MediaTypeAudio,
			Payloads: rtp.PayloadTypeOpus.CodecCodeNumber(), //109
			RTPCodec: rtp.PayloadTypeOpus.CodecName(),       //OPUS/48000/2
			Ufrag:    iceAgent.Ufrag,
			Pwd:      iceAgent.Pwd,
			/*
				https://webrtcforthecurious.com/docs/04-securing/
				Certificate #
				Certificate contains the certificate for the Client or Server.
				This is used to uniquely identify who we were communicating with.
				After the handshake is over we will make sure this certificate
				when hashed matches the fingerprint in the SessionDescription.
			*/
			FingerprintType: FingerprintTypeSHA256,
			FingerprintHash: iceAgent.FingerprintHash,
			Candidates:      candidates,
		})
	}
	return offer
}

func (m *SdpMessage) String() string {
	mediaItemsStr := make([]string, len(m.MediaItems))
	i := 0
	for _, media := range m.MediaItems {
		mediaItemsStr[i] = fmt.Sprintf("[SdpMedia] %s", media)
		i++
	}

	return common.JoinSlice("\n", false,
		fmt.Sprintf("SessionID: <u>%s</u>", m.SessionID),
		common.ProcessIndent("MediaItems:", "+", mediaItemsStr),
	)
}

func (m SdpMedia) String() string {
	candidatesStr := make([]string, len(m.Candidates))
	i := 0
	for _, candidate := range m.Candidates {
		candidatesStr[i] = fmt.Sprintf("[SdpCandidate] %s", candidate)
		i++
	}

	return common.JoinSlice("\n", false,
		common.ProcessIndent(fmt.Sprintf("MediaId: <u>%d</u>, Type: %s, Ufrag: <u>%s</u>, Pwd: <u>%s</u>", m.MediaId, m.Type, m.Ufrag, m.Pwd), "", []string{
			fmt.Sprintf("FingerprintType: <u>%s</u>, FingerprintHash: <u>%s</u>", m.FingerprintType, m.FingerprintHash),
			common.ProcessIndent("Candidates:", "+", candidatesStr),
		}))
}

func (m SdpMediaCandidate) String() string {
	return fmt.Sprintf("Type: <u>%s</u>, Transport: <u>%s</u>, Ip: <u>%s</u>, Port: <u>%d</u>", m.Type, m.Transport, m.Ip, m.Port)
}
