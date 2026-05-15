// Tests for ICE server-reflexive (srflx) gathering on `RTCPeerConnection`.
//
// Spins up an in-process STUN responder on a loopback UDP socket so the
// tests are fully offline and deterministic. The responder reuses
// `StunServer.handleDatagram` from `lib/src/stun/stun_server.dart`, which
// is the same code path the SFU uses for inbound STUN requests.

import 'dart:async';
import 'dart:io';

import 'package:pure_dart_webrtc/src/stun/stun_server.dart' as stun;
import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:test/test.dart';

/// Minimal STUN echo server: binds a UDP socket on loopback and answers
/// any incoming Binding Request with a Binding Success carrying an
/// `XOR-MAPPED-ADDRESS` for the request's source.
class _LocalStunServer {
  _LocalStunServer._(this._socket) {
    _sub = _socket.listen(_onEvent);
  }

  final RawDatagramSocket _socket;
  late final StreamSubscription<RawSocketEvent> _sub;

  static Future<_LocalStunServer> start() async {
    final socket =
        await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    return _LocalStunServer._(socket);
  }

  InternetAddress get address => _socket.address;
  int get port => _socket.port;

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket.receive();
    if (dg == null) return;
    // The project's StunServer answers Binding Requests with a
    // success response containing XOR-MAPPED-ADDRESS — exactly what the
    // peer connection needs to derive an srflx candidate.
    stun.StunServer.handleDatagram(
      Datagram(dg.data, dg.address, dg.port),
      socket: _socket,
      serverPassword: 'test-pwd',
    );
  }

  Future<void> close() async {
    await _sub.cancel();
    _socket.close();
  }
}

/// Drains [pc.onIceCandidate] until the `null` end-of-candidates sentinel
/// arrives, returning every non-null candidate observed (in order).
Future<List<RTCIceCandidate>> _collectCandidates(
  RTCPeerConnection pc, {
  Duration timeout = const Duration(seconds: 3),
}) {
  final out = <RTCIceCandidate>[];
  final done = Completer<List<RTCIceCandidate>>();
  pc.onIceCandidate = (c) {
    if (done.isCompleted) return;
    if (c == null) {
      done.complete(out);
    } else {
      out.add(c);
    }
  };
  return done.future.timeout(timeout);
}

void main() {
  group('RTCPeerConnection ICE gathering', () {
    late _LocalStunServer stunServer;

    setUp(() async {
      stunServer = await _LocalStunServer.start();
    });

    tearDown(() async {
      await stunServer.close();
    });

    test('gathers a host candidate when no STUN servers are configured',
        () async {
      final pc = RTCPeerConnection(RTCConfiguration(
        defaultVideoCodecs: [Vp8Codec()],
      ));
      addTearDown(pc.close);
      pc.addTransceiver(trackOrKind: MediaKind.video);

      final pending = _collectCandidates(pc);
      final transport = await pc.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(transport.close);

      final cands = await pending;

      expect(cands, hasLength(1));
      expect(cands.single.candidate, contains('typ host'));
      expect(pc.iceGatheringState, RTCIceGatheringState.complete);
    });

    test('gathers a srflx candidate from a configured STUN server', () async {
      final pc = RTCPeerConnection(RTCConfiguration(
        iceServers: [
          RTCIceServer(urls: [
            'stun:${stunServer.address.address}:'
                '${stunServer.port}'
          ]),
        ],
        defaultVideoCodecs: [Vp8Codec()],
      ));
      addTearDown(pc.close);
      pc.addTransceiver(trackOrKind: MediaKind.video);

      final pending = _collectCandidates(pc);
      final transport = await pc.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(transport.close);

      final cands = await pending;

      expect(cands, hasLength(2));
      expect(cands[0].candidate, contains('typ host'));

      final srflx = cands[1].candidate;
      expect(srflx, contains('typ srflx'));
      // raddr/rport should point back at the local host candidate.
      expect(srflx, contains('raddr 127.0.0.1'));
      expect(srflx, contains('rport ${transport.port}'));
      // The mapped address reported by our local STUN server is the
      // request's source — i.e. the bound media socket itself.
      expect(srflx, contains(' 127.0.0.1 ${transport.port} '));

      expect(pc.iceGatheringState, RTCIceGatheringState.complete);
    });

    test('still completes gathering when a STUN server is unreachable',
        () async {
      // Allocate a port and immediately release it so the address is very
      // likely closed for the duration of the test.
      final probe =
          await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      probe.close();

      final pc = RTCPeerConnection(RTCConfiguration(
        iceServers: [
          RTCIceServer(urls: ['stun:127.0.0.1:$deadPort']),
        ],
        defaultVideoCodecs: [Vp8Codec()],
      ));
      addTearDown(pc.close);
      pc.addTransceiver(trackOrKind: MediaKind.video);

      final pending = _collectCandidates(
        pc,
        timeout: const Duration(seconds: 6),
      );
      final transport = await pc.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(transport.close);

      final cands = await pending;

      // Only the host candidate; the unreachable STUN server is silently
      // skipped after `queryStunBinding` times out.
      expect(cands, hasLength(1));
      expect(cands.single.candidate, contains('typ host'));
      expect(pc.iceGatheringState, RTCIceGatheringState.complete);
    });

    test('ignores non-stun: URLs (turn:, https:, malformed)', () async {
      final pc = RTCPeerConnection(RTCConfiguration(
        iceServers: const [
          RTCIceServer(urls: [
            'turn:turn.example.com:3478',
            'https://not-a-stun-url',
            'stun:',
            'garbage',
          ]),
        ],
        defaultVideoCodecs: [Vp8Codec()],
      ));
      addTearDown(pc.close);
      pc.addTransceiver(trackOrKind: MediaKind.video);

      final pending = _collectCandidates(pc);
      final transport = await pc.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(transport.close);

      final cands = await pending;
      expect(cands, hasLength(1));
      expect(cands.single.candidate, contains('typ host'));
    });
  });

  group('RtcUdpTransport.queryStunBinding', () {
    test('resolves with the XOR-MAPPED-ADDRESS reported by the server',
        () async {
      final server = await _LocalStunServer.start();
      addTearDown(server.close);

      // Borrow a freshly-generated DTLS cert via a peer connection so we
      // don't have to plumb the EcdsaCert API into this test directly.
      final pc = RTCPeerConnection();
      addTearDown(pc.close);
      final transport = await pc.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(transport.close);

      final mapped =
          await transport.queryStunBinding(server.address, server.port);

      expect(mapped.ip.address, '127.0.0.1');
      expect(mapped.port, transport.port);
    });

    test('times out when the server never responds', () async {
      final probe =
          await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      probe.close();

      final pc = RTCPeerConnection();
      addTearDown(pc.close);
      final transport = await pc.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(transport.close);

      expect(
        () => transport.queryStunBinding(
          InternetAddress.loopbackIPv4,
          deadPort,
          timeout: const Duration(milliseconds: 200),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
