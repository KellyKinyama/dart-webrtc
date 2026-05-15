// Phase B-quick — exercise UdpRelayHub framing-error counter paths
// (too-short, bad magic, bad version, bad type, mismatched length)
// and the endpoints accessor that the existing udp_relay_test.dart
// doesn't reach.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pure_dart_webrtc_ion_style_sfu/src/cluster/udp_relay_transport.dart';
import 'package:test/test.dart';

const int _frameMagic = 0x696f6e72; // "ionr"
const int _frameVersion = 0x01;
const int _typeRtp = 1;
const int _headerLen = 12;

Uint8List _frame({
  int magic = _frameMagic,
  int version = _frameVersion,
  int type = _typeRtp,
  int? declaredLen,
  int payloadBytes = 4,
}) {
  final dl = declaredLen ?? payloadBytes;
  final out = Uint8List(_headerLen + payloadBytes);
  out[0] = (magic >> 24) & 0xff;
  out[1] = (magic >> 16) & 0xff;
  out[2] = (magic >> 8) & 0xff;
  out[3] = magic & 0xff;
  out[4] = version;
  out[5] = type;
  // bytes 6-7 unused / reserved
  out[8] = (dl >> 24) & 0xff;
  out[9] = (dl >> 16) & 0xff;
  out[10] = (dl >> 8) & 0xff;
  out[11] = dl & 0xff;
  for (var i = 0; i < payloadBytes; i++) {
    out[_headerLen + i] = i + 1;
  }
  return out;
}

Future<int> _waitFraming(UdpRelayHub h, int target,
    {Duration timeout = const Duration(seconds: 2)}) async {
  final deadline = DateTime.now().add(timeout);
  while ((h.stats['framingErrors'] as int) < target) {
    if (DateTime.now().isAfter(deadline)) {
      fail('framingErrors stuck at ${h.stats['framingErrors']}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return h.stats['framingErrors'] as int;
}

void main() {
  group('UdpRelayHub framing errors', () {
    late UdpRelayHub hub;
    late RawDatagramSocket sender;

    setUp(() async {
      hub = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: 0,
      );
      sender =
          await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    });

    tearDown(() async {
      sender.close();
      await hub.close();
    });

    void send(Uint8List data) {
      sender.send(data, InternetAddress.loopbackIPv4, hub.port);
    }

    test('too-short datagram (<headerLen) bumps framingErrors', () async {
      send(Uint8List.fromList(const [1, 2, 3]));
      await _waitFraming(hub, 1);
      expect(hub.stats['framingErrors'], greaterThanOrEqualTo(1));
    });

    test('bad magic bumps framingErrors', () async {
      send(_frame(magic: 0xDEADBEEF));
      await _waitFraming(hub, 1);
    });

    test('bad version bumps framingErrors', () async {
      send(_frame(version: 0x99));
      await _waitFraming(hub, 1);
    });

    test('unknown type bumps framingErrors', () async {
      send(_frame(type: 99));
      await _waitFraming(hub, 1);
    });

    test('mismatched declared length bumps framingErrors', () async {
      send(_frame(payloadBytes: 4, declaredLen: 999));
      await _waitFraming(hub, 1);
    });

    test('endpoints getter returns live snapshot', () async {
      expect(hub.endpoints, isEmpty);
      hub.endpointTo(InternetAddress.loopbackIPv4, 9999);
      expect(hub.endpoints.length, 1);
      hub.endpointTo(InternetAddress.loopbackIPv4, 9998);
      expect(hub.endpoints.length, 2);
    });
  });
}
