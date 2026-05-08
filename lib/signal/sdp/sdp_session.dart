// SDP (RFC 4566) data model and serializer.
//
// Each SDP line has the form `<key>=<value>\r\n`. Sessions and media
// sections are sequences of lines; the lines that appear before the first
// `m=` belong to the session, every line after an `m=` until the next `m=`
// belongs to that media section.
//
// This file defines a typed model (`SdpSession`, `SdpMedia`, attribute
// helpers) plus a forgiving line-based parser and a deterministic writer
// suited for WebRTC offer/answer exchange.

import 'dart:convert';

/// Parses or builds a single SDP session description.
class SdpSession {
  /// Protocol version (`v=`). Always 0.
  int version;

  /// Origin (`o=username sessId sessVersion nettype addrtype unicast-address`).
  SdpOrigin origin;

  /// Session name (`s=`). WebRTC implementations universally use `-`.
  String sessionName;

  /// Optional session-level connection (`c=...`).
  SdpConnection? connection;

  /// Timing (`t=start stop`); WebRTC uses `0 0`.
  String timing;

  /// Session-level attributes (`a=...`). Includes `group:BUNDLE`,
  /// `msid-semantic:`, `extmap-allow-mixed`, etc.
  final List<SdpAttribute> attributes;

  /// One entry per `m=` line.
  final List<SdpMedia> media;

  SdpSession({
    this.version = 0,
    required this.origin,
    this.sessionName = '-',
    this.connection,
    this.timing = '0 0',
    List<SdpAttribute>? attributes,
    List<SdpMedia>? media,
  })  : attributes = attributes ?? [],
        media = media ?? [];

  /// First session-level attribute matching [name], or null.
  SdpAttribute? attr(String name) =>
      attributes.where((a) => a.name == name).firstOrNull;

  /// All session-level attributes matching [name].
  Iterable<SdpAttribute> attrs(String name) =>
      attributes.where((a) => a.name == name);

  /// Names of media sections that participate in BUNDLE
  /// (from `a=group:BUNDLE 0 1 2`). Empty if no group line.
  List<String> get bundleMids {
    final g = attr('group');
    if (g == null) return const [];
    final v = g.value ?? '';
    final parts = v.split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first != 'BUNDLE') return const [];
    return parts.skip(1).toList();
  }

  /// Serialize to a CRLF-terminated SDP string.
  String write() {
    final b = StringBuffer();
    b.write('v=$version\r\n');
    b.write('o=${origin.write()}\r\n');
    b.write('s=$sessionName\r\n');
    if (connection != null) b.write('c=${connection!.write()}\r\n');
    b.write('t=$timing\r\n');
    for (final a in attributes) {
      b.write('a=${a.write()}\r\n');
    }
    for (final m in media) {
      m.writeTo(b);
    }
    return b.toString();
  }

  @override
  String toString() => write();

  /// Forgiving line-based SDP parser. Unknown attributes are kept verbatim
  /// as [SdpAttribute] entries, so round-tripping a description preserves
  /// fields this model doesn't yet understand.
  factory SdpSession.parse(String text) {
    SdpOrigin? origin;
    int version = 0;
    String sessionName = '-';
    SdpConnection? sessionConnection;
    String timing = '0 0';
    final sessionAttrs = <SdpAttribute>[];
    final media = <SdpMedia>[];
    SdpMedia? current;

    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trimRight();
      if (line.isEmpty) continue;
      if (line.length < 2 || line[1] != '=') continue;
      final key = line[0];
      final value = line.substring(2);

      if (key == 'm') {
        current = SdpMedia.parseMLine(value);
        media.add(current);
        continue;
      }
      if (current != null) {
        current.acceptLine(key, value);
        continue;
      }
      switch (key) {
        case 'v':
          version = int.tryParse(value) ?? 0;
          break;
        case 'o':
          origin = SdpOrigin.parse(value);
          break;
        case 's':
          sessionName = value;
          break;
        case 'c':
          sessionConnection = SdpConnection.parse(value);
          break;
        case 't':
          timing = value;
          break;
        case 'a':
          sessionAttrs.add(SdpAttribute.parse(value));
          break;
      }
    }

    return SdpSession(
      version: version,
      origin: origin ??
          SdpOrigin(
              username: '-',
              sessionId: '0',
              sessionVersion: 0,
              netType: 'IN',
              addrType: 'IP4',
              address: '127.0.0.1'),
      sessionName: sessionName,
      connection: sessionConnection,
      timing: timing,
      attributes: sessionAttrs,
      media: media,
    );
  }
}

/// SDP `o=` line.
class SdpOrigin {
  String username;
  String sessionId;
  int sessionVersion;
  String netType;
  String addrType;
  String address;

  SdpOrigin({
    this.username = '-',
    required this.sessionId,
    this.sessionVersion = 2,
    this.netType = 'IN',
    this.addrType = 'IP4',
    this.address = '127.0.0.1',
  });

  String write() =>
      '$username $sessionId $sessionVersion $netType $addrType $address';

  factory SdpOrigin.parse(String value) {
    final p = value.split(RegExp(r'\s+'));
    return SdpOrigin(
      username: p.isNotEmpty ? p[0] : '-',
      sessionId: p.length > 1 ? p[1] : '0',
      sessionVersion: p.length > 2 ? int.tryParse(p[2]) ?? 2 : 2,
      netType: p.length > 3 ? p[3] : 'IN',
      addrType: p.length > 4 ? p[4] : 'IP4',
      address: p.length > 5 ? p[5] : '127.0.0.1',
    );
  }
}

