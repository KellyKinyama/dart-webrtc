List<String> linePartsParser(String line, String letter) {
  final lineContent = line.replaceFirst("$letter=", '');
  return lineContent.split(' ');
}
