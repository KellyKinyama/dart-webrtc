// Codec selector for [VpxEncoder] and [VpxDecoder].

enum VpxCodec {
  vp8,
  vp9;

  /// IVF FourCC for this codec ('VP80' / 'VP90').
  String get fourcc => switch (this) {
        VpxCodec.vp8 => 'VP80',
        VpxCodec.vp9 => 'VP90',
      };

  static VpxCodec fromFourcc(String fourcc) => switch (fourcc) {
        'VP80' => VpxCodec.vp8,
        'VP90' => VpxCodec.vp9,
        _ => throw ArgumentError('Unsupported codec FourCC: $fourcc'),
      };
}
