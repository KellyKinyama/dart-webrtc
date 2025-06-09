let peerConnection = new RTCPeerConnection({
    iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
});

let localStream;
let remoteStream;

let init = async () => {
    localStream = await navigator.mediaDevices.getUserMedia({video:true, audio:true})
    remoteStream = new MediaStream()
    document.getElementById('user-1').srcObject = localStream
    document.getElementById('user-2').srcObject = remoteStream

    localStream.getTracks().forEach((track) => {
        peerConnection.addTrack(track, localStream);
    });

    peerConnection.ontrack = (event) => {
        event.streams[0].getTracks().forEach((track) => {
        remoteStream.addTrack(track);
        });
    };

    peerConnection.onicecandidate = (e) => {
        if (e.candidate === null) {
            console.log('onicecandidate: localSessionDescription:\n', e.localDescription);
        } else {            
            console.log('New ICE candidate:', e.candidate);
        }
    };
    peerConnection.addEventListener('track', e => {
        console.log('onTrack', e);
    });
    peerConnection.onicecandidateerror = (e) => {
        console.log("onicecandidateerror", "candidate address:", e.hostCandidate ?? '', "error text:", e.errorText ?? '', e);
    };
    peerConnection.oniceconnectionstatechange = (e) => {
        const lcalConnection = e.target;
        // this.updateStatus(lcalConnection.iceConnectionState);
        console.log('oniceconnectionstatechange', peerConnection.iceConnectionState, '\n', e);
        if (lcalConnection.iceConnectionState == 'disconnected') {
            this.stop(true);
        } else if (peerConnection.iceConnectionState === 'connected' || peerConnection.iceConnectionState === 'completed') {
            // Get the stats for the peer connection
            lcalConnection.getStats().then((stats) => {                
                stats.forEach((report) => {
                    if (report.type === 'candidate-pair' && report.state === 'succeeded') {
                        const localCandidate = stats.get(report.localCandidateId);
                        const remoteCandidate = stats.get(report.remoteCandidateId);
                        console.log('Succeded Local Candidate:', report.localCandidateId, 'address:', localCandidate?.address, 'object:', localCandidate);
                        console.log('Succeded Remote Candidate:', report.remoteCandidateId, 'address:', remoteCandidate?.address, 'object:', remoteCandidate);
                    }
                });
            });
        }
    };
    peerConnection.onicegatheringstatechange = (e) => {
        console.log('onicegatheringstatechange', (e.target).iceGatheringState, '\n', e);
    };
    peerConnection.onnegotiationneeded = (e) => {
        console.log('onnegotiationneeded', e);
    };
    peerConnection.onsignalingstatechange = (e) => {
        console.log('onsignalingstatechange', (e.target).signalingState, '\n', e);
    };
}

let createOffer = async () => {


    peerConnection.onicecandidate = async (event) => {
        //Event that fires off when a new offer ICE candidate is created
        if(event.candidate){
            document.getElementById('offer-sdp').value = JSON.stringify(peerConnection.localDescription)
        }
    };

    
    const offer = await peerConnection.createOffer();

      
    await peerConnection.setLocalDescription(offer);
}

let createAnswer = async () => {

    let offer = JSON.parse(document.getElementById('offer-sdp').value)

    peerConnection.onicecandidate = async (event) => {
        //Event that fires off when a new answer ICE candidate is created
        if(event.candidate){
            console.log('Adding answer candidate...:', event.candidate)
            document.getElementById('answer-sdp').value = JSON.stringify(peerConnection.localDescription)
        }
    };

    await peerConnection.setRemoteDescription(offer);
    

    let answer = await peerConnection.createAnswer();
    await peerConnection.setLocalDescription(answer); 
    document.getElementById('answer-sdp').value = JSON.stringify(peerConnection.localDescription)
}

let addAnswer = async () => {
    console.log('Add answer triggerd')
    let answer = JSON.parse(document.getElementById('answer-sdp').value)
    console.log('answer:', answer)
     if (!peerConnection.currentRemoteDescription){
        console.log('setting remote description:')
        peerConnection.setRemoteDescription(answer);
    }
    else{
        console.log('Remote description already set')
        
        // peerConnection.setLocalDescription(answer);
    }
}

init()

document.getElementById('create-offer').addEventListener('click', createOffer)
document.getElementById('create-answer').addEventListener('click', createAnswer)
document.getElementById('add-answer').addEventListener('click', addAnswer)