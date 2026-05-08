// VPX camera demo:
//   - opens the first available camera,
//   - streams frames into a VP8/VP9 encoder,
//   - immediately decodes them, and
//   - shows the decoded frames side by side with the live preview.
//
// Tap the codec chip to switch between VP8 and VP9 at runtime (the pipeline
// is rebuilt on the fly).

import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pure_dart_webrtc/vpx.dart';

import 'camera_image_to_i420.dart';
import 'synthetic_source.dart';
import 'take_picture_source.dart';
import 'vpx_pipeline.dart';

late final List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _cameras = await availableCameras();
  } catch (e) {
    debugPrint('availableCameras() failed: $e');
    _cameras = const [];
  }
  runApp(const VpxCameraApp());
}

class VpxCameraApp extends StatelessWidget {
  const VpxCameraApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'VPX Camera Demo',
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
    ),
    home: const _DemoPage(),
  );
}

class _DemoPage extends StatefulWidget {
  const _DemoPage();
  @override
  State<_DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<_DemoPage> {
  CameraController? _controller;
  SyntheticFrameSource? _synthetic;
  TakePictureSource? _takePictureSource;
  ui.Image? _sourceImage; // shown in the left panel when running synthetic
  VpxLoopbackPipeline? _pipeline;
  VpxCodec _codec = VpxCodec.vp8;
  bool _busy = false;
  ui.Image? _decodedImage;
  PipelineStats _stats = const PipelineStats(
    encodedFrames: 0,
    decodedFrames: 0,
    encodedBytes: 0,
    keyframes: 0,
  );
  String? _error;
  String _sourceLabel = 'Camera';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (_cameras.isEmpty) {
      debugPrint('No camera available — falling back to synthetic source.');
      _startSynthetic();
      return;
    }
    final controller = CameraController(
      _cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );
    try {
      await controller.initialize();
    } catch (e) {
      debugPrint('Camera init failed ($e) — falling back to synthetic source.');
      _startSynthetic();
      return;
    }
    _controller = controller;

    try {
      // Build pipeline lazily on the first frame so we know the real WxH.
      await controller.startImageStream(_onFrame);
    } catch (e) {
      debugPrint(
        'Image stream not supported ($e) — falling back to takePicture polling.',
      );
      // Try the polled snapshot path before giving up to synthetic.
      try {
        final src = TakePictureSource(controller, fps: 5);
        src.start(_onPolledFrame);
        _takePictureSource = src;
        if (mounted) {
          setState(() => _sourceLabel = 'Camera (snapshot @ 5fps)');
        }
        return;
      } catch (e2) {
        debugPrint(
          'takePicture polling also failed ($e2) — falling back to synthetic source.',
        );
        _controller = null;
        _startSynthetic();
        return;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _onPolledFrame(I420Frame i420) async {
    if (_busy) return;
    _busy = true;
    try {
      _pipeline ??= VpxLoopbackPipeline(
        codec: _codec,
        width: i420.width,
        height: i420.height,
        fps: 5,
        bitrateKbps: 400,
      );
      final src = await _decodeToUiImage(i420);
      final decoded = _pipeline!.process(i420);
      ui.Image? out;
      if (decoded != null) {
        out = await _decodeToUiImage(decoded);
      }
      if (!mounted) {
        src.dispose();
        out?.dispose();
        return;
      }
      _sourceImage?.dispose();
      if (out != null) _decodedImage?.dispose();
      setState(() {
        _sourceImage = src;
        if (out != null) _decodedImage = out;
        _stats = _pipeline!.stats;
      });
    } catch (e, st) {
      debugPrint('polled frame error: $e\n$st');
    } finally {
      _busy = false;
    }
  }

  void _startSynthetic() {
    _synthetic = SyntheticFrameSource(width: 320, height: 240, fps: 30);
    _synthetic!.start(_onSyntheticFrame);
    if (mounted) setState(() => _sourceLabel = 'Synthetic test pattern');
  }

  Future<void> _onSyntheticFrame(I420Frame i420) async {
    if (_busy) return;
    _busy = true;
    try {
      _pipeline ??= VpxLoopbackPipeline(
        codec: _codec,
        width: i420.width,
        height: i420.height,
        fps: 30,
        bitrateKbps: 400,
      );
      final src = await _decodeToUiImage(i420);
      final decoded = _pipeline!.process(i420);
      ui.Image? out;
      if (decoded != null) {
        out = await _decodeToUiImage(decoded);
      }
      if (!mounted) {
        src.dispose();
        out?.dispose();
        return;
      }
      _sourceImage?.dispose();
      if (out != null) _decodedImage?.dispose();
      setState(() {
        _sourceImage = src;
        if (out != null) _decodedImage = out;
        _stats = _pipeline!.stats;
      });
    } catch (e, st) {
      debugPrint('synthetic frame error: $e\n$st');
    } finally {
      _busy = false;
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy) return; // Drop frames while the previous one is in-flight.
    _busy = true;
    try {
      final i420 = CameraImageConverter.convert(image);
      _pipeline ??= VpxLoopbackPipeline(
        codec: _codec,
        width: i420.width,
        height: i420.height,
        fps: 30,
        bitrateKbps: 800,
      );
      final decoded = _pipeline!.process(i420);
      if (decoded != null) {
        final img = await _decodeToUiImage(decoded);
        if (!mounted) return;
        _decodedImage?.dispose();
        setState(() {
          _decodedImage = img;
          _stats = _pipeline!.stats;
        });
      }
    } catch (e, st) {
      debugPrint('frame error: $e\n$st');
    } finally {
      _busy = false;
    }
  }

  Future<ui.Image> _decodeToUiImage(I420Frame f) async {
    final bgra = i420ToBgra8888(f);
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      Uint8List.fromList(bgra),
    );
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: f.width,
      height: f.height,
      pixelFormat: ui.PixelFormat.bgra8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<void> _switchCodec() async {
    final next = _codec == VpxCodec.vp8 ? VpxCodec.vp9 : VpxCodec.vp8;
    final old = _pipeline;
    setState(() {
      _codec = next;
      _pipeline = null;
    });
    old?.dispose();
  }

  @override
  void dispose() {
    _synthetic?.stop();
    _takePictureSource?.stop();
    _controller?.stopImageStream();
    _controller?.dispose();
    _pipeline?.dispose();
    _decodedImage?.dispose();
    _sourceImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('VPX Camera Demo'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ActionChip(
              avatar: const Icon(Icons.swap_horiz, size: 18),
              label: Text(_codec == VpxCodec.vp8 ? 'VP8' : 'VP9'),
              onPressed: _switchCodec,
            ),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : _buildBody(controller),
    );
  }

  Widget _buildBody(CameraController? controller) {
    final usingCamera = controller != null && controller.value.isInitialized;
    final usingSynthetic = _synthetic != null;
    final usingPolled = _takePictureSource != null;
    if (!usingCamera && !usingSynthetic && !usingPolled) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (ctx, c) {
        final wide = c.maxWidth > c.maxHeight;
        // For the polled / synthetic paths we render the most-recent decoded
        // source frame instead of `CameraPreview` (which would try to use
        // an active image stream that isn't running).
        final useLiveCameraWidget = usingCamera && !usingPolled;
        final sourceWidget = useLiveCameraWidget
            ? CameraPreview(controller)
            : (_sourceImage == null
                  ? const Center(child: Text('warming up…'))
                  : RawImage(image: _sourceImage, fit: BoxFit.contain));
        final children = [
          Expanded(child: _LabeledBox(_sourceLabel, sourceWidget)),
          Expanded(
            child: _LabeledBox(
              'Decoded (${_codec == VpxCodec.vp8 ? "VP8" : "VP9"})',
              _decodedImage == null
                  ? const Center(child: Text('warming up…'))
                  : RawImage(image: _decodedImage, fit: BoxFit.contain),
            ),
          ),
        ];
        return Column(
          children: [
            Expanded(
              child: wide
                  ? Row(children: children)
                  : Column(children: children),
            ),
            _StatsBar(stats: _stats),
          ],
        );
      },
    );
  }
}

class _LabeledBox extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledBox(this.label, this.child);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(color: Colors.black, child: child),
          ),
        ),
      ],
    ),
  );
}

class _StatsBar extends StatelessWidget {
  final PipelineStats stats;
  const _StatsBar({required this.stats});
  @override
  Widget build(BuildContext context) {
    final kb = (stats.encodedBytes / 1024).toStringAsFixed(1);
    final perFrame = stats.avgBytesPerFrame.toStringAsFixed(0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.black54,
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          Text('encoded: ${stats.encodedFrames}'),
          Text('decoded: ${stats.decodedFrames}'),
          Text('keyframes: ${stats.keyframes}'),
          Text('total: $kb KB'),
          Text('avg: $perFrame B/frame'),
        ],
      ),
    );
  }
}
