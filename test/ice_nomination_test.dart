// Tests for ICE peer-reflexive discovery + USE-CANDIDATE nomination
// + unsecured-non-nominated peer pruning on `RtcUdpTransport`.
//
// We drive the transport from a second loopback UDP socket, sending
// signed STUN binding requests with and without USE-CANDIDATE, and
// inspect the resulting `RtcPeerTransport` snapshots.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/src/stun/stun_server.dart' as stun;
import 'package:pure_dart_webrtc/webrtc/webrtc.dart';
import 'package:test/test.dart';

const _password = 'test-pwd-ice-nomination';

Uint8List _txid([int seed = 0]) {
  final out = Uint8List(stun.stunTransactionIdSize);
  for (var i = 0; i < out.length; i++) {
    out[i] = (i * 31 + seed) & 0xff;
  }
  return out;
}

Uint8List _bindingRequest({required bool useCandidate, int seed = 0}) {
  final attrs = <stun.StunAttributeType, stun.StunAttribute>{
    // ICE checks always carry USERNAME; the contents don't matter for
    // this test — the embedded server only validates MESSAGE-INTEGRITY.
    stun.StunAttributeType.username:
        stun.StunAttribute(stun.StunAttributeType.username,
            Uint8List.fromList('test-ufrag:remote-ufrag'.codeUnits)),
  };
  if (useCandidate) {
    attrs[stun.StunAttributeType.useCandidate] = stun.StunAttribute(
        stun.StunAttributeType.useCandidate, Uint8List(0));
  }
  final msg = stun.StunMessage(
    messageType: stun.StunMessageType.bindingRequest,
    transactionId: _txid(seed),
    attributes: attrs,
  );
  return msg.encode(password: _password);
}

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TimeoutException('predicate never became true within $timeout');
}

void main() {
  group('ICE peer-reflexive + nomination', () {
    test(
        'first signed STUN binding from a new (host, port) is admitted as '
        'prflx; USE-CANDIDATE marks the peer nominated', () async {
      final pc = RTCPeerConnection();
      addTearDown(pc.close);
      final transport = await pc.bind(
        InternetAddress.loopbackIPv4,
        0,
        stunPassword: _password,
      );
      addTearDown(transport.close);

      final client =
          await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => client.close());

      // First request — no USE-CANDIDATE. Should create a prflx peer
      // with bindingRequestsReceived=1, nominated=false.
      client.send(_bindingRequest(useCandidate: false, seed: 1),
          transport.address, transport.port);
      await _waitFor(() => transport.peers.isNotEmpty);
      var peer = transport.peers.single;
      expect(peer.discoveryMethod, 'prflx');
      expect(peer.nominated, isFalse);
      expect(peer.nominatedAt, isNull);
      await _waitFor(() => peer.bindingRequestsReceived >= 1);

      // Second request — USE-CANDIDATE. Same (host, port), so the
      // existing peer should now flip to nominated=true.
      client.send(_bindingRequest(useCandidate: true, seed: 2),
          transport.address, transport.port);
      await _waitFor(() => peer.nominated);
      expect(peer.nominatedAt, isNotNull);
      expect(peer.bindingRequestsReceived, greaterThanOrEqualTo(2));
    });

    test('binding request with bad MESSAGE-INTEGRITY does not nominate '
        'the peer', () async {
      final pc = RTCPeerConnection();
      addTearDown(pc.close);
      final transport = await pc.bind(
        InternetAddress.loopbackIPv4,
        0,
        stunPassword: _password,
      );
      addTearDown(transport.close);

      // Encode with a *different* password — the embedded server's
      // requireMessageIntegrity gate will drop it, and our peek will
      // also fail integrity, so no peer should ever be created.
      final attrs = <stun.StunAttributeType, stun.StunAttribute>{
        stun.StunAttributeType.username: stun.StunAttribute(
            stun.StunAttributeType.username,
            Uint8List.fromList('attacker:remote'.codeUnits)),
        stun.StunAttributeType.useCandidate: stun.StunAttribute(
            stun.StunAttributeType.useCandidate, Uint8List(0)),
      };
      final msg = stun.StunMessage(
        messageType: stun.StunMessageType.bindingRequest,
        transactionId: _txid(99),
        attributes: attrs,
      );
      final bad = msg.encode(password: 'wrong-password');

      final client =
          await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => client.close());
      client.send(bad, transport.address, transport.port);

      // Give the transport plenty of time to (not) admit the peer.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(transport.peers, isEmpty);
    });
  });
}
