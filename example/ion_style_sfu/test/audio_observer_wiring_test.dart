// Phase 4 — verify Receiver feeds the AudioObserver from the RFC 6464
// extension on inbound RTP packets.

import 'dart:typed_data';

import 'package:pure_dart_webrtc/webrtc/webrtc.dart' show MediaKind;
import 'package:pure_dart_webrtc_ion_style_sfu/ion_style_sfu.dart';
import 'package:test/test.dart';

const _audioOffer = '''v=0
o=- 1 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE 0
m=audio 9 UDP/TLS/RTP/SAVPF 111
c=IN IP4 0.0.0.0
a=ice-ufrag:abcd
a=ice-pwd:efghefghefghefghefgh
a=fingerprint:sha-256 11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22
a=setup:actpass
a=mid:0
a=sendrecv
a=rtpmap:111 opus/48000/2
a=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level
a=msid:audioStream audioTrack
a=ssrc:7777 cname:user1
a=ssrc:7777 msid:audioStream audioTrack
''';

/// Build an Opus RTP packet with a one-byte audio-level extension.
/// [extId] selects the extmap id; [level] is the raw 7-bit value (0 =
/// loudest, 127 = silence).
Uint8List _audioRtp({
  required int ssrc,
  required int extId,
  required int level,
  bool voice = true,
}) {
  // One-byte form, len-1=0 → header byte = (extId<<4)|0; payload byte
  // V|level. Pad to 4-byte multiple → 1+1+2 = 4.
  final hdr = ((extId & 0x0f) << 4);
  final lvlByte = ((voice ? 0x80 : 0) | (level & 0x7f));
  final ext = <int>[hdr, lvlByte, 0, 0];
  final out = Uint8List(12 + 4 + ext.length + 4);
  out[0] = 0x90; // V=2, X=1
  out[1] = 111; // PT=opus
  out[2] = 0;
  out[3] = 1;
  out[8] = (ssrc >> 24) & 0xff;
  out[9] = (ssrc >> 16) & 0xff;
  out[10] = (ssrc >> 8) & 0xff;
  out[11] = ssrc & 0xff;
  out[12] = 0xBE;
  out[13] = 0xDE;
  out[14] = 0;
  out[15] = ext.length ~/ 4;
  out.setAll(16, ext);
  return out;
}

void main() {
  test('parsePublisherOffer surfaces audioLevelExtId on audio streams',
      () {
    final s =
        parsePublisherOffer(peerId: 'user1', offerSdp: _audioOffer).single;
    expect(s.kind, 'audio');
    expect(s.audioLevelExtId, 1);
    expect(s.primarySsrc, 7777);
  });

  test('Receiver feeds AudioObserver with decoded level + voice flag',
      () async {
    final stream =
        parsePublisherOffer(peerId: 'user1', offerSdp: _audioOffer).single;
    final ob = AudioObserver(threshold: 0, filter: 5, smoothing: 1.0);
    final receiver = Receiver(
      id: 'user1:0',
      peerId: 'user1',
      kind: MediaKind.audio,
      codecs: const [],
      stream: stream,
    );
    receiver.audioObserver = ob;

    receiver.deliverRtp(_audioRtp(ssrc: 7777, extId: 1, level: 10));
    final fut = ob.events.first;
    ob.emitNow();
    final ev = await fut;

    expect(ev.speakers, ['user1:0']);
    // level=10 → loudness = 127 - 10 = 117
    expect(ev.scores.single, 117);
  });

  test('Receiver does not observe when audio-level extmap is absent',
      () async {
    // Offer without the extmap line.
    final noExtOffer = _audioOffer.replaceAll(
      'a=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level\n',
      '',
    );
    final stream =
        parsePublisherOffer(peerId: 'user1', offerSdp: noExtOffer).single;
    expect(stream.audioLevelExtId, isNull);

    final ob = AudioObserver(threshold: 0, filter: 5, smoothing: 1.0);
    final receiver = Receiver(
      id: 'user1:0',
      peerId: 'user1',
      kind: MediaKind.audio,
      codecs: const [],
      stream: stream,
    );
    receiver.audioObserver = ob;

    receiver.deliverRtp(_audioRtp(ssrc: 7777, extId: 1, level: 10));
    final fut = ob.events.first;
    ob.emitNow();
    final ev = await fut;
    expect(ev.speakers, isEmpty);
  });
}
