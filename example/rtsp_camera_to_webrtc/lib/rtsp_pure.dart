// Shared building blocks used by the pure-Dart RTSP-to-WebRTC examples.
//
// Exposes:
//   - [AccessUnit]      : H.264 access unit (a list of NALUs + flags)
//   - [AuHub]           : per-camera broadcast bus with keyframe cache
//   - [RtspClient]      : minimal RTSP/1.0 client (TCP-interleaved,
//                         Basic + Digest auth, GET_PARAMETER keepalive)
//
// Zero external dependencies — uses only `dart:*` plus the public
// `package:pure_dart_webrtc` H.264 helpers.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pure_dart_webrtc/h264.dart';

// ---------------------------------------------------------------------------
// AccessUnit + AuHub
// ---------------------------------------------------------------------------

class AccessUnit {
  /// NALUs in delivery order.
  final List<Uint8List> nalus;

  /// True if this AU contains an IDR slice (NAL type 5) or SPS (type 7).
  final bool hasKeyframeSlice;
  AccessUnit(this.nalus, this.hasKeyframeSlice);
}

class AuHub {
  AuHub({this.name = ''});
  final String name;

  final _subs = <StreamController<AccessUnit>>{};

  /// Latest SPS / PPS seen on the stream.
  Uint8List? sps;
  Uint8List? pps;

  /// Last keyframe AU. Sent to each new subscriber so the browser
  /// decoder syncs immediately.
  AccessUnit? lastKeyframeAu;

  Stream<AccessUnit> subscribe() {
    final ctl = StreamController<AccessUnit>(sync: true);
    ctl.onCancel = () => _subs.remove(ctl);
    _subs.add(ctl);

    final kf = lastKeyframeAu;
    if (kf != null) {
      scheduleMicrotask(() {
        if (!ctl.isClosed) ctl.add(_keyframeWithParams(kf));
      });
    }
    return ctl.stream;
  }

  AccessUnit _keyframeWithParams(AccessUnit kf) {
    final s = sps;
    final p = pps;
    final hasSps = kf.nalus.any((n) => n.isNotEmpty && (n[0] & 0x1f) == 7);
    final hasPps = kf.nalus.any((n) => n.isNotEmpty && (n[0] & 0x1f) == 8);
    if ((s == null || hasSps) && (p == null || hasPps)) return kf;
    final out = <Uint8List>[];
    if (s != null && !hasSps) out.add(s);
    if (p != null && !hasPps) out.add(p);
    out.addAll(kf.nalus);
    return AccessUnit(out, true);
  }

  void publish(AccessUnit au) {
    for (final n in au.nalus) {
      if (n.isEmpty) continue;
      final t = n[0] & 0x1f;
      if (t == 7) sps = Uint8List.fromList(n);
      if (t == 8) pps = Uint8List.fromList(n);
    }
    if (au.hasKeyframeSlice) lastKeyframeAu = au;
    for (final s in _subs.toList()) {
      if (!s.isClosed) s.add(au);
    }
  }
}

// ---------------------------------------------------------------------------
// RTSP client (interleaved TCP)
// ---------------------------------------------------------------------------

class RtspClient {
  RtspClient({
    required this.url,
    required this.hub,
    this.overrideUser,
    this.overridePass,
    this.logTag = 'rtsp',
  });

  final String url;
  final AuHub hub;
  final String? overrideUser;
  final String? overridePass;
  final String logTag;

  late Socket _socket;
  Uri get _uri => Uri.parse(url);

  String? _user;
  String? _pass;

  int _cseq = 0;
  String? _session;
  String? _wwwAuthenticate;

  String _videoControlUrl = '';
  int _videoPt = 96;
  static const int _chRtp = 0;
  static const int _chRtcp = 1;
  final _depack = H264RtpDepacketizer();

  final _auNalus = <Uint8List>[];
  int? _auTs;

  final _rx = BytesBuilder(copy: false);
  final _pending = <int, Completer<_RtspResponse>>{};

  void _log(String msg) => stdout.writeln('[$logTag] $msg');
  void _err(String msg) => stderr.writeln('[$logTag] $msg');

