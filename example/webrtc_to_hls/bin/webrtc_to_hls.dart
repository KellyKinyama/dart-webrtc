// webrtc_to_hls — pull a WHEP H.264 stream and republish it as HLS.
//
//   WHEP source ──RTP H.264──▶ depacketizer ──Access Units──▶
//      MPEG-TS muxer ──188B packets──▶ segmenter ──▶ stream.m3u8 + segNNN.ts
//                                                        ▲
//                                  any number of HLS players over HTTP
//
// HLS scales to thousands of viewers using nothing but cached HTTP.
// WebRTC scales to ~50 with a typical SFU. This bridge is the way you
// get the best of both.
//
// Usage:
//   dart run bin/webrtc_to_hls.dart \
//       --whep http://192.168.56.1:8080/whep \
//       --out  ./hls --segment 4 --window 6
//
//   # Then either play directly:
//   #   ffplay http://localhost:9090/stream.m3u8
//   # or open http://localhost:9090/  for the built-in hls.js player.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:pure_dart_webrtc/h264.dart';
import 'package:pure_dart_webrtc/webrtc/webrtc.dart';

class _Au {
  _Au(this.nalus, this.timestamp, this.isKey);
  final List<Uint8List> nalus;
  final int timestamp; // 90 kHz, from RTP
  final bool isKey;
}

Future<int> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('whep', mandatory: true, help: 'WHEP source URL')
    ..addOption('token', defaultsTo: '')
    ..addOption('bind-ip', defaultsTo: '0.0.0.0')
    ..addOption('announce-ip', defaultsTo: '')
    ..addOption('rtp-port', defaultsTo: '50400')
    ..addOption('http-port', defaultsTo: '9090')
    ..addOption('out', defaultsTo: './hls')
    ..addOption('segment', defaultsTo: '4', help: 'target segment seconds')
    ..addOption('window', defaultsTo: '6', help: 'live playlist window');

  late final ArgResults o;
  try {
    o = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n${parser.usage}');
    return 64;
  }

  final whepUrl = Uri.parse(o['whep'] as String);
  final token = o['token'] as String;
  final bindIp = InternetAddress(o['bind-ip'] as String);
  final announce = (o['announce-ip'] as String).isEmpty
      ? bindIp
      : InternetAddress(o['announce-ip'] as String);
  final rtpPort = int.parse(o['rtp-port'] as String);
  final httpPort = int.parse(o['http-port'] as String);
  final outDir = Directory(o['out'] as String);
  final segSecs = int.parse(o['segment'] as String);
  final windowSize = int.parse(o['window'] as String);
  await outDir.create(recursive: true);

  // 1) Spin up the HLS HTTP server early so players can connect even
  //    before the first segment is produced.
  unawaited(_serveHls(InternetAddress.anyIPv4, httpPort, outDir));
  stdout.writeln('[hls] server: http://0.0.0.0:$httpPort/');
  stdout.writeln('[hls] playlist: http://0.0.0.0:$httpPort/stream.m3u8');

  // 2) Pull AUs from the WHEP source.
  final source = _WhepSource(
    whepUrl: whepUrl,
    token: token,
    bindIp: bindIp,
    announce: announce,
    rtpPort: rtpPort,
  );
  final auStream = await source.start();

  // 3) Mux + segment.
  final segmenter = _HlsSegmenter(
    outDir: outDir,
    targetSecs: segSecs,
    windowSize: windowSize,
  );
  await for (final au in auStream) {
    segmenter.write(au);
  }
  return 0;
}

// ---------------------------------------------------------------------------
// WHEP source
// ---------------------------------------------------------------------------

class _WhepSource {
  _WhepSource({
    required this.whepUrl,
    required this.token,
    required this.bindIp,
    required this.announce,
    required this.rtpPort,
  });
  final Uri whepUrl;
  final String token;
  final InternetAddress bindIp;
  final InternetAddress announce;
  final int rtpPort;

