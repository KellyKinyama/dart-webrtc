// Browser-shaped transceiver / sender / receiver wrappers.
//
// https://www.w3.org/TR/webrtc/#rtcrtptransceiver-interface

import 'dart:async';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/signal/sdp_v2.dart' show SdpCodec;

import 'media_stream.dart';

/// Transceiver direction (`a=sendrecv` etc.). Mirrors the browser enum.
enum RTCRtpTransceiverDirection {
  sendrecv,
  sendonly,
  recvonly,
  inactive,
  stopped,
}

/// Pluggable callback used by the parent [RTCPeerConnection] to push
/// outbound RTP packets through the bound [RtcUdpTransport].
typedef SendRtpFn = Future<bool> Function(Uint8List rtpBytes);

/// Outbound side of an [RTCRtpTransceiver].
class RTCRtpSender {
  MediaStreamTrack? track;

  /// Hook installed by [RTCPeerConnection.bind]. When null, [send] returns
  /// false (no transport).
  SendRtpFn? sendHook;

  RTCRtpSender({this.track});

  Future<void> replaceTrack(MediaStreamTrack? newTrack) async {
    track = newTrack;
  }

  /// Encrypt and send a raw RTP packet through the bound transport.
  /// Returns false if the connection isn't yet keyed.
  Future<bool> send(Uint8List rtpBytes) async {
    final fn = sendHook;
    if (fn == null) return false;
    return fn(rtpBytes);
  }
}

/// Inbound side of an [RTCRtpTransceiver]. Populated when the remote
/// description introduces the track.
class RTCRtpReceiver {
  MediaStreamTrack? track;

  final StreamController<Uint8List> _rtpController =
      StreamController<Uint8List>.broadcast();
  final StreamController<Uint8List> _rtcpController =
      StreamController<Uint8List>.broadcast();

  RTCRtpReceiver({this.track});

  /// Inbound decrypted RTP packets routed to this receiver.
  Stream<Uint8List> get onRtp => _rtpController.stream;

  /// Inbound decrypted RTCP packets routed to this receiver.
  Stream<Uint8List> get onRtcp => _rtcpController.stream;

  /// Used by [RTCPeerConnection] to deliver decrypted RTP.
  void deliverRtp(Uint8List bytes) {
    if (!_rtpController.isClosed) _rtpController.add(bytes);
  }

  /// Used by [RTCPeerConnection] to deliver decrypted RTCP.
  void deliverRtcp(Uint8List bytes) {
    if (!_rtcpController.isClosed) _rtcpController.add(bytes);
  }

  void dispose() {
    _rtpController.close();
    _rtcpController.close();
  }
}

/// Bidirectional pairing of a sender and a receiver, scoped to one
/// `m=` section / mid.
class RTCRtpTransceiver {
  /// `mid` assigned by the local offer; null until [setLocalDescription] runs.
  String? mid;

  final MediaKind kind;
  final RTCRtpSender sender;
  final RTCRtpReceiver receiver;
  RTCRtpTransceiverDirection direction;
  RTCRtpTransceiverDirection? currentDirection;

  /// Codecs this side prefers to negotiate, in priority order.
  final List<SdpCodec> codecs;

  bool _stopped = false;

  RTCRtpTransceiver({
    required this.kind,
    required this.codecs,
    this.direction = RTCRtpTransceiverDirection.sendrecv,
    MediaStreamTrack? sendTrack,
  })  : sender = RTCRtpSender(track: sendTrack),
        receiver = RTCRtpReceiver();

  bool get stopped => _stopped;

  void stop() {
    _stopped = true;
    direction = RTCRtpTransceiverDirection.stopped;
    receiver.dispose();
  }
}