  /// Run forever, reconnecting with back-off on any error.
  Future<void> runForever() async {
    while (true) {
      try {
        await run();
      } catch (e) {
        _err('crashed: $e');
      }
      _err('reconnecting in 3s ...');
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  Future<void> run() async {
    final u = _uri;
    final userinfo = u.userInfo;
    if (userinfo.isNotEmpty) {
      final i = userinfo.indexOf(':');
      _user = i < 0 ? userinfo : userinfo.substring(0, i);
      _pass = i < 0 ? '' : userinfo.substring(i + 1);
    }
    if (overrideUser != null) _user = overrideUser;
    if (overridePass != null) _pass = overridePass;

    final port = u.hasPort ? u.port : 554;
    _log('connecting to ${u.host}:$port ...');
    _socket = await Socket.connect(u.host, port,
        timeout: const Duration(seconds: 10));

    final done = Completer<void>();
    _socket.listen(_onBytes, onDone: () {
      _log('socket closed');
      if (!done.isCompleted) done.complete();
    }, onError: (Object e) {
      _err('socket error: $e');
      if (!done.isCompleted) done.completeError(e);
    }, cancelOnError: true);

    final base = '${u.scheme}://${u.host}:$port${u.path}'
        '${u.hasQuery ? '?${u.query}' : ''}';

    var resp = await _request('OPTIONS', base);
    if (resp.status == 401) _wwwAuthenticate = resp.headers['www-authenticate'];

    resp = await _request('DESCRIBE', base, headers: {
      'Accept': 'application/sdp',
    });
    if (resp.status == 401) {
      _wwwAuthenticate = resp.headers['www-authenticate'];
      resp = await _request('DESCRIBE', base, headers: {
        'Accept': 'application/sdp',
      });
    }
    if (resp.status != 200) {
      throw StateError('DESCRIBE failed: ${resp.status} ${resp.reason}');
    }
    _parseSdp(resp.body, baseUrl: resp.headers['content-base'] ?? base);

    if (_videoControlUrl.isEmpty) {
      throw StateError('No H.264 video track in SDP');
    }
    _log('video PT=$_videoPt control=$_videoControlUrl');

    resp = await _request('SETUP', _videoControlUrl, headers: {
      'Transport': 'RTP/AVP/TCP;unicast;interleaved=$_chRtp-$_chRtcp',
    });
    if (resp.status != 200) {
      throw StateError('SETUP failed: ${resp.status} ${resp.reason}');
    }
    final session = resp.headers['session'];
    if (session != null) _session = session.split(';').first.trim();
    _log('session=$_session');

    resp = await _request('PLAY', base, headers: {'Range': 'npt=0.000-'});
    if (resp.status != 200) {
      throw StateError('PLAY failed: ${resp.status} ${resp.reason}');
    }
    _log('PLAY OK — streaming H.264');

    final keepalive = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        await _request('GET_PARAMETER', base)
            .timeout(const Duration(seconds: 10));
      } catch (_) {}
    });