/// SDP `c=` line.
class SdpConnection {
  String netType;
  String addrType;
  String address;

  SdpConnection({
    this.netType = 'IN',
    this.addrType = 'IP4',
    this.address = '0.0.0.0',
  });

  String write() => '$netType $addrType $address';

  factory SdpConnection.parse(String value) {
    final p = value.split(RegExp(r'\s+'));
    return SdpConnection(
      netType: p.isNotEmpty ? p[0] : 'IN',
      addrType: p.length > 1 ? p[1] : 'IP4',
      address: p.length > 2 ? p[2] : '0.0.0.0',
    );
  }
}

/// One SDP attribute (`a=name` or `a=name:value`).
class SdpAttribute {
  final String name;
  final String? value;
  const SdpAttribute(this.name, [this.value]);

  factory SdpAttribute.parse(String raw) {
    final i = raw.indexOf(':');
    if (i < 0) return SdpAttribute(raw);
    return SdpAttribute(raw.substring(0, i), raw.substring(i + 1));
  }

  String write() => value == null ? name : '$name:$value';

  @override
  String toString() => 'a=${write()}';
}

/// One `m=` section.
class SdpMedia {
  /// `audio` / `video` / `application`.
  String type;

  /// Port — `0` means the section is rejected, `9` is the WebRTC convention
  /// for an offer that lets ICE pick the real port.
  int port;

  /// Transport protocol, e.g. `UDP/TLS/RTP/SAVPF`.
  String protocol;

  /// Payload type numbers (RTP) or formats, in offer order.
  List<int> payloadTypes;

  /// Optional `c=...` line specific to this media section.
  SdpConnection? connection;

  /// Media-level attributes in the order they should be written.
  final List<SdpAttribute> attributes;

  SdpMedia({
    required this.type,
    this.port = 9,
    this.protocol = 'UDP/TLS/RTP/SAVPF',
    List<int>? payloadTypes,
    this.connection,
    List<SdpAttribute>? attributes,
  })  : payloadTypes = payloadTypes ?? [],
        attributes = attributes ?? [];

  /// Parse just the `m=` line value (everything after `m=`).
  factory SdpMedia.parseMLine(String value) {
    final p = value.split(RegExp(r'\s+'));
    return SdpMedia(
      type: p.isNotEmpty ? p[0] : 'audio',
      port: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0,
      protocol: p.length > 2 ? p[2] : 'UDP/TLS/RTP/SAVPF',
      payloadTypes: p.length > 3
          ? p.skip(3).map((s) => int.tryParse(s) ?? 0).toList()
          : [],
    );
  }

  /// Used by the parser to attach lines that follow this `m=`.
  void acceptLine(String key, String value) {
    switch (key) {
      case 'c':
        connection = SdpConnection.parse(value);
        break;
      case 'a':
        attributes.add(SdpAttribute.parse(value));
        break;
      // b=, k=, i= etc. are intentionally dropped to keep the model small;
      // extend here if you need them.
    }
  }

  /// `a=mid` value, the BUNDLE identifier for this section.
  String? get mid => attr('mid')?.value;
  set mid(String? v) => _setOrAdd('mid', v);

  /// `a=setup` (`actpass` / `active` / `passive`).
  String? get setup => attr('setup')?.value;
  set setup(String? v) => _setOrAdd('setup', v);

  /// First attribute matching [name], or null.
  SdpAttribute? attr(String name) =>
      attributes.where((a) => a.name == name).firstOrNull;

  /// All attributes matching [name].
  Iterable<SdpAttribute> attrs(String name) =>
      attributes.where((a) => a.name == name);

  /// Add or replace the first attribute named [name].
  void _setOrAdd(String name, String? value) {
    final i = attributes.indexWhere((a) => a.name == name);
    if (value == null) {
      if (i >= 0) attributes.removeAt(i);
      return;
    }
    final attr = SdpAttribute(name, value);
    if (i >= 0) {
      attributes[i] = attr;
    } else {
      attributes.add(attr);
    }
  }

  /// Convenience: find the rtpmap attribute for a payload type.
  /// Returns the parsed `<encoding>/<rate>[/<channels>]` triplet.
  RtpMap? rtpmapFor(int payloadType) {
    for (final a in attrs('rtpmap')) {
      final v = a.value;
      if (v == null) continue;
      final sp = v.indexOf(' ');
      if (sp < 0) continue;
      if (int.tryParse(v.substring(0, sp)) != payloadType) continue;
      return RtpMap.parse(v.substring(sp + 1));
    }
    return null;
  }

  void writeTo(StringBuffer b) {
    b.write('m=$type $port $protocol');
    for (final pt in payloadTypes) {
      b.write(' $pt');
    }
    b.write('\r\n');
    if (connection != null) b.write('c=${connection!.write()}\r\n');
    for (final a in attributes) {
      b.write('a=${a.write()}\r\n');
    }
  }
}

/// Parsed `<encoding>/<clockRate>[/<channels>]` from an `a=rtpmap` line.
class RtpMap {
  final String encoding;
  final int clockRate;
  final int? channels;

  const RtpMap(this.encoding, this.clockRate, [this.channels]);

  factory RtpMap.parse(String value) {
    final parts = value.split('/');
    return RtpMap(
      parts.isNotEmpty ? parts[0] : '',
      parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      parts.length > 2 ? int.tryParse(parts[2]) : null,
    );
  }

  String write() => channels == null
      ? '$encoding/$clockRate'
      : '$encoding/$clockRate/$channels';

  @override
  String toString() => write();
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
