# VPX Camera Demo (Flutter)

Cross-platform Flutter app that:

1. Opens the device camera via `package:camera`,
2. Converts each captured frame to **I420** ([camera_image_to_i420.dart](lib/camera_image_to_i420.dart)),
3. Encodes it with **libvpx** (VP8 or VP9) via the wrapper from `pure_dart_webrtc`,
4. Decodes the resulting bitstream back to I420,
5. Renders the decoded frame next to the live preview so you can visually confirm the round-trip.

A live stats bar shows encoded/decoded frame counts, keyframe count, total bytes, and average bytes per frame. Tap the codec chip in the app bar to flip between **VP8** and **VP9** at runtime.

## Project layout

```
example/flutter_camera/
├── lib/
│   ├── main.dart                     # UI + camera + codec switch
│   ├── camera_image_to_i420.dart     # CameraImage -> I420Frame; I420 -> BGRA for display
│   └── vpx_pipeline.dart             # VpxEncoder -> VpxDecoder loopback + stats
├── pubspec.yaml
└── README.md
```

## Setup

```bash
cd example/flutter_camera
flutter pub get
```

The app depends on the host package via `path: ../../`, so any local edits to `lib/src/codecs/vpx/**` are picked up automatically.

### Native libvpx — required on every platform

The wrapper is pure Dart FFI and **does not bundle libvpx itself**. You must make a libvpx shared library reachable at app launch.

| Platform | What to install / bundle |
| --- | --- |
| **Windows** | `pacman -S mingw-w64-x86_64-libvpx` (MSYS2). Either run with `C:\msys64\mingw64\bin` on `PATH`, or copy `libvpx-1.dll` next to the built `.exe`, or set the env var `VPX_LIB_PATH=C:\full\path\to\libvpx-1.dll`. |
| **macOS** | `brew install libvpx`. Either run with `DYLD_LIBRARY_PATH=/opt/homebrew/lib`, or copy `libvpx.dylib` into the app bundle's `Frameworks/`, or set `VPX_LIB_PATH=/opt/homebrew/lib/libvpx.dylib`. |
| **Linux** | `apt install libvpx7` (or `libvpx6`). Already on the loader path. |
| **Android** | Build libvpx for `arm64-v8a` / `armeabi-v7a` / `x86_64` and drop the `.so` files into `android/app/src/main/jniLibs/<abi>/libvpx.so`. They will be auto-extracted at install time. |
| **iOS** | Build a libvpx `.framework` (or `.xcframework`) and add it to the Runner target as **Embed & Sign**. The loader will pick it up via `DynamicLibrary.process()` on iOS, or by bundle-relative path. |

> The loader's search order is documented in `lib/src/codecs/vpx/vpx_loader.dart`. The simplest portable override is the `VPX_LIB_PATH` env var.

### Camera permission

The `camera` plugin needs platform-specific permission entries:

* **Android** — `<uses-permission android:name="android.permission.CAMERA" />` in `android/app/src/main/AndroidManifest.xml`, and `minSdkVersion 21+`.
* **iOS** — `NSCameraUsageDescription` in `ios/Runner/Info.plist`.
* **macOS** — `NSCameraUsageDescription` in `macos/Runner/Info.plist`, plus a `com.apple.security.device.camera` entitlement.
* **Windows / Linux** — no special permission needed beyond what the OS prompts for.

## Run

```bash
flutter run                  # current default device
flutter run -d windows
flutter run -d macos
flutter run -d linux
flutter run -d <android-id>
flutter run -d <ios-id>
```

You should see two panels (live preview + decoded round-trip) plus a stats bar updating ~30 fps. Press the codec chip to switch between VP8 and VP9 — the pipeline is rebuilt and the next captured frame becomes a fresh keyframe under the new codec.

## How it works

```
CameraImage stream
        │
        ▼
CameraImageConverter.convert(...)        // YUV420 / BGRA8888 -> I420Frame
        │
        ▼
VpxLoopbackPipeline.process(frame)
        │
        ├─ VpxEncoder.encode(frame, pts: i)   --> VpxPacket (VP8 / VP9)
        │
        └─ VpxDecoder.decode(pkt.data)        --> I420Frame
                                                │
                                                ▼
                                  i420ToBgra8888 + ui.ImageDescriptor.raw
                                                │
                                                ▼
                                            RawImage widget
```

The pipeline drops new frames while the previous one is still being processed (`_busy` flag) — encoding runs on the platform thread, so on lower-end devices you'll see effective fps drop rather than memory growth.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `VpxLoaderException: Could not load libvpx. Tried: …` | libvpx not installed / not on PATH; set `VPX_LIB_PATH`. |
| Black "Decoded" panel for >1s | First keyframe hasn't arrived yet (libvpx may buffer the very first frame) — wait one beat. |
| `Unsupported camera image format` | Some Android OEM cameras use NV21 only — pass `imageFormatGroup: ImageFormatGroup.nv21` in `main.dart` and add an `_fromNv21` branch in `CameraImageConverter`. |
| Stuttery preview | Reduce `bitrateKbps` or lower `ResolutionPreset` to `low`; encoding cost is O(W·H). |
