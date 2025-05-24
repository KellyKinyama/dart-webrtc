import 'dart:typed_data';

import 'handshake.dart';

class ChangeCipherSpec {
  ContentType getContentType() {
    return ContentType.content_change_cipher_spec;
  }

  int get size => 1;

  Uint8List marshal() {
    return (Uint8List.fromList([0x01]));
  }

  static (ChangeCipherSpec, int, bool?) unmarshal(
      Uint8List buf, int offset, int arrayLen) {
    if (buf[offset] != 0x01) {
      throw ('Invalid Cipher Spec');
    }
    offset++;
    return (ChangeCipherSpec(), offset, null);
  }

  static (ChangeCipherSpec, int, bool?) decode(
      Uint8List buf, int offset, int arrayLen) {
    return (ChangeCipherSpec(), buf[offset], null);
  }

  @override
  String toString() {
    return 'ChangeCipherSpec(size: $size, contentType: ${getContentType()})';
  }
}
