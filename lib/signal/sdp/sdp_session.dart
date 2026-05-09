// SDP document built on top of `package:sdp_transform`.
//
// `sdp_transform` parses an SDP into a plain `Map<String, dynamic>` that
// follows the well-known shape used by the npm `sdp-transform` library, and
// serializes the same map back to text. We delegate all parsing and writing
// to it; this file only exposes a couple of convenience helpers so callers
// don't have to import `sdp_transform` directly.

import 'package:sdp_transform/sdp_transform.dart' as sdp_transform;

/// Parse an SDP string into a typed-but-dynamic map.
Map<String, dynamic> parseSdp(String text) => sdp_transform.parse(text);

/// Serialize a session map to an SDP string.
///
/// If `session['extmapAllowMixed'] == true`, an `a=extmap-allow-mixed` line
/// is injected at the session level. (sdp_transform 0.3.2 has no formatter
/// for this attribute, so we emit it ourselves.)
String writeSdp(Map<String, dynamic> session) {
  final wantMixed = session['extmapAllowMixed'] == true;
  // Strip our marker so sdp_transform doesn't try to format it.
  final cleaned = wantMixed
      ? (Map<String, dynamic>.from(session)..remove('extmapAllowMixed'))
      : session;
  final text = sdp_transform.write(cleaned, null);
  if (!wantMixed) return text;
  // Insert at session level: just before the first `m=` line.
  final idx = text.indexOf('\r\nm=');
  if (idx < 0) return text;
  return '${text.substring(0, idx)}\r\na=extmap-allow-mixed${text.substring(idx)}';
}

/// Helpers for reading common WebRTC fields out of a parsed session map.
extension SdpSessionMap on Map<String, dynamic> {
  /// All media sections, never null.
  List<Map<String, dynamic>> get mediaList =>
      (this['media'] as List? ?? const []).cast<Map<String, dynamic>>();

  /// Mids in the BUNDLE group, in order. Empty if no group is present.
  List<String> get bundleMids {
    final groups = (this['groups'] as List? ?? const []).cast<Map>();
    for (final g in groups) {
      if (g['type'] == 'BUNDLE') {
        final mids = (g['mids'] as String? ?? '').trim();
        if (mids.isEmpty) return const [];
        return mids.split(RegExp(r'\s+'));
      }
    }
    return const [];
  }
}

/// Helpers for reading per-media fields.
extension SdpMediaMap on Map<String, dynamic> {
  /// `rtp` array (rtpmap entries), never null.
  List<Map<String, dynamic>> get rtpList =>
      (this['rtp'] as List? ?? const []).cast<Map<String, dynamic>>();

  /// Find the rtpmap entry for [payloadType], or null.
  Map<String, dynamic>? rtpmapFor(int payloadType) {
    for (final r in rtpList) {
      if (r['payload'] == payloadType) return r;
    }
    return null;
  }

  /// Payload-type list parsed out of the `m=` line's `payloads` string.
  List<int> get payloadTypeList {
    final raw = this['payloads'];
    if (raw == null) return const [];
    if (raw is int) return [raw];
    final p = raw.toString().trim();
    if (p.isEmpty) return const [];
    return p.split(RegExp(r'\s+')).map(int.tryParse).whereType<int>().toList();
  }

  /// `a=ssrc-group:` entries, never null. Each entry is
  /// `{semantics: 'FID' | 'FEC' | ..., ssrcs: [int, int, ...]}`.
  List<Map<String, Object>> get ssrcGroupList {
    final raw = (this['ssrcGroups'] as List?) ?? const [];
    final out = <Map<String, Object>>[];
    for (final g in raw.cast<Map>()) {
      final semantics = g['semantics']?.toString() ?? '';
      final ssrcs = (g['ssrcs']?.toString() ?? '')
          .trim()
          .split(RegExp(r'\s+'))
          .map(int.tryParse)
          .whereType<int>()
          .toList();
      if (semantics.isEmpty || ssrcs.isEmpty) continue;
      out.add({'semantics': semantics, 'ssrcs': ssrcs});
    }
    return out;
  }

  /// Map from RTX SSRC to its primary SSRC, parsed from
  /// `a=ssrc-group:FID <primary> <rtx>` entries. Empty if none present.
  Map<int, int> get rtxToPrimarySsrc {
    final out = <int, int>{};
    for (final g in ssrcGroupList) {
      if (g['semantics'] != 'FID') continue;
      final ssrcs = g['ssrcs'] as List<int>;
      if (ssrcs.length < 2) continue;
      // FID convention: first SSRC is primary, second is RTX.
      out[ssrcs[1]] = ssrcs[0];
    }
    return out;
  }

  /// All SSRCs that appear on at least one `a=ssrc:<id> ...` line.
  Set<int> get ssrcSet {
    final raw = (this['ssrcs'] as List?) ?? const [];
    final out = <int>{};
    for (final s in raw.cast<Map>()) {
      final id = s['id'];
      if (id is int) out.add(id);
      if (id is String) {
        final v = int.tryParse(id);
        if (v != null) out.add(v);
      }
    }
    return out;
  }
}
