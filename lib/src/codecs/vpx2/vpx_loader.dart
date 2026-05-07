// Resolves the libvpx shared library across platforms.
//
// Resolution order:
//   1. The `VPX_LIB_PATH` environment variable, if set (must be an
//      absolute path to the shared library).
//   2. A short list of common installation paths per platform.
//   3. The bare library name, which lets the dynamic loader search
//      `PATH` / `LD_LIBRARY_PATH` / `DYLD_LIBRARY_PATH`.
//
// Throws [VpxLoaderException] with all attempted paths if no candidate
// can be opened.

import 'dart:ffi' as ffi;
import 'dart:io';

import 'vpx_bindings.dart';

class VpxLoaderException implements Exception {
  final List<String> attempted;
  VpxLoaderException(this.attempted);
  @override
  String toString() =>
      'Could not load libvpx. Tried:\n  - ${attempted.join('\n  - ')}\n'
      'Set the VPX_LIB_PATH environment variable to the absolute path of '
      'libvpx (e.g. C:/msys64/mingw64/bin/libvpx-1.dll, /usr/lib/x86_64-linux-gnu/libvpx.so.7).';
}

/// Opens libvpx and returns the high-level [NativeLibrary] wrapper.
NativeLibrary loadVpx() {
  final tried = <String>[];

  ffi.DynamicLibrary? open(String path) {
    tried.add(path);
    try {
      return ffi.DynamicLibrary.open(path);
    } catch (_) {
      return null;
    }
  }

  // 1. Explicit override.
  final override = Platform.environment['VPX_LIB_PATH'];
  if (override != null && override.isNotEmpty) {
    final lib = open(override);
    if (lib != null) return NativeLibrary(lib);
  }

  // 2. Per-platform candidates.
  final candidates = <String>[
    if (Platform.isWindows) ...[
      'libvpx-1.dll',
      'vpx.dll',
      r'C:\msys64\mingw64\bin\libvpx-1.dll',
      r'C:\msys64\ucrt64\bin\libvpx-1.dll',
    ],
    if (Platform.isMacOS) ...[
      'libvpx.dylib',
      '/opt/homebrew/lib/libvpx.dylib',
      '/usr/local/lib/libvpx.dylib',
    ],
    if (Platform.isLinux) ...[
      'libvpx.so',
      'libvpx.so.7',
      'libvpx.so.6',
      '/usr/lib/x86_64-linux-gnu/libvpx.so.7',
      '/usr/lib/x86_64-linux-gnu/libvpx.so.6',
    ],
  ];

  for (final c in candidates) {
    final lib = open(c);
    if (lib != null) return NativeLibrary(lib);
  }

  throw VpxLoaderException(tried);
}
