import 'dart:typed_data';
import 'dart:io';

Future<void> saveOrDownload(Uint8List data) async {
  await (File('output.wav')).writeAsBytes(data);
}
