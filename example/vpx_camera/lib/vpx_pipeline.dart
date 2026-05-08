// Wires a [VpxEncoder] -> [VpxDecoder] loopback. The UI feeds raw camera
// frames in (as [I420Frame]) and gets back the just-decoded [I420Frame] —
// proving the encoder + decoder both work on the captured stream.

import 'package:pure_dart_webrtc/vpx.dart';

class VpxLoopbackPipeline {
  final VpxCodec codec;
  final int width;
  final int height;
  final int fps;

  late final VpxEncoder _encoder;
  late final VpxDecoder _decoder;

  int _pts = 0;
  int _encodedBytes = 0;
  int _encodedFrames = 0;
  int _decodedFrames = 0;
  int _keyframes = 0;

  VpxLoopbackPipeline({
    required this.codec,
    required this.width,
    required this.height,
    this.fps = 30,
    int bitrateKbps = 800,
    int keyframeInterval = 60,
  }) {
    _encoder = VpxEncoder(
      codec: codec,
      width: width,
      height: height,
      fps: fps,
      bitrateKbps: bitrateKbps,
      keyframeInterval: keyframeInterval,
    );
    _decoder = VpxDecoder(codec: codec);
  }

  /// Push one captured [I420Frame] through encoder + decoder. Returns the
  /// most recent decoded frame (or null if the encoder buffered without
  /// emitting a packet).
  I420Frame? process(I420Frame frame) {
    I420Frame? lastDecoded;
    final packets = _encoder.encode(frame, pts: _pts++);
    for (final pkt in packets) {
      _encodedBytes += pkt.data.length;
      _encodedFrames++;
      if (pkt.isKeyframe) _keyframes++;
      for (final out in _decoder.decode(pkt.data)) {
        lastDecoded = out;
        _decodedFrames++;
      }
    }
    return lastDecoded;
  }

  PipelineStats get stats => PipelineStats(
        encodedFrames: _encodedFrames,
        decodedFrames: _decodedFrames,
        encodedBytes: _encodedBytes,
        keyframes: _keyframes,
      );

  void dispose() {
    _encoder.dispose();
    _decoder.dispose();
  }
}

class PipelineStats {
  final int encodedFrames;
  final int decodedFrames;
  final int encodedBytes;
  final int keyframes;

  const PipelineStats({
    required this.encodedFrames,
    required this.decodedFrames,
    required this.encodedBytes,
    required this.keyframes,
  });

  double get avgBytesPerFrame =>
      encodedFrames == 0 ? 0 : encodedBytes / encodedFrames;
}
