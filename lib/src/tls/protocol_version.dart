import 'dart:typed_data';

import 'package:dartls/types/types.dart';

class ProtocolVersion {
  Uint8 major;
  Uint8 minor;
  ProtocolVersion(this.major, this.minor);

  Uint8List marshal() {
    return Uint8List.fromList([major.value, major.value]);
  }

  @override
  String toString() {
    // TODO: implement toString
    return "ProtcolVersion{ major: $major, minor: $minor}";
  }
}
