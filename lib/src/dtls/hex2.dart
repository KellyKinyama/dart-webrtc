import "package:hex/hex.dart";

List<int> hexDecode(String input) {
  return HEX.decode(input);
}

String hexEncode(List<int> input) {
  return HEX.encode(input);
}

void main() {
  final encodedhex = HEX.encode(const [
    185,
    77,
    39,
    185,
    147,
    77,
    62,
    8,
    165,
    46,
    82,
    215,
    218,
    125,
    171,
    250,
    196,
    132,
    239,
    227,
    122,
    83,
    128,
    238,
    144,
    136,
    247,
    172,
    226,
    239,
    205,
    233
  ]); // "010203"
  HEX.decode(
      "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"); // [1, 2, 3]
  print(encodedhex);
}
