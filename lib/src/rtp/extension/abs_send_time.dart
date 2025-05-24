import 'dart:typed_data';

import 'package:dartls/types/types.dart';

import 'extension.dart';

const ABS_SEND_TIME_EXTENSION_SIZE = 3;

class AbsSendTimeExtension extends HeaderExtension{
  Uint24 timestamp; //: u64,

  AbsSendTimeExtension(this.timestamp);

  Uint8List marshal() {
    return timestamp.toBytes();
  }

  factory AbsSendTimeExtension.unmarshal(Uint8List bytes) {
    return AbsSendTimeExtension(Uint24.fromBytes(bytes));
  }
}
