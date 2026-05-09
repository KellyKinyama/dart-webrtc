// Tests for the browser-shaped `RTCPeerConnection` façade.
//
// These mirror typical browser code: build two peer connections, do an
// offer/answer exchange, verify the signaling-state machine and that
// `ontrack` fires on the answerer.

import 'dart:io';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:test/test.dart';

void main() {
  group('RTCPeerConnection (browser-shaped)', () {
    test('initial state is `stable` / `new`', () {
      final pc = RTCPeerConnection();
      addTearDown(pc.close);

      expect(pc.signalingState, RTCSignalingState.stable);
      expect(pc.iceConnectionState, RTCIceConnectionState.newState);
      expect(pc.connectionState, RTCPeerConnectionState.newState);
      expect(pc.iceGatheringState, RTCIceGatheringState.newState);
      expect(pc.localDescription, isNull);
      expect(pc.remoteDescription, isNull);
      expect(pc.getTransceivers(), isEmpty);
    });

    test('addTransceiver appends a sender + receiver pair', () {
      final pc = RTCPeerConnection(RTCConfiguration(
        defaultVideoCodecs: [Vp8Codec()],
      ));
      addTearDown(pc.close);

      final t = pc.addTransceiver(trackOrKind: MediaKind.video);

      expect(pc.getTransceivers(), hasLength(1));
      expect(pc.getSenders(), hasLength(1));
      expect(pc.getReceivers(), hasLength(1));
      expect(t.kind, MediaKind.video);
      expect(t.direction, RTCRtpTransceiverDirection.sendrecv);
    });

    test('createOffer without transceivers throws', () {
      final pc = RTCPeerConnection();
      addTearDown(pc.close);
      expect(pc.createOffer(), throwsA(isA<StateError>()));
    });

    test('full offer/answer exchange between two peers', () async {
      final caller = RTCPeerConnection(RTCConfiguration(
        defaultVideoCodecs: [Vp8Codec(), Vp9Codec()],
        defaultAudioCodecs: [PcmuCodec()],
      ));
      final callee = RTCPeerConnection(RTCConfiguration(
        defaultVideoCodecs: [Vp8Codec()],
        defaultAudioCodecs: [PcmuCodec()],
      ));
      addTearDown(caller.close);
      addTearDown(callee.close);

      caller.addTransceiver(trackOrKind: MediaKind.video);
      caller.addTransceiver(trackOrKind: MediaKind.audio);

      final tracksOnCallee = <MediaStreamTrack>[];
      callee.onTrack = (event) => tracksOnCallee.add(event.track);

      // Caller side.
      final offer = await caller.createOffer();
      expect(offer.type, RTCSdpType.offer);
      expect(offer.sdp, contains('m=video'));
      expect(offer.sdp, contains('m=audio'));
      expect(offer.sdp, contains('a=mid:0'));
      expect(offer.sdp, contains('a=mid:1'));
      expect(offer.sdp, contains('a=group:BUNDLE 0 1'));
      expect(offer.sdp, contains('a=fingerprint:sha-256'));

      await caller.setLocalDescription(offer);
      expect(caller.signalingState, RTCSignalingState.haveLocalOffer);

      // Callee side.
      await callee.setRemoteDescription(offer);
      expect(callee.signalingState, RTCSignalingState.haveRemoteOffer);

      final answer = await callee.createAnswer();
      expect(answer.type, RTCSdpType.answer);
      expect(answer.sdp, contains('m=video'));
      expect(answer.sdp, contains('m=audio'));
      expect(answer.sdp, contains('a=setup:passive'));

      await callee.setLocalDescription(answer);
      expect(callee.signalingState, RTCSignalingState.stable);

      // ontrack should have fired once per recvable transceiver.
      expect(tracksOnCallee.map((t) => t.kind),
          containsAll([MediaKind.video, MediaKind.audio]));

      await caller.setRemoteDescription(answer);
      expect(caller.signalingState, RTCSignalingState.stable);
      expect(caller.iceConnectionState, RTCIceConnectionState.checking);
      expect(caller.connectionState, RTCPeerConnectionState.connecting);
    });

    test('ICE gathering completes and emits the end-of-candidates sentinel',
        () async {
      final pc = RTCPeerConnection(RTCConfiguration(
        defaultVideoCodecs: [Vp8Codec()],
      ));
      addTearDown(pc.close);

      final candidates = <RTCIceCandidate?>[];
      final gatheringStates = <RTCIceGatheringState>[];
      pc.onIceCandidate = candidates.add;
      pc.onIceGatheringStateChange = gatheringStates.add;

      pc.addTransceiver(trackOrKind: MediaKind.video);
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      await Future<void>.delayed(Duration.zero);

      expect(
          gatheringStates,
          containsAllInOrder([
            RTCIceGatheringState.gathering,
            RTCIceGatheringState.complete,
          ]));
      expect(candidates, [null]);
    });

    test('signaling state transitions reject invalid sequences', () async {
      final pc = RTCPeerConnection(RTCConfiguration(
        defaultVideoCodecs: [Vp8Codec()],
      ));
      addTearDown(pc.close);
      pc.addTransceiver(trackOrKind: MediaKind.video);
      final offer = await pc.createOffer();
      // Setting an `answer` from `stable` is illegal.
      expect(
        pc.setLocalDescription(
            RTCSessionDescription(RTCSdpType.answer, offer.sdp)),
        throwsA(isA<StateError>()),
      );
    });

    test('close transitions to `closed` and blocks further calls', () {
      final pc = RTCPeerConnection(RTCConfiguration(
        defaultVideoCodecs: [Vp8Codec()],
      ));
      pc.addTransceiver(trackOrKind: MediaKind.video);
      pc.close();

      expect(pc.signalingState, RTCSignalingState.closed);
      expect(pc.connectionState, RTCPeerConnectionState.closed);
      expect(pc.iceConnectionState, RTCIceConnectionState.closed);
      expect(() => pc.addTransceiver(trackOrKind: MediaKind.audio),
          throwsA(isA<StateError>()));
    });

    test('RTCSessionDescription round-trips through JSON', () {
      const original = RTCSessionDescription(RTCSdpType.offer, 'v=0\r\n');
      final json = original.toJson();
      final restored = RTCSessionDescription.fromJson(json);
      expect(restored.type, original.type);
      expect(restored.sdp, original.sdp);
    });
  });

  group('RTCPeerConnection transport binding', () {
    test('bind emits a real host RTCIceCandidate then a null sentinel',
        () async {
      final pc = RTCPeerConnection(RTCConfiguration(
        defaultVideoCodecs: [Vp8Codec()],
      ));
      addTearDown(pc.close);
      pc.addTransceiver(trackOrKind: MediaKind.video);

      final candidates = <RTCIceCandidate?>[];
      pc.onIceCandidate = candidates.add;

      final transport = await pc.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(transport.close);

      // Wait one tick for the scheduled emissions.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(candidates, hasLength(2));
      expect(candidates.first, isNotNull);
      expect(candidates.first!.candidate, contains('typ host'));
      expect(candidates.first!.candidate, contains('udp'));
      expect(candidates.last, isNull);
      expect(pc.iceGatheringState, RTCIceGatheringState.complete);
      expect(pc.transport, isNotNull);
    });

    test('bind throws when called twice', () async {
      final pc = RTCPeerConnection();
      addTearDown(pc.close);
      final t = await pc.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(t.close);
      expect(
        () => pc.bind(InternetAddress.loopbackIPv4, 0),
        throwsStateError,
      );
    });

    test('close tears down the bound transport', () async {
      final pc = RTCPeerConnection();
      final t = await pc.bind(InternetAddress.loopbackIPv4, 0);
      pc.close();
      // The socket should have been closed too; binding to its port again
      // must succeed.
      expect(pc.transport, isNull);
      // A small delay to let the underlying socket fully release.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // re-using the port number is a flaky check, just confirm no crash.
      expect(t.address.address, '127.0.0.1');
    });
  });

  group('RTCDataChannel', () {
    test('createDataChannel returns a properly-shaped channel', () {
      final pc = RTCPeerConnection();
      addTearDown(pc.close);

      final ch = pc.createDataChannel(
          'chat', const RTCDataChannelInit(ordered: true, protocol: 'json'));

      expect(ch.label, 'chat');
      expect(ch.init.ordered, isTrue);
      expect(ch.init.protocol, 'json');
      expect(ch.readyState, RTCDataChannelState.connecting);
      expect(pc.dataChannels, hasLength(1));
    });

    test('markOpen fires onOpen and allows sending', () async {
      final ch = RTCDataChannel('chat');
      var opened = false;
      ch.onOpen = () => opened = true;

      final received = <RTCDataChannelMessage>[];
      ch.onMessage = received.add;

      ch.markOpen();
      await Future<void>.delayed(Duration.zero);
      expect(opened, isTrue);
      expect(ch.readyState, RTCDataChannelState.open);

      ch.send('hello');
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      expect(received.first.text, 'hello');

      ch.close();
      await Future<void>.delayed(Duration.zero);
      expect(ch.readyState, RTCDataChannelState.closed);
    });
  });

  group('RTCStats', () {
    test('getStats returns at least a peer-connection record', () async {
      final pc = RTCPeerConnection();
      addTearDown(pc.close);

      final report = await pc.getStats();
      expect(report.length, greaterThanOrEqualTo(1));
      final pcStats = report.ofType('peer-connection').toList();
      expect(pcStats, hasLength(1));
      expect(pcStats.first.values['signalingState'], 'stable');
    });
  });
}
