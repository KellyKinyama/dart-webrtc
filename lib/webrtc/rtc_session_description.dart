// Mirrors the browser's `RTCSessionDescription` / `RTCSessionDescriptionInit`.
//
// https://www.w3.org/TR/webrtc/#rtcsessiondescription-class

/// Type of an SDP exchange step.
enum RTCSdpType { offer, pranswer, answer, rollback }

/// Immutable session-description value, carrying the SDP text and its role
/// in the offer/answer exchange.
class RTCSessionDescription {
  final RTCSdpType type;
  final String sdp;

  const RTCSessionDescription(this.type, this.sdp);

  /// Browser-compatible serialization (`toJSON()` returns `{type, sdp}`).
  Map<String, String> toJson() => {'type': type.name, 'sdp': sdp};

  factory RTCSessionDescription.fromJson(Map<String, dynamic> json) {
    final t = (json['type'] as String).toLowerCase();
    final type = RTCSdpType.values.firstWhere(
      (e) => e.name == t,
      orElse: () =>
          throw ArgumentError.value(json['type'], 'type', 'unknown sdp type'),
    );
    return RTCSessionDescription(type, (json['sdp'] as String?) ?? '');
  }

  @override
  String toString() => 'RTCSessionDescription(type=${type.name}, '
      'sdp=${sdp.length} chars)';
}
