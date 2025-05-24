class ServerAgent {
	late String ConferenceName           ;
	late String Ufrag                    ;
	late String Pwd                      ;
	late String FingerprintHash          ;
	late List<IceCandidate>            iceCandidates;
	late Map<String,SignalingMediaComponent> signalingMediaComponents;
	// Sockets                  map[string]UDPClientSocket
}

class SignalingMediaComponent  {
	late ServerAgent Agent           ;
	late String Ufrag           ;
	late String Pwd             ;
	late String FingerprintHash ;
}

class IceCandidate {
	late String Ip;
	late int Port;
}

// func NewServerAgent(candidateIPs []string, udpPort int, conferenceName string) *ServerAgent {
// 	result := &ServerAgent{
// 		ConferenceName:           conferenceName,
// 		Ufrag:                    GenerateICEUfrag(),
// 		Pwd:                      GenerateICEPwd(),
// 		FingerprintHash:          dtls.ServerCertificateFingerprint,
// 		IceCandidates:            []*IceCandidate{},
// 		SignalingMediaComponents: map[string]*SignalingMediaComponent{},
// 		Sockets:                  map[string]UDPClientSocket{},
// 	}
// 	for _, candidateIP := range candidateIPs {
// 		result.IceCandidates = append(result.IceCandidates, &IceCandidate{
// 			Ip:   candidateIP,
// 			Port: udpPort,
// 		})
// 	}
// 	logging.Descf(logging.ProtoAPP, "A new server ICE Agent was created (for a new conference) with Ufrag: <u>%s</u>, Pwd: <u>%s</u>, FingerprintHash: <u>%s</u>", result.Ufrag, result.Pwd, result.FingerprintHash)
// 	return result
// }

// func (a *ServerAgent) EnsureSignalingMediaComponent(iceUfrag string, icePwd string, fingerprintHash string) *SignalingMediaComponent {
// 	result, ok := a.SignalingMediaComponents[iceUfrag]
// 	if ok {
// 		return result
// 	}
// 	result = &SignalingMediaComponent{
// 		Agent:           a,
// 		Ufrag:           iceUfrag,
// 		Pwd:             icePwd,
// 		FingerprintHash: fingerprintHash,
// 	}
// 	a.SignalingMediaComponents[iceUfrag] = result
// 	return result
// }
