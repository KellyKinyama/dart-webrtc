import 'sdp_parser_builder.dart';

void main() {
  // Build an offer
  final offer = SdpSession()
    ..originUsername = '-'
    ..sessionId = '1234567890'
    ..sessionVersion = '1'
    ..ipAddress = '192.168.1.2'
    ..iceUfrag = 'ufrag_offer'
    ..icePwd = 'pwd_offer'
    ..fingerprint = 'AA:BB:CC:DD:...'
    ..setup = 'actpass'
    ..bundleMids = ['0', '1']
    ..mediaSections = [
      SdpMedia(kind: 'audio', protocol: 'RTP/SAVPF')
        ..mid = '0'
        ..payloadTypes = [111]
        ..codecs = [SdpCodec(payloadType: 111, name: 'opus', clockRate: 48000)]
        ..candidates = [
          SdpIceCandidate(
            foundation: '1',
            component: 1,
            transport: 'udp',
            priority: 2113937151,
            ip: '192.168.1.2',
            port: 54500,
            type: 'host',
          )
        ],
      SdpMedia(kind: 'video', protocol: 'RTP/SAVPF')
        ..mid = '1'
        ..payloadTypes = [96]
        ..codecs = [SdpCodec(payloadType: 96, name: 'VP8', clockRate: 90000)]
    ];

  final offerText = offer.toSdpString();
  print('Offer:\n$offerText');

  // Parse it back
  final parsed = SdpParser.parse(offerText);
  print('\nParsed back:\n${parsed.toSdpString()}');
}
