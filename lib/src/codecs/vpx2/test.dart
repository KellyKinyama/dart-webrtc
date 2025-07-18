import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart'; // This is essential for .toDartString() and calloc

import 'vpx_bindings.dart'; // Adjust this path as necessary for your project structure

void main() {
  // Use Platform.script.toFilePath() to determine the current script's directory
  // This helps in locating DLLs relative to your executable or script.
  final String scriptDir = Platform.script.toFilePath().replaceAll('\\', '/');
  final String libraryPath;

  if (Platform.isWindows) {
    // Construct the path for Windows. Assuming libvpx-1.dll is directly accessible or in a known location.
    // C:/msys64/mingw64/bin/libvpx-1.dll is an absolute path, so no need for relative path logic here.
    libraryPath = 'C:/msys64/mingw64/bin/libvpx-1.dll';
  } else if (Platform.isMacOS) {
    // For macOS, 'libvpx.dylib' is the typical name.
    // If you explicitly copied it to the project, you might need a relative path.
    // E.g., '$scriptDir/../libvpx.dylib' or simply 'libvpx.dylib' if it's in a standard system location.
    libraryPath =
        'libvpx.dylib'; // Common name, or specify full path if custom location
  } else {
    // For Linux, 'libvpx.so' is typical.
    libraryPath =
        'libvpx.so'; // Common name, or specify full path if custom location
  }

  ffi.DynamicLibrary vpxLib;
  try {
    vpxLib = ffi.DynamicLibrary.open(libraryPath);
    print('Successfully opened $libraryPath');
  } catch (e) {
    print('Error opening library "$libraryPath": $e');
    print(
        'Please ensure the native library is correctly installed and accessible.');
    return;
  }

  final bindings = NativeLibrary(vpxLib);

  // Get the pointer to the C string for the version
  final ffi.Pointer<Utf8> versionCharPtr =
      bindings.vpx_codec_version_str().cast<Utf8>();
  // Convert the C string pointer to a Dart String using .toDartString()
  print('VPX Codec Version: ${versionCharPtr.toDartString()}');

  // Get the pointer to the C string for the build config
  final ffi.Pointer<Utf8> buildConfigPtr =
      bindings.vpx_codec_build_config().cast<Utf8>();
  // Convert the C string pointer to a Dart String using .toDartString()
  print('VPX Build Config: ${buildConfigPtr.toDartString()}');

  // Remember to properly close/cleanup any resources if you initialize a codec context later.
  // For the simple version functions, no extra cleanup is needed for the library itself.
}