  Future<Stream<_Au>> start() async {
    final pc = RTCPeerConnection(RTCConfiguration(
      defaultVideoCodecs: [H264Codec()],
    ));
    final tx = pc.addTransceiver(
      trackOrKind: MediaKind.video,
      direction: RTCRtpTransceiverDirection.recvonly,
    );
    await pc.bind(bindIp, rtpPort, announceAddress: announce);

    final cands = <RTCIceCandidate>[];
    final gathered = Completer<void>();
    pc.onIceCandidate = (c) {
      if (c == null) {
        if (!gathered.isCompleted) gathered.complete();
        return;
      }
      cands.add(c);
    };

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await gathered.future.timeout(const Duration(seconds: 3),
        onTimeout: () => stderr.writeln('[whep] gather timeout'));
    final fullOffer = _injectCandidates(offer.sdp, cands);

    // POST offer.
    final client = HttpClient();
    final req = await client.postUrl(whepUrl);
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/sdp');
    if (token.isNotEmpty) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final off = utf8.encode(fullOffer);
    req.contentLength = off.length;
    req.add(off);
    final resp = await req.close();
    final ans = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != HttpStatus.created) {
      throw StateError('WHEP POST failed ${resp.statusCode}: $ans');
    }
    await pc
        .setRemoteDescription(RTCSessionDescription(RTCSdpType.answer, ans));
    stdout.writeln('[whep] negotiated, awaiting RTP');

    pc.onConnectionStateChange = (s) => stdout.writeln('[whep] state: $s');

    // 4) Demux RTP into AUs.
    final ctl = StreamController<_Au>();
    final depack = H264RtpDepacketizer();
    final auNalus = <Uint8List>[];
    int? auTs;

    void flush() {
      if (auNalus.isEmpty || auTs == null) return;
      final hasKey = auNalus.any((n) {
        if (n.isEmpty) return false;
        final t = n[0] & 0x1f;
        return t == 5 || t == 7;
      });
      ctl.add(_Au(List.of(auNalus), auTs!, hasKey));
      auNalus.clear();
    }

    tx.receiver.onRtp.listen((rtp) {
      if (rtp.length < 12) return;
      final marker = (rtp[1] & 0x80) != 0;
      final ts = ByteData.sublistView(rtp).getUint32(4, Endian.big);
      final cc = rtp[0] & 0x0f;
      final ext = (rtp[0] & 0x10) != 0;
      var hl = 12 + 4 * cc;
      if (ext && rtp.length >= hl + 4) {
        final el = ByteData.sublistView(rtp).getUint16(hl + 2, Endian.big);
        hl += 4 + 4 * el;
      }
      if (rtp.length <= hl) return;
      final payload = Uint8List.sublistView(rtp, hl);
      if (auTs != null && auTs != ts) {
        flush();
      }
      auTs = ts;
      for (final n in depack.push(payload)) {
        auNalus.add(n);
      }
      if (marker) {
        flush();
        auTs = null;
      }
    });
    return ctl.stream;
  }
}

String _injectCandidates(String sdp, List<RTCIceCandidate> cands) {
  if (cands.isEmpty) return sdp;
  final lines = sdp.split(RegExp(r'\r?\n'));
  final out = <String>[];
  bool inMedia = false, injected = false;
  for (final l in lines) {
    if (l.startsWith('m=')) {
      if (inMedia && !injected) {
        for (final c in cands) {
          out.add('a=${c.candidate}');
        }
        out.add('a=end-of-candidates');
        injected = true;
      }
      inMedia = true;
      injected = false;
    }
    out.add(l);
  }
  if (inMedia && !injected) {
    for (final c in cands) {
      out.add('a=${c.candidate}');
    }
    out.add('a=end-of-candidates');
  }
  return out.join('\r\n');
}

// ---------------------------------------------------------------------------
// HLS segmenter (calls TsMuxer per segment)
// ---------------------------------------------------------------------------

