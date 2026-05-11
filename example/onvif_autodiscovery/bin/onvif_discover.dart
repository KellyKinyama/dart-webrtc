// onvif_autodiscovery — find every ONVIF camera on the LAN and print its
// RTSP stream URLs. No external dependencies; raw UDP + HTTP + tiny
// regex-based SOAP/XML parsing.
//
// Two-phase protocol:
//
//   1. WS-Discovery (https://docs.oasis-open.org/ws-dd/discovery/1.1/)
//      Send a SOAP <Probe> for `dn:NetworkVideoTransmitter` to the
//      multicast group 239.255.255.250:3702 over UDP. Cameras reply
//      unicast with a <ProbeMatch> containing one or more service URLs
//      (XAddrs).
//
//   2. ONVIF Media (https://www.onvif.org/profiles/specifications/)
//      POST a SOAP <GetProfiles> request to each XAddr, then
//      <GetStreamUri> for each profile to get the rtsp:// URL.
//
// The library does not implement WS-Security (digest-of-nonce) auth —
// most cameras allow GetProfiles unauthenticated; if yours doesn't,
// supply --user/--pass and we'll add a WS-UsernameToken header.
//
// Output is a tab-separated list, one row per discovered stream:
//
//   <ip>  <model>  <profile-name>  <rtsp-url>
//
// Pipe straight into the multicam viewer:
//
//   dart run bin/onvif_discover.dart |
//     ForEach-Object { ($_ -split "`t")[3] } |
//     ForEach-Object { "--cam"; "cam$($i++)=$_" }

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';

const _wsdMulticast = '239.255.255.250';
const _wsdPort = 3702;

Future<int> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('timeout', defaultsTo: '4', help: 'discovery seconds')
    ..addOption('iface', help: 'interface IP to send probe from')
    ..addOption('user', defaultsTo: '')
    ..addOption('pass', defaultsTo: '')
    ..addFlag('rtsp', defaultsTo: true, help: 'also fetch RTSP URLs');

  late final ArgResults o;
  try {
    o = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n${parser.usage}');
    return 64;
  }

  final timeout = Duration(seconds: int.parse(o['timeout'] as String));
  final ifaceIp = o['iface'] as String?;
  final user = o['user'] as String;
  final pass = o['pass'] as String;
  final fetchRtsp = o['rtsp'] as bool;

  stderr.writeln('[onvif] probing for $timeout ...');
  final devices = await _discover(timeout: timeout, ifaceIp: ifaceIp);
  stderr.writeln('[onvif] found ${devices.length} device(s)');

  for (final d in devices) {
    if (!fetchRtsp) {
      stdout.writeln([d.ip, d.model, '-', d.xaddr].join('\t'));
      continue;
    }
    try {
      final mediaUrl =
          await _getMediaServiceUrl(d.xaddr, user: user, pass: pass);
      final profiles = await _getProfiles(mediaUrl, user: user, pass: pass);
      for (final p in profiles) {
        try {
          final url =
              await _getStreamUri(mediaUrl, p.token, user: user, pass: pass);
          stdout.writeln([d.ip, d.model, p.name, url].join('\t'));
        } catch (e) {
          stderr.writeln('[onvif] ${d.ip} GetStreamUri(${p.token}) failed: $e');
        }
      }
    } catch (e) {
      stderr.writeln('[onvif] ${d.ip} ${d.xaddr} failed: $e');
      stdout.writeln([d.ip, d.model, '-', d.xaddr].join('\t'));
    }
  }
  return 0;
}

// ---------------------------------------------------------------------------
// WS-Discovery
// ---------------------------------------------------------------------------

class _Device {
  _Device({required this.ip, required this.xaddr, required this.model});
  final String ip;
  final String xaddr;
  final String model;
}

