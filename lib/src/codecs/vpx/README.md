# VPX (VP8 / VP9) codec

Pure-Dart FFI bindings to **libvpx 1.14**, plus three CLI tools:

| File | Purpose |
| --- | --- |
| [bin/vpx_encode.dart](../../../../bin/vpx_encode.dart) | Encode raw RGB24 → VP8 IVF |
| [bin/vpx_decode.dart](../../../../bin/vpx_decode.dart) | Decode VP8/VP9 IVF → raw I420 YUV |
| [bin/vpx_test_vectors.dart](../../../../bin/vpx_test_vectors.dart) | Run libvpx VP8 conformance suite (per-frame MD5 compare) |

## Layout

```
lib/src/codecs/vpx/
├── vpx_bindings.dart      # ffigen-generated libvpx bindings (do not edit by hand)
├── vpx_loader.dart        # cross-platform DynamicLibrary loader
├── vp8-test-vectors/      # 61 conformance IVFs + per-frame MD5 reference (data only)
└── README.md              # this file
```

## Native library

libvpx is a C library; this package only links to it at runtime. Install it
yourself:

| OS | Command / location |
| --- | --- |
| Windows (MSYS2) | `pacman -S mingw-w64-x86_64-libvpx` → `C:\msys64\mingw64\bin\libvpx-1.dll` |
| macOS | `brew install libvpx` → `/opt/homebrew/lib/libvpx.dylib` |
| Debian / Ubuntu | `apt install libvpx7` (or `libvpx6`) → `/usr/lib/x86_64-linux-gnu/libvpx.so.7` |

The loader in [vpx_loader.dart](vpx_loader.dart) tries, in order:

1. `$VPX_LIB_PATH` (env var override — absolute path to the shared library)
2. The platform's default candidates (DLL/dylib/so + common install prefixes)

If every candidate fails, it throws `VpxLoaderException` listing every path it
tried.

## ABI versions

The `*_init_ver` functions reject calls whose ABI constant doesn't match the
exact value libvpx was compiled with. The values that ship in
`vpx_bindings.dart` were probed against libvpx 1.14:

| Constant | Value |
| --- | --- |
| `VPX_ENCODER_ABI_VERSION` | **34** |
| `VPX_DECODER_ABI_VERSION` | **12** |

If you swap libvpx for a different major version you must regenerate the
bindings (see "Regenerating bindings" below).

## IVF container format