class _HlsSegmenter {
  _HlsSegmenter({
    required this.outDir,
    required this.targetSecs,
    required this.windowSize,
  });
  final Directory outDir;
  final int targetSecs;
  final int windowSize;

  int _seq = 0;
  TsMuxer? _mux;
  int? _segStartTs90k; // first AU PTS in current segment
  int? _lastTs90k;
  Uint8List? _spsCache;
  Uint8List? _ppsCache;

  // [(seqNumber, fileName, durationSeconds), ...] — newest at end.
  final _segments = <_Seg>[];

  void write(_Au au) {
    // Cache SPS/PPS so every keyframe segment can prepend them.
    for (final n in au.nalus) {
      if (n.isEmpty) continue;
      final t = n[0] & 0x1f;
      if (t == 7) _spsCache = Uint8List.fromList(n);
      if (t == 8) _ppsCache = Uint8List.fromList(n);
    }
    _lastTs90k = au.timestamp;

    final shouldRotate = _mux == null ||
        (au.isKey &&
            _segStartTs90k != null &&
            _wrapDelta(au.timestamp, _segStartTs90k!) >= targetSecs * 90000);

    if (shouldRotate) {
      if (_mux == null && !au.isKey) {
        // Wait for first keyframe before starting any segment.
        return;
      }
      _closeSegment();
      _openSegment(au);
    }

    // Inject SPS/PPS in front of every keyframe AU even mid-segment so
    // mid-rollover decoders re-sync.
    final nalus = au.isKey
        ? <Uint8List>[
            if (_spsCache != null && !_hasNal(au.nalus, 7)) _spsCache!,
            if (_ppsCache != null && !_hasNal(au.nalus, 8)) _ppsCache!,
            ...au.nalus,
          ]
        : au.nalus;

    _mux!.writeAccessUnit(nalus, pts90k: au.timestamp, isKey: au.isKey);
  }

  void _openSegment(_Au firstAu) {
    final name = 'seg${_seq.toString().padLeft(6, '0')}.ts';
    final f = File('${outDir.path}/$name');
    _mux = TsMuxer(f.openWrite());
    _segStartTs90k = firstAu.timestamp;
    _segments.add(_Seg(_seq, name, 0));
    _seq++;
  }

  Future<void> _closeSegment() async {
    final m = _mux;
    if (m == null) return;
    final last = _lastTs90k ?? _segStartTs90k!;
    final dur = _wrapDelta(last, _segStartTs90k!) / 90000.0;
    _segments.last = _Seg(_segments.last.seq, _segments.last.name, dur);
    await m.close();
    _mux = null;

    // Trim window + write playlist.
    while (_segments.length > windowSize) {
      final drop = _segments.removeAt(0);
      try {
        File('${outDir.path}/${drop.name}').deleteSync();
      } catch (_) {}
    }
    _writePlaylist();
  }

  void _writePlaylist() {
    if (_segments.isEmpty) return;
    final target = _segments
        .map((s) => s.dur.ceil())
        .fold<int>(1, (a, b) => b > a ? b : a);
    final sb = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:3')
      ..writeln('#EXT-X-TARGETDURATION:$target')
      ..writeln('#EXT-X-MEDIA-SEQUENCE:${_segments.first.seq}');
    for (final s in _segments) {
      sb
        ..writeln('#EXTINF:${s.dur.toStringAsFixed(3)},')
        ..writeln(s.name);
    }
    final tmp = File('${outDir.path}/stream.m3u8.tmp');
    tmp.writeAsStringSync(sb.toString());
    tmp.renameSync('${outDir.path}/stream.m3u8');
  }

  static bool _hasNal(List<Uint8List> nalus, int t) {
    for (final n in nalus) {
      if (n.isNotEmpty && (n[0] & 0x1f) == t) return true;
    }
    return false;
  }

  /// 32-bit-wrap-aware difference (a - b) in 90 kHz ticks.
  static int _wrapDelta(int a, int b) {
    var d = (a - b) & 0xffffffff;
    if (d > 0x80000000) d -= 0x100000000;
    return d.abs();
  }
}