Future<List<_Device>> _discover({
  required Duration timeout,
  String? ifaceIp,
}) async {
  final bind =
      ifaceIp == null ? InternetAddress.anyIPv4 : InternetAddress(ifaceIp);
  final sock = await RawDatagramSocket.bind(bind, 0, reuseAddress: true);
  sock.broadcastEnabled = true;
  try {
    sock.joinMulticast(InternetAddress(_wsdMulticast));
  } catch (_) {/* not strictly required for sending */}

  final msgId = 'urn:uuid:${_uuid()}';
  final probe = '<?xml version="1.0" encoding="utf-8"?>'
      '<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope"'
      ' xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing"'
      ' xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"'
      ' xmlns:dn="http://www.onvif.org/ver10/network/wsdl">'
      '<e:Header>'
      '<w:MessageID>$msgId</w:MessageID>'
      '<w:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>'
      '<w:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>'
      '</e:Header><e:Body><d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types>'
      '</d:Probe></e:Body></e:Envelope>';

  final bytes = utf8.encode(probe);
  // Send three times — UDP, no ack.
  for (var i = 0; i < 3; i++) {
    sock.send(bytes, InternetAddress(_wsdMulticast), _wsdPort);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  final found = <String, _Device>{};
  final done = Completer<void>();
  Timer(timeout, () {
    if (!done.isCompleted) done.complete();
  });

  sock.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = sock.receive();
    if (dg == null) return;
    final body = utf8.decode(dg.data, allowMalformed: true);
    final xaddrs = _firstTagText(body, 'XAddrs') ?? '';
    final scopes = _firstTagText(body, 'Scopes') ?? '';
    final model =
        _scopeValue(scopes, 'name') ?? _scopeValue(scopes, 'hardware') ?? '?';
    for (final url in xaddrs.split(RegExp(r'\s+'))) {
      if (url.isEmpty) continue;
      final ip = Uri.tryParse(url)?.host ?? dg.address.address;
      found.putIfAbsent(
          '$ip|$url', () => _Device(ip: ip, xaddr: url, model: model));
    }
  });

  await done.future;
  sock.close();
  return found.values.toList();
}

String? _firstTagText(String xml, String localName) {
  // Match <ns:LocalName>...</ns:LocalName> or <LocalName>...</LocalName>.
  final m =
      RegExp(r'<(?:\w+:)?' + localName + r'\b[^>]*>([^<]*)</', dotAll: true)
          .firstMatch(xml);
  return m?.group(1)?.trim();
}

String? _scopeValue(String scopes, String key) {
  // Scopes are space-separated URIs like onvif://www.onvif.org/name/MyCam
  for (final s in scopes.split(RegExp(r'\s+'))) {
    final i = s.indexOf('/$key/');
    if (i < 0) continue;
    return Uri.decodeComponent(s.substring(i + key.length + 2));
  }
  return null;
}

// ---------------------------------------------------------------------------
// ONVIF Media SOAP
// ---------------------------------------------------------------------------

class _Profile {
  _Profile({required this.token, required this.name});
  final String token;
  final String name;
}

Future<String> _getMediaServiceUrl(String deviceXaddr,
    {required String user, required String pass}) async {
  // GetCapabilities → Capabilities/Media/XAddr.
  final resp = await _soap(
    deviceXaddr,
    action: 'http://www.onvif.org/ver10/device/wsdl/GetCapabilities',
    body:
        '<tds:GetCapabilities xmlns:tds="http://www.onvif.org/ver10/device/wsdl">'
        '<tds:Category>Media</tds:Category></tds:GetCapabilities>',
    user: user,
    pass: pass,
  );
  // Look for the first <XAddr> nested under a <Media>.
  final m = RegExp(
    r'<(?:\w+:)?Media\b[^>]*>.*?<(?:\w+:)?XAddr\b[^>]*>([^<]+)</',
    dotAll: true,
  ).firstMatch(resp);
  if (m == null) {
    throw StateError('GetCapabilities returned no Media XAddr');
  }
  return m.group(1)!.trim();
}

Future<List<_Profile>> _getProfiles(String mediaUrl,
    {required String user, required String pass}) async {
  final resp = await _soap(
    mediaUrl,
    action: 'http://www.onvif.org/ver10/media/wsdl/GetProfiles',
    body:
        '<trt:GetProfiles xmlns:trt="http://www.onvif.org/ver10/media/wsdl"/>',
    user: user,
    pass: pass,
  );
  final out = <_Profile>[];
  // Each profile is <trt:Profiles token="..."> ... <tt:Name>...</tt:Name>
  final reg = RegExp(
    r'<(?:\w+:)?Profiles\b[^>]*\btoken="([^"]+)"[^>]*>.*?<(?:\w+:)?Name\b[^>]*>([^<]+)</',
    dotAll: true,
  );
  for (final m in reg.allMatches(resp)) {
    out.add(_Profile(token: m.group(1)!, name: m.group(2)!.trim()));
  }
  return out;
}

Future<String> _getStreamUri(String mediaUrl, String profileToken,
    {required String user, required String pass}) async {
  final resp = await _soap(
    mediaUrl,
    action: 'http://www.onvif.org/ver10/media/wsdl/GetStreamUri',
    body: '<trt:GetStreamUri xmlns:trt="http://www.onvif.org/ver10/media/wsdl"'
        ' xmlns:tt="http://www.onvif.org/ver10/schema">'
        '<trt:StreamSetup><tt:Stream>RTP-Unicast</tt:Stream>'
        '<tt:Transport><tt:Protocol>RTSP</tt:Protocol></tt:Transport>'
        '</trt:StreamSetup>'
        '<trt:ProfileToken>$profileToken</trt:ProfileToken>'
        '</trt:GetStreamUri>',
    user: user,
    pass: pass,
  );
  final m =
      RegExp(r'<(?:\w+:)?Uri\b[^>]*>([^<]+)</', dotAll: true).firstMatch(resp);
  if (m == null) throw StateError('GetStreamUri returned no Uri');
  return m.group(1)!.trim();
}

