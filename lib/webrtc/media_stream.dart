// Tiny stand-ins for `MediaStreamTrack` / `MediaStream`. They carry just
// enough metadata for the offer/answer exchange to advertise the right
// `m=` sections; actual media plumbing lives in the RTP/SRTP layers.

import 'package:uuid/v4.dart';

enum MediaKind { audio, video }

/// Minimal `MediaStreamTrack` analogue.
class MediaStreamTrack {
  final String id;
  final MediaKind kind;
  String label;
  bool enabled;
  bool muted;

  MediaStreamTrack({
    required this.kind,
    String? id,
    String? label,
    this.enabled = true,
    this.muted = false,
  })  : id = id ?? const UuidV4().generate(),
        label = label ?? '${kind.name} track';

  /// Browser parity: `track.kind` returns `'audio'` / `'video'`.
  String get kindName => kind.name;

  void stop() {
    enabled = false;
    muted = true;
  }

  @override
  String toString() => 'MediaStreamTrack(id=$id, kind=${kind.name})';
}

/// Minimal `MediaStream` analogue.
class MediaStream {
  final String id;
  final List<MediaStreamTrack> _tracks = [];

  MediaStream({String? id, List<MediaStreamTrack> tracks = const []})
      : id = id ?? const UuidV4().generate() {
    _tracks.addAll(tracks);
  }

  List<MediaStreamTrack> getTracks() => List.unmodifiable(_tracks);
  List<MediaStreamTrack> getAudioTracks() =>
      _tracks.where((t) => t.kind == MediaKind.audio).toList();
  List<MediaStreamTrack> getVideoTracks() =>
      _tracks.where((t) => t.kind == MediaKind.video).toList();

  void addTrack(MediaStreamTrack track) {
    if (!_tracks.contains(track)) _tracks.add(track);
  }

  void removeTrack(MediaStreamTrack track) => _tracks.remove(track);
}