All three CLIs read/write [IVF](https://wiki.multimedia.cx/index.php/IVF), a
minimal container used by libvpx tools and the VP8 test-vector suite.

**File header — 32 bytes, little-endian**

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 4 | Magic `"DKIF"` (stored as `0x46494B44` LE) |
| 4 | 2 | Version (0) |
| 6 | 2 | Header length (32) |
| 8 | 4 | FourCC — `"VP80"` or `"VP90"` |
| 12 | 2 | Width |
| 14 | 2 | Height |
| 16 | 4 | Time-base denominator (FPS) |
| 20 | 4 | Time-base numerator (1) |
| 24 | 4 | Frame count |
| 28 | 4 | Reserved |

> **Subtle bug from a prior cycle**: the magic is the four ASCII bytes
> `D K I F` _stored_ in that order, which on a little-endian read of a `uint32`
> reads back as `0x46494B44`. Writing `0x46564944` (which spells "DIVF") makes
> ffmpeg, mplayer, and libvpx all silently reject the file.

**Per-frame header — 12 bytes**

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 4 | Frame size (bytes that follow) |
| 4 | 8 | PTS (in time-base ticks) |

## Encoder pipeline (`vpx_encode.dart`)

```text
RGB24 file ──► _rgb24ToI420 ──► vpx_image_t (I420) ──► vpx_codec_encode
                                                                 │
                                                                 ▼
                                              vpx_codec_get_cx_data (loop)
                                                                 │
                                       VPX_CODEC_CX_FRAME_PKT ──┘
                                                                 │
                                                                 ▼
                                                IVF frame header + payload
```

Key calls (`NativeLibrary` from `vpx_bindings.dart`):

```dart
final ctx = calloc<vpx_codec_ctx_t>();
final iface = lib.vpx_codec_vp8_cx();
lib.vpx_codec_enc_config_default(iface, cfg, 0);
lib.vpx_codec_enc_init_ver(ctx, iface, cfg, 0, VPX_ENCODER_ABI_VERSION);

final img = lib.vpx_img_alloc(
    ffi.nullptr, vpx_img_fmt.VPX_IMG_FMT_I420, w, h, 1);

// per frame
lib.vpx_codec_encode(ctx, img, frameIndex, 1, 0, 1);

// flush after the last frame
lib.vpx_codec_encode(ctx, ffi.nullptr, -1, 1, 0, 1);
```

> **Subtle bug**: `pkt.buf.asTypedList(pkt.sz)` returns a **view** of native
> memory that libvpx overwrites on the next `vpx_codec_encode`. Writing that
> view directly to an `IOSink` queues a reference, not a copy, so by the time
> the bytes hit disk every frame after the first has been overwritten by the
> next one's payload. The encoder always copies first:
>
> ```dart
> sink.add(Uint8List.fromList(pkt.buf.cast<Uint8>().asTypedList(pkt.sz)));
> ```

## Decoder pipeline (`vpx_decode.dart`)

```text
IVF file ──► _readIvfHeader ──► pick vpx_codec_vp8_dx() / vp9_dx()
                                              │
                                              ▼
            ┌──────── per frame ────────┐
            │  _readIvfFrame             │
            │  vpx_codec_decode          │
            │  while (vpx_codec_get_frame│
            │           != null) emit    │
            └────────────────────────────┘
                              │
                              ▼
                      raw I420 YUV file
```

The decoder honours the image's **display** dimensions (`d_w`, `d_h`) and
4:2:0 chroma rounding (`(d_w+1)/2 × (d_h+1)/2`), which matters for test
vectors with odd dimensions.

## Conformance runner (`vpx_test_vectors.dart`)

`vp8-test-vectors/` is a clone of the upstream libvpx VP8 conformance suite.
Each `<name>.ivf` ships with a `<name>.ivf.md5` listing the expected MD5 of
every decoded I420 frame.

```bash
# Run the whole VP8 suite (default folder is the bundled one)
dart run bin/vpx_test_vectors.dart

# Filter by name substring
dart run bin/vpx_test_vectors.dart --filter sharpness

# Include VP9 (skipped by default; only runs if --vp9 is passed)
dart run bin/vpx_test_vectors.dart --vp9 --dir path/to/vp9-test-vectors

# Point at a different folder
dart run bin/vpx_test_vectors.dart --dir external/vp8-test-vectors
```

Output:

```
PASS  vp80-00-comprehensive-001.ivf  (29 frames, VP80)
PASS  vp80-00-comprehensive-002.ivf  (49 frames, VP80)
…
Summary: 61 passed, 0 failed, 0 skipped, total 61
```

The runner exits `0` on full pass, `1` on any failure or load error.

## VP9 support

VP9 decode works through the same code path: pass an IVF whose FourCC is
`"VP90"` to `bin/vpx_decode.dart` and it picks `vpx_codec_vp9_dx()`
automatically. The conformance runner skips VP9 vectors unless `--vp9` is set,
because the bundled folder is the VP8 suite. To run the VP9 suite, fetch
`https://chromium.googlesource.com/webm/vp9-test-vectors`, drop it somewhere,
and point `--dir` at it.

There is **no VP9 encoder CLI** yet. Adding one is a one-line change
(`lib.vpx_codec_vp9_cx()` instead of `vpx_codec_vp8_cx()` in
`bin/vpx_encode.dart`); the rest of the I420-in / IVF-out pipeline is
codec-agnostic.

## Quick recipes

```bash
# Encode raw RGB24 → VP8 IVF
dart run bin/vpx_encode.dart \
    --width 384 --height 216 --fps 25 --bitrate 800 \
    video.rgb24 output.ivf

# Decode VP8/VP9 IVF → I420 YUV
dart run bin/vpx_decode.dart output.ivf decoded.yuv

# Inspect an I420 with ffplay
ffplay -f rawvideo -pixel_format yuv420p -video_size 384x216 decoded.yuv

# Run the VP8 conformance suite
dart run bin/vpx_test_vectors.dart
```

## Regenerating bindings

`vpx_bindings.dart` is produced by [`package:ffigen`] from libvpx's public
headers (`vpx/vp8cx.h`, `vpx/vp8dx.h`, `vpx/vpx_codec.h`,
`vpx/vpx_encoder.h`, `vpx/vpx_decoder.h`, `vpx/vpx_image.h`). When upgrading
libvpx, regenerate and then re-probe the ABI version constants by feeding
candidate values to `vpx_codec_dec_init_ver` / `vpx_codec_enc_init_ver` until
they return `VPX_CODEC_OK`.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `VpxLoaderException` listing every tried path | libvpx not installed, or set `VPX_LIB_PATH` |
| `VPX_CODEC_ABI_MISMATCH` from `*_init_ver` | `VPX_*_ABI_VERSION` doesn't match the installed libvpx — regenerate bindings |
| Decoded frames have garbage after the first | Encoder forgot to copy `vpx_codec_cx_pkt_t.buf` before queuing it |
| `Invalid IVF file (missing DKIF signature)` | Magic was written as `0x46564944` ("DIVF") instead of `0x46494B44` ("DKIF") |
| MD5 mismatch on test vectors | Using `height ~/ 2` for chroma rows on odd-height vectors — use `(h+1) >> 1` |
