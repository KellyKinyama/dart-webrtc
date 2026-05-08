// Polls `CameraController.takePicture()` at a fixed rate and decodes each JPEG
// (or RGBA PNG, depending on the platform) into an [I420Frame]. Used as a
// fallback on platforms whose camera backend doesn't support
// `startImageStream` — currently Windows.
//
// Throughput is limited (typically 2-10 fps depending on the OS shutter
// behaviour), but it lets the demo run against a real webcam everywhere
// `takePicture` works.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:pure_dart_webrtc/vpx.dart';

class TakePictureSource {
  final CameraController controller;
  final int fps;
  bool _running = false;
  bool _busy = false;

  TakePictureSource(this.controller, {this.fps = 5});

  /// Begin polling. [onFrame] is invoked with each successfully decoded frame.
  void start(void Function(I420Frame) onFrame) {
    _running = true;
    final period = Duration(milliseconds: (1000 / fps).round());
    Timer.periodic(period, (t) async {
      if (!_running) {
        t.cancel();
        return;
      }
      if (_busy) return;
      _busy = true;
      try {
        final frame = await _grab();
        if (frame != null && _running) onFrame(frame);
      } catch (_) {
        // swallow transient camera errors; next tick retries
      } finally {
        _busy = false;
      }
    });
  }

  Future<I420Frame?> _grab() async {
    final XFile shot;
    try {
      shot = await controller.takePicture();
    } catch (_) {
      return null;
    }
    final bytes = await shot.readAsBytes();
    // Best-effort: clean up the temp file the platform created.
    try {
      await File(shot.path).delete();
    } catch (_) {}
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // Force even dimensions for libvpx 4:2:0.
    final w = decoded.width & ~1;
    final h = decoded.height & ~1;
    final cropped = (w == decoded.width && h == decoded.height)
        ? decoded
        : img.copyCrop(decoded, x: 0, y: 0, width: w, height: h);

    // Repack into a tight RGB24 buffer for `I420Frame.fromRgb24`.
    final rgb = Uint8List(w * h * 3);
    var o = 0;
    for (final p in cropped) {
      rgb[o++] = p.r.toInt();
      rgb[o++] = p.g.toInt();
      rgb[o++] = p.b.toInt();
    }
    return I420Frame.fromRgb24(rgb, w, h);
  }

  void stop() {
    _running = false;
  }
}
