// Notice that in this file, we import dart:ffi and not proxy_ffi.dart
import 'dart:ffi';
import 'dart:io' show Platform;
import 'package:opus_dart/opus_dart.dart';

// For dart:ffi platforms, this can be a no-op (empty function)
Future<void> initFfi() async {}

DynamicLibrary openOpus() {
  DynamicLibrary lib;
  if (Platform.isWindows) {
    bool x64 = Platform.version.contains('x64');
    if (x64) {
      lib = new DynamicLibrary.open(
          'C:/www/dart/opus_dart/assets/codecs/libopus_x64.dll');
    } else {
      lib = new DynamicLibrary.open('path/to/libopus_x86.dll');
    }
  } else if (Platform.isLinux) {
    lib = new DynamicLibrary.open('/usr/local/lib/libopus.so');
  } else {
    throw new UnsupportedError('This programm does not support this platform!');
  }
  return lib;
}

Future<void> main() async {
  await initFfi();
  initOpus(openOpus());
  print(getOpusVersion());
}
