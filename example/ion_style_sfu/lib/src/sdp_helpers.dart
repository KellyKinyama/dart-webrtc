// Phase 2/3 — SDP helpers shared by Router (parse publisher offer) and
// Subscriber (augment subscriber offer with rewritten SSRC lines).

import 'package:pure_dart_webrtc/signal/sdp_v2.dart';

import 'producer_layer.dart';
import 'producer_stream.dart';
import 'ssrc_allocator.dart';

/// Parse [offerSdp] from a publisher and extract the producer streams
/// declared in each m= section. One [ProducerStream] per logical track:
/// non-simulcast tracks have one layer, SIM-grouped simulcast tracks
/// have N layers ordered low→high.
List<ProducerStream> parsePublisherOffer({
  required String peerId,
  required String offerSdp,
}) {
  final out = <ProducerStream>[];
  final session = parseSdp(offerSdp);
  for (final m in session.mediaList) {
    final kind = (m['type'] as String?) ?? '';
    if (kind != 'video' && kind != 'audio') continue;
    final mid = m['mid']?.toString() ?? '';
    final rtxToPrimary = m.rtxToPrimarySsrc;
    final primaryToRtx = <int, int>{
      for (final e in rtxToPrimary.entries) e.value: e.key,
    };
    final cnames = <int, String>{};
    final msids = <int, String>{};
    for (final s in (m['ssrcs'] as List?)?.cast<Map>() ?? const []) {
      final id = s['id'];
      final attr = s['attribute'];
      final val = s['value']?.toString();
      int? n;
      if (id is int) {
        n = id;
      } else if (id is String) {
        n = int.tryParse(id);
      }
      if (n == null || val == null) continue;
      if (attr == 'cname') cnames[n] = val;
      if (attr == 'msid') msids[n] = val;
    }
    final rtxSsrcs = rtxToPrimary.keys.toSet();

    // SIM groups: a=ssrc-group:SIM <ssrc1> <ssrc2> <ssrc3>
    // Each ssrc is a primary for one simulcast layer (lowest first by
    // convention; we preserve declared order).
    final simGroups = <List<int>>[];
    for (final g in (m['ssrcGroups'] as List?)?.cast<Map>() ?? const []) {
      if (g['semantics'] != 'SIM') continue;
      final raw = g['ssrcs']?.toString() ?? '';
      final parsed = raw
          .split(RegExp(r'\s+'))
          .map(int.tryParse)
          .whereType<int>()
          .toList(growable: false);
      if (parsed.length >= 2) simGroups.add(parsed);
    }
    final simByPrimary = <int, List<int>>{};
    for (final g in simGroups) {
      simByPrimary[g.first] = g;
    }
    final simSecondaryMembers = <int>{
      for (final g in simGroups) ...g.skip(1),
    };

    String resolveStreamId(int ssrc) {
      final raw = msids[ssrc];
      if (raw == null) return peerId;
      final parts = raw.split(RegExp(r'\s+'));
      return parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : peerId;
    }

    String resolveTrackId(int ssrc) {
      final raw = msids[ssrc];
      if (raw != null) {
        final parts = raw.split(RegExp(r'\s+'));
        if (parts.length > 1 && parts[1].isNotEmpty) return parts[1];
      }
      return '$peerId-$kind-$mid';
    }

    // Walk primary SSRCs in declaration order (m.ssrcSet preserves it),
    // skipping RTX SSRCs and SIM-secondary members (those are emitted
    // as part of the SIM-leader's stream below).
    for (final ssrc in m.ssrcSet) {
      if (rtxSsrcs.contains(ssrc)) continue;
      if (simSecondaryMembers.contains(ssrc)) continue;
      final cname = cnames[ssrc] ?? peerId;
      final streamId = resolveStreamId(ssrc);
      final trackId = resolveTrackId(ssrc);

      final simMembers = simByPrimary[ssrc];
      if (simMembers != null) {
        // Simulcast: build one layer per member, ordered as declared.
        // Convention is low→high quality; we don't reorder.
        final layers = <ProducerLayer>[];
        for (var i = 0; i < simMembers.length; i++) {
          final s = simMembers[i];
          // 3 layers default to q/h/f names, otherwise just the index.
          String rid;
          if (simMembers.length == 3) {
            rid = const ['q', 'h', 'f'][i];
          } else if (simMembers.length == 2) {
            rid = const ['h', 'f'][i];
          } else {
            rid = 'l$i';
          }
          layers.add(ProducerLayer(
            rid: rid,
            primarySsrc: s,
            rtxSsrc: primaryToRtx[s],
          ));
        }
        out.add(ProducerStream.simulcast(
          kind: kind,
          mid: mid,
          layers: layers,
          cname: cname,
          msidStream: streamId,
          msidTrack: trackId,
        ));
      } else {
        out.add(ProducerStream(
          kind: kind,
          mid: mid,
          primarySsrc: ssrc,
          rtxSsrc: primaryToRtx[ssrc],
          cname: cname,
          msidStream: streamId,
          msidTrack: trackId,
        ));
      }
    }
  }
  return out;
}