class _Seg {
  _Seg(this.seq, this.name, this.dur);
  final int seq;
  final String name;
  final double dur;
}

// ---------------------------------------------------------------------------
// MPEG-TS muxer (H.264 video only — single program, single PID 256)
// ---------------------------------------------------------------------------

class TsMuxer {
  TsMuxer(this._sink) {
    _writePat();
    _writePmt();
  }
  final IOSink _sink;
  static const int _videoPid = 0x100;
  static const int _pmtPid = 0x1000;
  static const int _videoStreamType = 0x1B; // H.264

  int _ccPat = 0;
  int _ccPmt = 0;
  int _ccVideo = 0;
  int _siCounter = 0;

  Future<void> close() => _sink.close();

  void writeAccessUnit(List<Uint8List> nalus,
      {required int pts90k, required bool isKey}) {
    // Re-emit PAT/PMT every ~10 PES packets.
    if (_siCounter++ % 10 == 0) {
      _writePat();
      _writePmt();
    }

    // Build AU bytes: AUD (NAL type 9) is technically required, but most
    // players accept its absence. Emit Annex-B start codes between NALUs.
    final body = BytesBuilder(copy: false);
    body.add(const [0x00, 0x00, 0x00, 0x01, 0x09, 0xF0]); // AUD
    for (final n in nalus) {
      body.add(const [0x00, 0x00, 0x00, 0x01]);
      body.add(n);
    }

    final pesHeader = _buildPesHeader(pts90k);
    final pesBody = body.toBytes();

    // PCR (27 MHz) for keyframes only — gives players a reliable clock.
    final pcr27m = isKey ? pts90k * 300 : null;

    _writePes(pesHeader, pesBody, pcr27m: pcr27m, randomAccess: isKey);
  }

  // ---- TS section writers ----

  void _writePat() {
    final body = BytesBuilder(copy: false);
    body.addByte(0x00); // table_id PAT
    body.add(_u16(0xB000 | (5 + 4))); // section_syntax + section_length=9
    body.add(_u16(0x0001)); // transport_stream_id
    body.addByte(0xC1); // version=0, current_next=1
    body.addByte(0x00); // section_number
    body.addByte(0x00); // last_section_number
    body.add(_u16(0x0001)); // program_number 1
    body.add(_u16(0xE000 | _pmtPid)); // PMT PID
    final crc = _crc32(body.toBytes());
    body.add(_u32(crc));
    _writeSectionPacket(0x0000, body.toBytes(), () {
      final cc = _ccPat;
      _ccPat = (_ccPat + 1) & 0x0f;
      return cc;
    });
  }

  void _writePmt() {
    final body = BytesBuilder(copy: false);
    body.addByte(0x02); // table_id PMT
    // section_length filled in after we know size; build the rest first
    final tail = BytesBuilder(copy: false);
    tail.add(_u16(0x0001)); // program_number
    tail.addByte(0xC1); // version
    tail.addByte(0x00); // section_number
    tail.addByte(0x00); // last_section_number
    tail.add(_u16(0xE000 | _videoPid)); // PCR_PID = video PID
    tail.add(_u16(0xF000)); // program_info_length=0
    // Stream entry
    tail.addByte(_videoStreamType);
    tail.add(_u16(0xE000 | _videoPid)); // elementary PID
    tail.add(_u16(0xF000)); // ES_info_length=0
    final tailBytes = tail.toBytes();
    final sectionLen = tailBytes.length + 4; // + CRC32
    body.add(_u16(0xB000 | sectionLen));
    body.add(tailBytes);
    final crc = _crc32(body.toBytes());
    body.add(_u32(crc));
    _writeSectionPacket(_pmtPid, body.toBytes(), () {
      final cc = _ccPmt;
      _ccPmt = (_ccPmt + 1) & 0x0f;
      return cc;
    });
  }

