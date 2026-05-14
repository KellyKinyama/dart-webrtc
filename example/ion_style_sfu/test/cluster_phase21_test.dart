// Phase 21 \u2014 per-bridge throughput counters (TX/RX \u00d7 control/RTP/RTCP).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

Future<Map<String, Object?>> _getJson(int port, String path) async {
  final c = HttpClient();
  try {
    final req = await c.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, Object?>;
  } finally {
    c.close(force: true);
  }
}

Future<String> _getText(int port, String path) async {
  final c = HttpClient();
  try {
    final req = await c.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    final resp = await req.close();
    return await resp.transform(utf8.decoder).join();
  } finally {
    c.close(force: true);
  }
}

String _sessionOwnedBy(String peerId, List<ClusterPeer> peers) {
  final loc = RoomLocator(selfId: peerId, peers: peers);
  for (var i = 0; i < 1000; i++) {
    final sid = 'p21-$i';
    if (loc.ownerOf(sid)?.id == peerId) return sid;
  }
  fail('no session id mapped to $peerId in 1000 tries');
}

Future<void> _waitFor(
  FutureOr<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
  Duration interval = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) return;
    await Future.delayed(interval);
  }
  fail('predicate never became true within $timeout');
}

void main() {
  group('Cluster bridge throughput counters (Phase 21)', () {
    test(
        'control TX/RX counters increment as keepalive ping/pong flows',
        () async {
      final ownerPeer = ClusterPeer.parse('127.0.0.1:18901:18902');
      final fakePeer = ClusterPeer.parse('127.0.0.1:18903:18904');
      final owner = await runIonStyleSfuServer(
        ip: '127.0.0.1',
        port: ownerPeer.httpPort,
        rtpBase: 61400,
        announceIp: '127.0.0.1',
        quiet: true,
        clusterPeers: [ownerPeer, fakePeer],
        selfClusterId: ownerPeer.id,
        relayPort: ownerPeer.relayPort,
        bridgeKeepaliveMs: 100,
      );
      final fakeHub = await UdpRelayHub.bind(
        bindAddress: InternetAddress.loopbackIPv4,
        port: fakePeer.relayPort,
      );
      final fakeSfu = Sfu(WebRTCTransportConfig(
        bindAddress: InternetAddress.loopbackIPv4,
        rtpBasePort: 61700,
      ));
      addTearDown(() async {
        await owner.close();
        await fakeHub.close();
        await fakeSfu.close();
      });

      final sid = _sessionOwnedBy(ownerPeer.id, [ownerPeer, fakePeer]);
      final transport = fakeHub.endpointTo(
        InternetAddress('127.0.0.1'),
        ownerPeer.relayPort,
      );
      final relay = RelayPeer.over(
        remoteId: 'cluster:${fakePeer.id}:$sid',
        session: fakeSfu.getSession(sid),
        transport: transport,
      );
      transport.sendControl({
        'type': 'cascade-hello',
        'sessionId': sid,
        'fromSfu': fakePeer.id,
      });
      await Future.delayed(const Duration(milliseconds: 250));
      relay.start();
      await _waitFor(() => relay.established);

      // Wait for at least three keepalive pings to have round-tripped
      // \u2014 enough to be confident the counters are wired up.
      await _waitFor(() async {
        final c = await _getJson(ownerPeer.httpPort, '/cluster');
        final bridges = (c['bridges'] as List).cast<Map>();
        for (final b in bridges) {
          if (b['sessionId'] != sid) continue;
          if (!(b['bridgeId'] as String).startsWith('inbound:')) continue;
          if ((b['txControlPackets'] as int) >= 3 &&
              (b['rxControlPackets'] as int) >= 3) {
            return true;
          }
        }
        return false;
      });

      final c = await _getJson(ownerPeer.httpPort, '/cluster');
      final bridges = (c['bridges'] as List).cast<Map>();
      final hb = bridges.firstWhere(
        (b) =>
            b['sessionId'] == sid &&
            (b['bridgeId'] as String).startsWith('inbound:'),
      );

      // TX side \u2014 we sent at least the helloAck plus several pings.
      expect(hb['txControlPackets'] as int, greaterThanOrEqualTo(3));
      expect(hb['txControlBytes'] as int, greaterThan(0));
      // RX side \u2014 hello + cascade-hello replay + several pongs.
      expect(hb['rxControlPackets'] as int, greaterThanOrEqualTo(3));
      expect(hb['rxControlBytes'] as int, greaterThan(0));
      // Bytes should always be \u2265 packets (each frame is at least 1 byte).
      expect(hb['txControlBytes'] as int,
          greaterThanOrEqualTo(hb['txControlPackets'] as int));
      expect(hb['rxControlBytes'] as int,
          greaterThanOrEqualTo(hb['rxControlPackets'] as int));
      // No media on this bridge \u2014 RTP/RTCP counters stay zero.
      expect(hb['txRtpPackets'], 0);
      expect(hb['rxRtpPackets'], 0);
      expect(hb['txRtcpPackets'], 0);
      expect(hb['rxRtcpPackets'], 0);

      // /metrics carries the new counter families.
      final metrics = await _getText(ownerPeer.httpPort, '/metrics');
      expect(metrics,
          contains('ionsfu_cluster_bridge_tx_control_packets_total{'));
      expect(metrics,
          contains('ionsfu_cluster_bridge_rx_control_packets_total{'));
      expect(metrics, contains('ionsfu_cluster_bridge_tx_rtp_packets_total{'));
      expect(metrics, contains('ionsfu_cluster_bridge_rx_rtp_packets_total{'));
      expect(metrics, contains('ionsfu_cluster_bridge_tx_rtcp_bytes_total{'));
      expect(metrics, contains('ionsfu_cluster_bridge_rx_rtcp_bytes_total{'));
    });
  });
}