/// Augment [offerSdp] (the subscriber-PC's outbound offer) with
/// `a=ssrc-group:FID` and `a=ssrc:` lines describing the per-subscriber
/// rewritten SSRCs for [streams]. Streams are paired with the
/// SDP's m= sections in document order, kind-matched, skipping rejected
/// (port=0) sections. Even simulcast streams emit a single outbound
/// SSRC pair — the subscriber sees one continuous track regardless of
/// the inbound layer being forwarded.
///
/// Mirrors `BasicSfu.augmentAnswerSdp`, adapted to operate on offers.
String augmentSubscriberOffer({
  required String subscriberId,
  required SsrcAllocator allocator,
  required List<ProducerStream> streams,
  required String offerSdp,
}) {
  if (streams.isEmpty) return offerSdp;
  final session = parseSdp(offerSdp);
  final media = session.mediaList;
  if (media.isEmpty) return offerSdp;

  final pendingByKind = <String, List<ProducerStream>>{
    'video': [],
    'audio': [],
  };
  for (final s in streams) {
    pendingByKind[s.kind]?.add(s);
  }

  var changed = false;
  for (final m in media) {
    final kind = (m['type'] as String?) ?? '';
    if (kind != 'video' && kind != 'audio') continue;
    if (m['port'] == 0) continue;
    final dir = (m['direction'] as String?) ?? 'sendrecv';
    if (dir != 'sendrecv' && dir != 'sendonly') continue;
    final pending = pendingByKind[kind]!;
    if (pending.isEmpty) continue;
    final stream = pending.removeAt(0);

    final ssrcs = (m['ssrcs'] as List?) ?? <Map<String, dynamic>>[];
    final groups = (m['ssrcGroups'] as List?) ?? <Map<String, dynamic>>[];

    final rwPrimary = allocator.rewrite(subscriberId, stream.primarySsrc);
    int? rwRtx;
    if (stream.rtxSsrc != null) {
      rwRtx = allocator.rewriteRtx(
        subscriberId,
        stream.primarySsrc,
        stream.rtxSsrc!,
      );
    }
    ssrcs.add({
      'id': rwPrimary,
      'attribute': 'cname',
      'value': stream.cname,
    });
    ssrcs.add({
      'id': rwPrimary,
      'attribute': 'msid',
      'value': '${stream.msidStream} ${stream.msidTrack}',
    });
    if (rwRtx != null) {
      ssrcs.add({
        'id': rwRtx,
        'attribute': 'cname',
        'value': stream.cname,
      });
      ssrcs.add({
        'id': rwRtx,
        'attribute': 'msid',
        'value': '${stream.msidStream} ${stream.msidTrack}',
      });
      groups.add({
        'semantics': 'FID',
        'ssrcs': '$rwPrimary $rwRtx',
      });
    }
    changed = true;
    if (ssrcs.isNotEmpty) m['ssrcs'] = ssrcs;
    if (groups.isNotEmpty) m['ssrcGroups'] = groups;
    m['msid'] = '${stream.msidStream} ${stream.msidTrack}';
  }

  if (!changed) return offerSdp;
  return writeSdp(session);
}
