import 'dart:typed_data';

import '../../../types/types.dart';
import 'extension.dart';

class AudioLevelExtension extends HeaderExtension {
  Uint8 level; //: u8,
  bool voice; //: bool,

  AudioLevelExtension(this.level, this.voice);

  factory AudioLevelExtension.fromBytes(Uint8List bytes) {
    Uint8 level = Uint8(bytes[0] & 0x7F); //: u8,
    bool voice = (bytes[0] & 0x80) != 0; //: bool,

    return AudioLevelExtension(level, voice);
  }
}
