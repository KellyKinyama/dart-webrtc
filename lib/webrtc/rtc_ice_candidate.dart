// Mirrors the browser's `RTCIceCandidate` / `RTCIceCandidateInit` shape.

/// A single ICE candidate (`a=candidate:...`) plus its m-section binding.
class RTCIceCandidate {
  /// The full candidate-attribute value, *including* the leading `candidate:`
  /// prefix (matches the browser).
  final String candidate;

  /// `mid` of the m-section this candidate belongs to. May be null when only
  /// [sdpMLineIndex] is provided.
  final String? sdpMid;

  /// Zero-based index of the m-section.
  final int? sdpMLineIndex;

  /// Optional ICE ufrag carried alongside the candidate.
  final String? usernameFragment;

  const RTCIceCandidate({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
    this.usernameFragment,
  });

  Map<String, dynamic> toJson() => {
        'candidate': candidate,
        if (sdpMid != null) 'sdpMid': sdpMid,
        if (sdpMLineIndex != null) 'sdpMLineIndex': sdpMLineIndex,
        if (usernameFragment != null) 'usernameFragment': usernameFragment,
      };

  factory RTCIceCandidate.fromJson(Map<String, dynamic> json) =>
      RTCIceCandidate(
        candidate: (json['candidate'] as String?) ?? '',
        sdpMid: json['sdpMid'] as String?,
        sdpMLineIndex: json['sdpMLineIndex'] as int?,
        usernameFragment: json['usernameFragment'] as String?,
      );

  @override
  String toString() => 'RTCIceCandidate(mid=$sdpMid, $candidate)';
}
