
String JoinSlice(String separator, bool indent, List<String> lines) {
	String result = "";
  int i=0;
	for (String line in lines) {
		if (indent) {
			result += "\t";
		}
		result += line;
		if (i < lines.length-1) {
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
  int i=0;
	for (String line in lines) {
		result += "\t";
		if (bullet != "") {
			result += "$bullet ";
		}
		if (line.contains( "\n")) {
			final parts = line.split("\n");
			result += processIndent(parts[0], "", parts.sublist(1));
		} else {
			result += line;
		}
		if (i < lines.length-1) {
			result += "\n";
		}
	}
	return result;
}

func ToStrSlice(v ...interface{}) []string {
	result := make([]string, len(v))
	for i, item := range v {
		result[i] = item.(string)
	}
	return result
}

func MaskIPString(ip string) string {
	parts := strings.Split(ip, ".")
	result := ""
	for i, part := range parts {
		if i > 0 {
			result += "."
		}
		if i < 2 {
			result += part
		} else {
			result += "***"
		}
	}
	return result
}