Future<String> _soap(
  String url, {
  required String action,
  required String body,
  required String user,
  required String pass,
}) async {
  final sec = user.isEmpty ? '' : _wsSecurityHeader(user, pass);
  final envelope = '<?xml version="1.0" encoding="utf-8"?>'
      '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">'
      '<s:Header>$sec</s:Header><s:Body>$body</s:Body></s:Envelope>';

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client.postUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.contentTypeHeader,
        'application/soap+xml; charset=utf-8; action="$action"');
    final bytes = utf8.encode(envelope);
    req.contentLength = bytes.length;
    req.add(bytes);
    final resp = await req.close();
    final txt = await resp.transform(utf8.decoder).join();
    if (resp.statusCode >= 400) {
      throw StateError(
          'HTTP ${resp.statusCode}: ${txt.substring(0, txt.length > 200 ? 200 : txt.length)}');
    }
    return txt;
  } finally {
    client.close(force: true);
  }
}

/// Minimal WS-UsernameToken (PasswordDigest). Most ONVIF cameras accept this
/// even when the user account would otherwise need HTTP digest auth.
String _wsSecurityHeader(String user, String pass) {
  final nonceBytes =
      List<int>.generate(16, (_) => Random.secure().nextInt(256));
  final created = DateTime.now().toUtc().toIso8601String();
  final digestInput = <int>[
    ...nonceBytes,
    ...utf8.encode(created),
    ...utf8.encode(pass),
  ];
  final digest = base64Encode(_sha1(digestInput));
  final nonce = base64Encode(nonceBytes);
  return '<wsse:Security s:mustUnderstand="1" '
      'xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" '
      'xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">'
      '<wsse:UsernameToken><wsse:Username>$user</wsse:Username>'
      '<wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">$digest</wsse:Password>'
      '<wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">$nonce</wsse:Nonce>'
      '<wsu:Created>$created</wsu:Created>'
      '</wsse:UsernameToken></wsse:Security>';
}

// ---------------------------------------------------------------------------
// Tiny helpers
// ---------------------------------------------------------------------------

String _uuid() {
  final r = Random.secure();
  String hex(int n) =>
      List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  return '${hex(8)}-${hex(4)}-4${hex(3)}-${(8 + r.nextInt(4)).toRadixString(16)}'
      '${hex(3)}-${hex(12)}';
}

// ---- SHA-1 (RFC 3174) for WS-UsernameToken digest --------------------------

List<int> _sha1(List<int> msg) {
  int rotl(int x, int n) => ((x << n) | (x >>> (32 - n))) & 0xffffffff;
  int h0 = 0x67452301,
      h1 = 0xEFCDAB89,
      h2 = 0x98BADCFE,
      h3 = 0x10325476,
      h4 = 0xC3D2E1F0;
  final bits = msg.length * 8;
  final padded = <int>[...msg, 0x80];
  while (padded.length % 64 != 56) {
    padded.add(0);
  }
  for (var i = 7; i >= 0; i--) {
    padded.add((bits >> (i * 8)) & 0xff);
  }
  for (var off = 0; off < padded.length; off += 64) {
    final w = List<int>.filled(80, 0);
    for (var i = 0; i < 16; i++) {
      w[i] = (padded[off + i * 4] << 24) |
          (padded[off + i * 4 + 1] << 16) |
          (padded[off + i * 4 + 2] << 8) |
          padded[off + i * 4 + 3];
    }
    for (var i = 16; i < 80; i++) {
      w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }
    int a = h0, b = h1, c = h2, d = h3, e = h4;
    for (var i = 0; i < 80; i++) {
      int f, k;
      if (i < 20) {
        f = (b & c) | ((~b & 0xffffffff) & d);
        k = 0x5A827999;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ED9EBA1;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8F1BBCDC;
      } else {
        f = b ^ c ^ d;
        k = 0xCA62C1D6;
      }
      final t = (rotl(a, 5) + f + e + k + w[i]) & 0xffffffff;
      e = d;
      d = c;
      c = rotl(b, 30);
      b = a;
      a = t;
    }
    h0 = (h0 + a) & 0xffffffff;
    h1 = (h1 + b) & 0xffffffff;
    h2 = (h2 + c) & 0xffffffff;
    h3 = (h3 + d) & 0xffffffff;
    h4 = (h4 + e) & 0xffffffff;
  }
  final out = <int>[];
  for (final h in [h0, h1, h2, h3, h4]) {
    out
      ..add((h >> 24) & 0xff)
      ..add((h >> 16) & 0xff)
      ..add((h >> 8) & 0xff)
      ..add(h & 0xff);
  }
  return out;
}
