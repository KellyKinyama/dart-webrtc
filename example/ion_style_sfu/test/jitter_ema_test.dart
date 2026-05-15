// Phase F — RFC 3550 §A.8 interarrival jitter EMA on Receiver.
//
// Strategy: drive the Receiver with synthetic primary RTP packets back
// to back (arrival delta ≈ 0) but with a controlled RTP-timestamp gap.
// That makes |D| ≈ |0 - tsDelta| = tsDelta (in 90 kHz units for video),
// so a single update yields J = tsDelta / 16 with negligible noise.
// Tolerance is set to a few percent to absorb the microsecond-scale
// arrival jitter that DateTime.now() introduces.

import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart' show MediaKind;
import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

const _videoOffer = '''v=0
o=- 1 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE 0
m=video 9 UDP/TLS/RTP/SAVPF 96 97
c=IN IP4 0.0.0.0
a=ice-ufrag:abcd
a=ice-pwd:efghefghefghefghefgh
a=fingerprint:sha-256 11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22
a=setup:actpass
a=mid:0
a=sendrecv
a=rtpmap:96 VP8/90000
a=rtpmap:97 rtx/90000
a=fmtp:97 apt=96
a=msid:videoStream videoTrack
a=ssrc-group:FID 2001 2002
a=ssrc:2001 cname:user1
a=ssrc:2001 msid:videoStream videoTrack
a=ssrc:2002 cname:user1
a=ssrc:2002 msid:videoStream videoTrack
''';

Uint8List _videoRtp({required int ssrc, required int seq, required int ts}) {
  final out = Uint8List(12);
  out[0] = 0x80;
  out[1] = 96;
  out[2] = (seq >> 8) & 0xff;
  out[3] = seq & 0xff;
  out[4] = (ts >> 24) & 0xff;
  out[5] = (ts >> 16) & 0xff;
  out[6] = (ts >> 8) & 0xff;
  out[7] = ts & 0xff;
  out[8] = (ssrc >> 24) & 0xff;
  out[9] = (ssrc >> 16) & 0xff;
  out[10] = (ssrc >> 8) & 0xff;
  out[11] = ssrc & 0xff;
  return out;
}

Receiver _videoReceiver() {
  final s = parsePublisherOffer(peerId: 'user1', offerSdp: _videoOffer).single;
  return Receiver(
    id: 'user1:0',
    peerId: 'user1',
    kind: MediaKind.video,
    codecs: const [],
    stream: s,
  );
}

void main() {
  test('first primary packet seeds state but yields zero jitter', () {
    final r = _videoReceiver();
    expect(r.jitter, 0);
    expect(r.jitterSamples, 0);
    r.deliverRtp(_videoRtp(ssrc: 2001, seq: 1, ts: 1000));
    expect(r.jitterSamples, 0,
        reason: 'one sample is not enough to compute D');
    expect(r.jitter, 0);
  });

  test('back-to-back arrivals with a 1500-tick TS gap → ~93 units', () {
    final r = _videoReceiver();
    r.deliverRtp(_videoRtp(ssrc: 2001, seq: 1, ts: 0));
    r.deliverRtp(_videoRtp(ssrc: 2001, seq: 2, ts: 1500));
    // |D| ≈ 1500 (arrival delta in microseconds * 90/1e6 is < 1 unit
    // for back-to-back delivery in the same isolate). EMA after one
    // sample: J = 1500 / 16 = 93.75.
    expect(r.jitterSamples, 1);
    expect(r.jitter, inInclusiveRange(80, 110));
  });

  test('repeated identical-TS arrivals converge J toward 0', () {
    final r = _videoReceiver();
    // Seed: same TS over and over → tsDelta = 0 each time, arrival
    // delta is microseconds (rounds to ≤ 1 ts unit at 90 kHz). After
    // many samples the EMA should sit at single digits.
    for (var i = 0; i < 64; i++) {
      r.deliverRtp(_videoRtp(ssrc: 2001, seq: 1 + i, ts: 0));
    }
    expect(r.jitterSamples, 63);
    expect(r.jitter, lessThan(10));
  });

  test('RTX packets do not advance the jitter EMA', () {
    final r = _videoReceiver();
    r.deliverRtp(_videoRtp(ssrc: 2001, seq: 1, ts: 0));
    final before = r.jitterSamples;
    // RTX SSRC = 2002 from the offer; payload doesn't matter for
    // jitter accounting because the EMA only consumes primaries.
    r.deliverRtp(_videoRtp(ssrc: 2002, seq: 100, ts: 999999));
    expect(r.jitterSamples, before);
    expect(r.jitter, 0);
  });
}