    try {
      await done.future;
    } finally {
      keepalive.cancel();
      try {
        _socket.destroy();
      } catch (_) {}
    }
  }

  // -- request / response --

  Future<_RtspResponse> _request(
    String method,
    String url, {
    Map<String, String> headers = const {},
  }) {
    _cseq++;
    final cseq = _cseq;
    final h = <String, String>{
      'CSeq': '$cseq',
      'User-Agent': 'pure_dart_webrtc/0.1',
      ...headers,
    };
    if (_session != null) h.putIfAbsent('Session', () => _session!);
    final auth = _buildAuth(method, url);
    if (auth != null) h.putIfAbsent('Authorization', () => auth);

    final sb = StringBuffer('$method $url RTSP/1.0\r\n');
    h.forEach((k, v) => sb.write('$k: $v\r\n'));
    sb.write('\r\n');
    _socket.write(sb.toString());

    final c = Completer<_RtspResponse>();
    _pending[cseq] = c;
    return c.future;
  }

  String? _buildAuth(String method, String url) {
    final user = _user;
    if (user == null) return null;
    final pass = _pass ?? '';
    final wa = _wwwAuthenticate;
    if (wa == null || wa.toLowerCase().startsWith('basic')) {
      return 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
    }
    if (wa.toLowerCase().startsWith('digest')) {
      return _buildDigest(method, url, user, pass, wa);
    }
    return null;
  }

  String _buildDigest(
      String method, String url, String user, String pass, String wa) {
    String? get(String k) {
      final m = RegExp('$k="?([^",]+)"?', caseSensitive: false).firstMatch(wa);
      return m?.group(1);
    }

    final realm = get('realm') ?? '';
    final nonce = get('nonce') ?? '';
    final qop = get('qop');
    final ha1 = _md5Hex('$user:$realm:$pass');
    final ha2 = _md5Hex('$method:$url');
    String response;
    String extra = '';
    if (qop != null && qop.contains('auth')) {
      const nc = '00000001';
      final cnonce = Random.secure().nextInt(0x7fffffff).toRadixString(16);
      response = _md5Hex('$ha1:$nonce:$nc:$cnonce:auth:$ha2');
      extra = ', qop=auth, nc=$nc, cnonce="$cnonce"';
    } else {
      response = _md5Hex('$ha1:$nonce:$ha2');
    }
    return 'Digest username="$user", realm="$realm", nonce="$nonce", '
        'uri="$url", response="$response"$extra';
  }

  // -- inbound demux --

  void _onBytes(Uint8List data) {
    _rx.add(data);
    while (true) {
      final buf = _rx.toBytes();
      if (buf.isEmpty) {
        _rx.clear();
        return;
      }
      if (buf[0] == 0x24) {
        if (buf.length < 4) {
          _rx
            ..clear()
            ..add(buf);
          return;
        }
        final ch = buf[1];
        final len = (buf[2] << 8) | buf[3];
        if (buf.length < 4 + len) {
          _rx
            ..clear()
            ..add(buf);
          return;
        }
        final rtp = Uint8List.sublistView(buf, 4, 4 + len);
        _onRtp(ch, rtp);
        _rx
          ..clear()
          ..add(Uint8List.sublistView(buf, 4 + len));
        continue;
      }
      final hdrEnd = _findCrlfCrlf(buf);
      if (hdrEnd < 0) {
        _rx
          ..clear()
          ..add(buf);
        return;
      }
      final headerBytes = Uint8List.sublistView(buf, 0, hdrEnd);
      final headerText = utf8.decode(headerBytes, allowMalformed: true);
      final lines = headerText.split('\r\n');
      final headers = <String, String>{};
      for (final l in lines.skip(1)) {
        final i = l.indexOf(':');
        if (i <= 0) continue;
        headers[l.substring(0, i).trim().toLowerCase()] =
            l.substring(i + 1).trim();
      }
      final cl = int.tryParse(headers['content-length'] ?? '0') ?? 0;
      final total = hdrEnd + 4 + cl;
      if (buf.length < total) {
        _rx
          ..clear()
          ..add(buf);
        return;
      }
      final body = cl == 0
          ? ''
          : utf8.decode(Uint8List.sublistView(buf, hdrEnd + 4, total),
              allowMalformed: true);
      final firstLine = lines.first.split(' ');
      final status =
          int.tryParse(firstLine.length > 1 ? firstLine[1] : '0') ?? 0;
      final reason = firstLine.length > 2 ? firstLine.sublist(2).join(' ') : '';
      final cseq = int.tryParse(headers['cseq'] ?? '0') ?? 0;
      final resp = _RtspResponse(
        status: status,
        reason: reason,
        headers: headers,
        body: body,
      );
      _log('<- $status $reason (CSeq=$cseq, ${body.length}B body)');
      final c = _pending.remove(cseq);
      if (c != null && !c.isCompleted) c.complete(resp);
      _rx
        ..clear()
        ..add(Uint8List.sublistView(buf, total));
    }
  }

  static int _findCrlfCrlf(Uint8List b) {
    for (var i = 0; i + 3 < b.length; i++) {
      if (b[i] == 0x0d &&
          b[i + 1] == 0x0a &&
          b[i + 2] == 0x0d &&
          b[i + 3] == 0x0a) {
        return i;
      }
    }
    return -1;
  }

  void _onRtp(int channel, Uint8List rtp) {
    if (channel != _chRtp) return;
    if (rtp.length < 12) return;
    final marker = (rtp[1] & 0x80) != 0;
    final pt = rtp[1] & 0x7f;
    if (pt != _videoPt) return;
    final ts = ByteData.sublistView(rtp).getUint32(4, Endian.big);
    final cc = rtp[0] & 0x0f;
    final ext = (rtp[0] & 0x10) != 0;
    var headerLen = 12 + 4 * cc;
    if (ext && rtp.length >= headerLen + 4) {
      final extLen =
          ByteData.sublistView(rtp).getUint16(headerLen + 2, Endian.big);
      headerLen += 4 + 4 * extLen;
    }
    if (rtp.length <= headerLen) return;
    final payload = Uint8List.sublistView(rtp, headerLen);

    if (_auTs != null && _auTs != ts) _flushAu();
    _auTs = ts;
    for (final nalu in _depack.push(payload)) {
      _auNalus.add(nalu);
    }
    if (marker) _flushAu();
  }

  void _flushAu() {
    if (_auNalus.isEmpty) {
      _auTs = null;
      return;
    }
    final hasKey = _auNalus.any((n) {
      if (n.isEmpty) return false;
      final t = n[0] & 0x1f;
      return t == 5 || t == 7;
    });
    final au = AccessUnit(List.of(_auNalus), hasKey);
    _auNalus.clear();
    _auTs = null;
    hub.publish(au);
  }

  void _parseSdp(String body, {required String baseUrl}) {
    String? videoControl;
    int? pt;
    String? sprop;
    bool inVideo = false;
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';

    for (final raw in body.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.startsWith('m=')) {
        inVideo = line.startsWith('m=video');
        if (inVideo) {
          final parts = line.split(' ');
          if (parts.length >= 4) pt = int.tryParse(parts[3]);
        }
        continue;
      }
      if (!inVideo) continue;
      if (line.startsWith('a=control:')) {
        final v = line.substring('a=control:'.length).trim();
        if (v == '*' || v.isEmpty) {
          videoControl = baseUrl;
        } else if (v.startsWith('rtsp://')) {
          videoControl = v;
        } else {
          videoControl = '$base$v';
        }
      } else if (line.startsWith('a=rtpmap:')) {
        final m = RegExp(r'^a=rtpmap:(\d+)\s+([^/]+)/(\d+)').firstMatch(line);
        if (m != null && pt != null && int.parse(m.group(1)!) == pt) {
          if (m.group(2)!.toUpperCase() != 'H264') {
            _err('WARNING: video codec is ${m.group(2)}, not H264');
          }
        }
      } else if (line.startsWith('a=fmtp:')) {
        final m = RegExp(r'^a=fmtp:(\d+)\s+(.*)').firstMatch(line);
        if (m != null && pt != null && int.parse(m.group(1)!) == pt) {
          for (final kv in m.group(2)!.split(';')) {
            final parts = kv.trim().split('=');
            if (parts.length == 2 &&
                parts[0].toLowerCase() == 'sprop-parameter-sets') {
              sprop = parts[1];
            }
          }
        }
      }
    }
    if (videoControl != null) _videoControlUrl = videoControl;
    if (pt != null) _videoPt = pt;
    if (sprop != null) {
      for (final n in decodeSpropParameterSets(sprop)) {
        if (n.isEmpty) continue;
        final t = n[0] & 0x1f;
        if (t == 7) hub.sps = n;
        if (t == 8) hub.pps = n;
      }
      _log('sprop SPS=${hub.sps?.length ?? 0}B PPS=${hub.pps?.length ?? 0}B');
    }
  }
}