  void _writeSectionPacket(int pid, Uint8List section, int Function() nextCc) {
    // PSI section in a single TS packet, payload starts with pointer_field 0.
    final pkt = Uint8List(188)..fillRange(0, 188, 0xff);
    pkt[0] = 0x47;
    pkt[1] = 0x40 | ((pid >> 8) & 0x1f); // PUSI=1
    pkt[2] = pid & 0xff;
    pkt[3] = 0x10 | nextCc(); // payload only
    pkt[4] = 0x00; // pointer_field
    final maxBody = 188 - 5;
    if (section.length > maxBody) {
      throw StateError('PSI too large for single packet');
    }
    pkt.setRange(5, 5 + section.length, section);
    _sink.add(pkt);
  }

  // ---- PES → TS chunks ----

  Uint8List _buildPesHeader(int pts90k) {
    final b = BytesBuilder(copy: false);
    b.add(const [0x00, 0x00, 0x01, 0xE0]); // start code + stream_id (video 0)
    b.add(const [0x00, 0x00]); // PES_packet_length 0 = unbounded (video only)
    b.addByte(0x80); // marker bits, no scrambling, etc.
    b.addByte(0x80); // PTS only
    b.addByte(0x05); // PES_header_data_length (5 bytes of PTS)
    b.add(_pts(0x21, pts90k)); // PTS prefix 0010
    return b.toBytes();
  }

  static Uint8List _pts(int prefix, int pts) {
    // 33-bit PTS encoding per ISO/IEC 13818-1.
    final b = Uint8List(5);
    b[0] = ((prefix & 0xf0) | (((pts >> 30) & 0x07) << 1) | 0x01);
    b[1] = (pts >> 22) & 0xff;
    b[2] = ((pts >> 14) & 0xff) | 0x01;
    b[3] = (pts >> 7) & 0xff;
    b[4] = ((pts << 1) & 0xff) | 0x01;
    return b;
  }

  void _writePes(Uint8List header, Uint8List body,
      {int? pcr27m, required bool randomAccess}) {
    var first = true;
    var offset = 0;
    final whole = BytesBuilder(copy: false)
      ..add(header)
      ..add(body);
    final all = whole.toBytes();

    while (offset < all.length) {
      final pkt = Uint8List(188);
      pkt[0] = 0x47;
      pkt[1] = (first ? 0x40 : 0x00) | ((_videoPid >> 8) & 0x1f);
      pkt[2] = _videoPid & 0xff;
      // continuity counter goes in low nibble of byte 3 (set below).

      var afNeeded = false;
      var afLen = 0;
      Uint8List? af;

      if (first && (pcr27m != null || randomAccess)) {
        afNeeded = true;
        // flags byte + (PCR ? 6 : 0)
        final pcrBytes = pcr27m != null ? 6 : 0;
        afLen = 1 + pcrBytes;
        af = Uint8List(1 + afLen); // [length, flags, ...]
        af[0] = afLen;
        var flags = 0;
        if (randomAccess) flags |= 0x40;
        if (pcr27m != null) flags |= 0x10;
        af[1] = flags;
        if (pcr27m != null) {
          // 33-bit base + 6 reserved + 9 ext (we use ext=0)
          final base = pcr27m ~/ 300;
          af[2] = (base >> 25) & 0xff;
          af[3] = (base >> 17) & 0xff;
          af[4] = (base >> 9) & 0xff;
          af[5] = (base >> 1) & 0xff;
          af[6] = ((base & 0x01) << 7) | 0x7e;
          af[7] = 0x00;
        }
      }

      // Compute payload space
      var headerLen = 4 + (afNeeded ? af!.length : 0);
      var payloadSpace = 188 - headerLen;
      var remaining = all.length - offset;

      // Pad with stuffing if last packet doesn't fill 188.
      if (remaining < payloadSpace) {
        final stuff = payloadSpace - remaining;
        if (afNeeded) {
          final newAf = Uint8List(af!.length + stuff)..fillRange(0, 1, 0);
          newAf[0] = af.length - 1 + stuff; // grow length
          newAf.setRange(1, af.length, af.sublist(1));
          newAf.fillRange(af.length, newAf.length, 0xff);
          af = newAf;
        } else {
          afNeeded = true;
          af = Uint8List(1 + 1 + stuff);
          af[0] = 1 + stuff;
          af[1] = 0x00; // no flags
          for (var i = 2; i < af.length; i++) {
            af[i] = 0xff;
          }
        }
        headerLen = 4 + af.length;
        payloadSpace = 188 - headerLen;
      }

      // Set adaptation_field_control bits in byte 3 + CC.
      pkt[3] = (afNeeded ? 0x30 : 0x10) | _ccVideo;
      _ccVideo = (_ccVideo + 1) & 0x0f;
      var pos = 4;
      if (afNeeded) {
        pkt.setRange(pos, pos + af!.length, af);
        pos += af.length;
      }
      final take = (all.length - offset) > payloadSpace
          ? payloadSpace
          : (all.length - offset);
      pkt.setRange(pos, pos + take, all, offset);
      offset += take;
      _sink.add(pkt);
      first = false;
    }
  }

