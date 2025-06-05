import "package:hex/hex.dart";

List<int> hexDecode(String input) {
  return HEX.decode(input);
}

String hexEncode(List<int> input) {
  return HEX.encode(input);
}