class _RtspResponse {
  final int status;
  final String reason;
  final Map<String, String> headers;
  final String body;
  _RtspResponse({
    required this.status,
    required this.reason,
    required this.headers,
    required this.body,
  });
}

// ---------------------------------------------------------------------------
// MD5 (small RFC 1321 implementation, used for Digest auth)
// ---------------------------------------------------------------------------

String _md5Hex(String s) {
  final b = _md5(utf8.encode(s));
  final sb = StringBuffer();
  for (final byte in b) {
    sb.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

Uint8List _md5(List<int> input) {
  const r = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, //
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];
  const k = <int>[
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, //
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
  ];
  final msg = BytesBuilder(copy: false)..add(input);
  final origLenBits = input.length * 8;
  msg.addByte(0x80);
  while (msg.length % 64 != 56) {
    msg.addByte(0);
  }
  final lenBytes = Uint8List(8);
  ByteData.sublistView(lenBytes).setUint64(0, origLenBits, Endian.little);
  msg.add(lenBytes);
  final bytes = msg.toBytes();
  int a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
  for (var off = 0; off < bytes.length; off += 64) {
    final m = List<int>.filled(16, 0);
    final bd = ByteData.sublistView(bytes, off, off + 64);
    for (var i = 0; i < 16; i++) {
      m[i] = bd.getUint32(i * 4, Endian.little);
    }
    int A = a0, B = b0, C = c0, D = d0;
    for (var i = 0; i < 64; i++) {
      int f, g;
      if (i < 16) {
        f = (B & C) | ((~B & 0xffffffff) & D);
        g = i;
      } else if (i < 32) {
        f = (D & B) | ((~D & 0xffffffff) & C);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = B ^ C ^ D;
        g = (3 * i + 5) % 16;
      } else {
        f = C ^ (B | (~D & 0xffffffff));
        g = (7 * i) % 16;
      }
      f = (f + A + k[i] + m[g]) & 0xffffffff;
      A = D;
      D = C;
      C = B;
      final s = r[i];
      B = (B + (((f << s) | (f >>> (32 - s))) & 0xffffffff)) & 0xffffffff;
    }
    a0 = (a0 + A) & 0xffffffff;
    b0 = (b0 + B) & 0xffffffff;
    c0 = (c0 + C) & 0xffffffff;
    d0 = (d0 + D) & 0xffffffff;
  }
  final out = Uint8List(16);
  final bdo = ByteData.sublistView(out);
  bdo.setUint32(0, a0, Endian.little);
  bdo.setUint32(4, b0, Endian.little);
  bdo.setUint32(8, c0, Endian.little);
  bdo.setUint32(12, d0, Endian.little);
  return out;
}
