// common.dart

String joinSlice(String separator, bool indent, List<String> lines) {
  final buffer = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    if (indent) {
      buffer.write('\t');
    }
    buffer.write(lines[i]);
    if (i < lines.length - 1) {
      buffer.write(separator);
    }
  }
  return buffer.toString();
}

String processIndent(String title, String bullet, List<String> lines) {
  final buffer = StringBuffer();
  if (title.isNotEmpty) {
    buffer.write(title);
    buffer.write('\n');
  }
  for (var i = 0; i < lines.length; i++) {
    buffer.write('\t');
    if (bullet.isNotEmpty) {
      buffer.write('$bullet ');
    }
    if (lines[i].contains('\n')) {
      final parts = lines[i].split('\n');
      buffer.write(processIndent(parts[0], "", parts.sublist(1)));
    } else {
      buffer.write(lines[i]);
    }
    if (i < lines.length - 1) {
      buffer.write('\n');
    }
  }
  return buffer.toString();
}

List<String> toStrSlice(List<dynamic> values) {
  return values.map((e) => e as String).toList();
}

String maskIPString(String ip) {
  final parts = ip.split('.');
  final buffer = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    if (i > 0) {
      buffer.write('.');
    }
    if (i < 2) {
      buffer.write(parts[i]);
    } else {
      buffer.write('***');
    }
  }
  return buffer.toString();
}
