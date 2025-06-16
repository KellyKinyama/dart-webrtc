import 'package:opus_dart/opus_dart.dart';
import 'init_ffi.dart';

Future<void> main() async {
  await initFfi();
  initOpus(openOpus());
  print(getOpusVersion());
}
