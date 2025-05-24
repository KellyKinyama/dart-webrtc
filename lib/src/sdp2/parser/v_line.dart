int vLineParser(String line) {
  return int.parse(line.replaceFirst('v=', ''));
}