  // ---- helpers ----

  static Uint8List _u16(int v) =>
      Uint8List.fromList([(v >> 8) & 0xff, v & 0xff]);
  static Uint8List _u32(int v) => Uint8List.fromList(
      [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]);
}

// MPEG-TS uses CRC-32/MPEG-2: poly 0x04C11DB7, init 0xFFFFFFFF, no reflect, no XOR.
int _crc32(Uint8List data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc ^= (b << 24);
    for (var i = 0; i < 8; i++) {
      if ((crc & 0x80000000) != 0) {
        crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF;
      } else {
        crc = (crc << 1) & 0xFFFFFFFF;
      }
    }
  }
  return crc;
}

// ---------------------------------------------------------------------------
// Tiny HTTP server for the .m3u8 + .ts files + a built-in hls.js player.
// ---------------------------------------------------------------------------

Future<void> _serveHls(InternetAddress ip, int port, Directory dir) async {
  final s = await HttpServer.bind(ip, port);
  await for (final req in s) {
    try {
      req.response.headers.set('Access-Control-Allow-Origin', '*');
      var path = req.uri.path;
      if (path == '/' || path == '/index.html') {
        req.response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        req.response.write(_playerHtml);
        await req.response.close();
        continue;
      }
      if (path.contains('..') || path.contains('\\')) {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        continue;
      }
      final f = File('${dir.path}$path');
      if (!f.existsSync()) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        continue;
      }
      if (path.endsWith('.m3u8')) {
        req.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl');
        req.response.headers.set('Cache-Control', 'no-cache');
      } else if (path.endsWith('.ts')) {
        req.response.headers.contentType = ContentType('video', 'mp2t');
        req.response.headers.set('Cache-Control', 'public, max-age=300');
      }
      await f.openRead().pipe(req.response);
    } catch (e) {
      stderr.writeln('[http] $e');
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (_) {}
    }
  }
}

const _playerHtml = r'''
<!doctype html><html><head><meta charset="utf-8"><title>HLS player</title>
<style>body{font:14px sans-serif;background:#111;color:#eee;margin:1em}
video{width:100%;max-width:960px;background:#000;display:block}</style>
<script src="https://cdn.jsdelivr.net/npm/hls.js@1"></script></head><body>
<h2>HLS playback</h2>
<video id="v" controls autoplay muted playsinline></video>
<script>
const v=document.getElementById('v');
const url='/stream.m3u8';
if(v.canPlayType('application/vnd.apple.mpegurl')){v.src=url}
else if(window.Hls&&Hls.isSupported()){const h=new Hls();h.loadSource(url);h.attachMedia(v)}
else{document.body.append('HLS not supported in this browser.')}
</script></body></html>
''';
