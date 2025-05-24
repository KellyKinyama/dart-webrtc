String joinSlice(String separator, bool indent, List<String> lines) {
  String result = "";
  int i = 0;
  for (String line in lines) {
    if (indent) {
      result += "\t";
    }
    result += line;
    if (i < lines.length - 1) {
      result += separator;
    }
    i++;
  }
  return result;
}

String processIndent(String title, String bullet, List<String> lines) {
  String result = title;
  if (result != "") {
    result += "\n";
  }
  int i = 0;
  for (String line in lines) {
    result += "\t";
    if (bullet != "") {
      result += "$bullet ";
    }
    if (line.contains("\n")) {
      final parts = line.split("\n");
      result += processIndent(parts[0], "", parts.sublist(1));
    } else {
      result += line;
    }
    if (i < lines.length - 1) {
      result += "\n";
    }
  }
  return result;
}
