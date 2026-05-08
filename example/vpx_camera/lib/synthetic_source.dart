// Synthetic animated frame source. Produces a 320x240 I420 frame at ~30fps
// containing scrolling colour bars + a moving white square. Lets the demo
// run on machines with no camera (CI, headless desktops, devices where
// `package:camera` has no backend).

import 'dart:async';
import 'dart:math' as math;

import 'package:pure_dart_webrtc/vpx.dart';

class SyntheticFrameSource {
  final int width;
  final int height;
  final int fps;
  Timer? _timer;
  int _t = 0;

  SyntheticFrameSource({this.width = 320, this.height = 240, this.fps = 30});

  /// Start emitting frames; [onFrame] is called once per tick.
  void start(void Function(I420Frame) onFrame) {
    _timer?.cancel();
    final period = Duration(microseconds: (1e6 / fps).round());
    _timer = Timer.periodic(period, (_) {
      onFrame(_buildFrame(_t));
      _t++;
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  I420Frame _buildFrame(int t) {
    final f = I420Frame.allocate(width, height);
    final cw = (width + 1) >> 1;
    final ch = (height + 1) >> 1;

    // Y: vertical colour bars + moving wave.
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final bar = ((x + t) ~/ (width ~/ 8)) & 7;
        final base = 16 + bar * 28;
        final wave = (16 * math.sin((x + t) * 0.05) * math.cos(y * 0.05))
            .round();
        final v = base + wave;
        f.y[y * width + x] = v.clamp(0, 255);
      }
    }

    // U/V: smooth gradients that drift over time.
    for (var y = 0; y < ch; y++) {
      for (var x = 0; x < cw; x++) {
        f.u[y * cw + x] = (128 + (x * 2 + t) % 80 - 40).clamp(0, 255);
        f.v[y * cw + x] = (128 + (y * 2 + t * 2) % 80 - 40).clamp(0, 255);
      }
    }

    // White moving square so motion is obvious.
    final sqSize = 32;
    final sx = (t * 3) % (width - sqSize);
    final sy = (height - sqSize) ~/ 2 + (16 * math.sin(t * 0.1)).round();
    for (var y = 0; y < sqSize; y++) {
      for (var x = 0; x < sqSize; x++) {
        f.y[(sy + y) * width + (sx + x)] = 235;
      }
    }
    return f;
  }
}
