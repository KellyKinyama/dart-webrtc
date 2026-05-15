// Publisher — server-side wrapper around the client's "publish"
// PeerConnection. Receives RTP from the browser and feeds the per-peer
// [Router] which fans the streams out to subscribers.
//
// Mirrors `pkg/sfu/publisher.go`.

import 'dart:async';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

import 'router.dart';
import 'session.dart';

class Publisher {
  final String peerId;
  final Session session;
  final RTCPeerConnection pc;
  final RtcUdpTransport transport;
  final Router router;

  /// Forwarded from the underlying [pc].
  void Function(RTCIceCandidate? candidate)? onIceCandidate;
  void Function(RTCIceConnectionState state)? onIceConnectionStateChange;

  bool _closed = false;
  int _rtpCount = 0;
  int _rtcpCount = 0;

  Publisher._({
    required this.peerId,
    required this.session,
    required this.pc,
    required this.transport,
    required this.router,
  }) {
    pc.onIceCandidate = (c) => onIceCandidate?.call(c);
    pc.onIceConnectionStateChange = (s) => onIceConnectionStateChange?.call(s);

    // Inbound media: hand each decrypted RTP/RTCP packet to the router
    // for fan-out. SSRC-based demux happens inside [Router].
    transport.onRtp = (peer, rtp) => _onPublisherRtp(rtp);
    transport.onRtcp = (peer, rtcp) => _onPublisherRtcp(rtcp);

    // Router → upstream NACK/PLI: ship packets back over the publisher
    // transport to the secured browser peer.
    router.onUpstreamFeedback = _sendUpstream;
  }

  void _sendUpstream(Uint8List pkt) {
    if (_closed) return;
    final peer = pc.activePeer;
    if (peer == null || !peer.isSecure) return;
    transport.sendRtcp(peer, pkt);
  }

  /// Allocate the publisher transport, bind it on a UDP port, and create
  /// the underlying [RTCPeerConnection]. The SDP exchange is driven by
  /// [answerOffer].
  static Future<Publisher> create({
    required String peerId,
    required Session session,
  }) async {
    final cfg = session.sfu.config;
    final pc = RTCPeerConnection(RTCConfiguration(
      iceServers: [
        for (final url in cfg.iceServerUrls) RTCIceServer(urls: [url]),
      ],
      defaultVideoCodecs: cfg.defaultVideoCodecs,
      defaultAudioCodecs: cfg.defaultAudioCodecs,
    ));
    final port = session.sfu.allocatePort();
    final transport = await pc.bind(
      cfg.bindAddress,
      port,
      announceAddress: cfg.announceAddress,
    );
    final router = Router(peerId: peerId, session: session);
    return Publisher._(
      peerId: peerId,
      session: session,
      pc: pc,
      transport: transport,
      router: router,
    );
  }

  /// Apply the client's offer and return the server's answer. The
  /// receiver/router wiring is populated lazily as the publisher's
  /// transceivers fire `onTrack`.
  Future<RTCSessionDescription> answerOffer(String offerSdp) async {
    await pc.setRemoteDescription(
      RTCSessionDescription(RTCSdpType.offer, offerSdp),
    );
    // Each m= section in the offer becomes a recvonly transceiver on us;
    // when the inbound RTP arrives the Router will register a Receiver
    // for the SSRC. Phase 2 will parse a=ssrc lines here so the router
    // can advertise the receivers to subscribers *before* the first
    // packet lands.
    router.bindToRemoteOffer(pc, offerSdp);
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    return answer;
  }

  // ---- Inbound media plumbing -----------------------------------------

  void _onPublisherRtp(Uint8List rtp) {
    if (_closed) return;
    _rtpCount++;
    if (_rtpCount == 1 || _rtpCount % 500 == 0) {
      final ssrc = rtp.length >= 12
          ? ((rtp[8] << 24) | (rtp[9] << 16) | (rtp[10] << 8) | rtp[11])
              .toUnsigned(32)
          : 0;
      // ignore: avoid_print
      print('[pub:$peerId] inbound RTP #$_rtpCount ssrc=0x'
          '${ssrc.toRadixString(16).padLeft(8, '0')} len=${rtp.length}');
    }
    router.routeRtp(rtp);
  }

  void _onPublisherRtcp(Uint8List rtcp) {
    if (_closed) return;
    _rtcpCount++;
    if (_rtcpCount == 1) {
      // ignore: avoid_print
      print('[pub:$peerId] inbound RTCP #1 len=${rtcp.length}');
    }
    router.routeRtcp(rtcp);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    router.close();
    pc.close();
  }
}
