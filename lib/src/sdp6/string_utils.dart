// string_utils.dart

/// Joins a list of strings with a [separator].
///
/// If [indent] is true, each line (including the first) will be prefixed with a tab character.
String joinSlice(String separator, bool indent, List<String> lines) {
  if (lines.isEmpty) {
    return "";
  }

  StringBuffer result = StringBuffer();
  String prefix = indent ? "\t" : "";

  for (int i = 0; i < lines.length; i++) {
    result.write(prefix);
    result.write(lines[i]);
    if (i < lines.length - 1) {
      result.write(separator);
    }
  }
  return result.toString();
}

// Example Usage:
void main() {
  List<String> items = ["Line 1", "Line 2", "Line 3"];

  print("--- JoinSlice (no indent) ---");
  print(joinSlice("\n", false, items));
  // Output:
  // Line 1
  // Line 2
  // Line 3

  print("\n--- JoinSlice (with indent) ---");
  print(joinSlice("\n", true, items));
  // Output:
  //   Line 1
  //   Line 2
  //   Line 3

  List<String> singleItem = ["Only one line"];
  print("\n--- JoinSlice (single item, with indent) ---");
  print(joinSlice("\n", true, singleItem));
  // Output:
  //   Only one line

  List<String> emptyList = [];
  print("\n--- JoinSlice (empty list) ---");
  print(joinSlice("\n", true, emptyList));
  // Output:
  // (empty string)
}

// string_utils.dart (continued)

/// Formats a list of strings with a title, indentation, and optional bullets.
///
/// [title] is printed first, followed by a newline if not empty.
/// Each [line] in [lines] is then indented with a tab.
/// If [bullet] is not empty, it's added before each line (after the tab).
/// If a line itself contains newlines, it's treated as a sub-list and processed recursively.
String processIndent(String title, String bullet, List<String> lines) {
  StringBuffer result = StringBuffer();

  if (title.isNotEmpty) {
    result.writeln(title); // writeln adds a newline character at the end
  }

  for (int i = 0; i < lines.length; i++) {
    String line = lines[i];
    String indentPrefix = "\t";
    String bulletPrefix = bullet.isNotEmpty ? "$bullet " : "";

    if (line.contains("\n")) {
      List<String> parts = line.split("\n");
      String firstPartOfLine = parts.first;
      List<String> remainingPartsOfLine = parts.sublist(1);

      // Add the current level's indentation and bullet to the first part of the multi-line entry
      result.write(indentPrefix);
      result.write(bulletPrefix);

      // The first part of the split line acts as a new 'title' for the recursive call,
      // and sub-lines get no further bullet from this level.
      // The sub-lines will be indented by the recursive call itself.
      result.write(processIndent(firstPartOfLine, "", remainingPartsOfLine));
    } else {
      result.write(indentPrefix);
      result.write(bulletPrefix);
      result.write(line);
    }

    if (i < lines.length - 1) {
      result.writeln(); // Add newline between items in the list
    }
  }
  return result.toString();
}

// Example Usage (in main or a test):
// void main() {
//   // ... (previous joinSlice examples)

//   print("\n--- ProcessIndent (Simple) ---");
//   List<String> simpleLines = ["Item A", "Item B", "Item C"];
//   print(processIndent("My List:", "*", simpleLines));
//   // Output:
//   // My List:
//   // 	* Item A
//   // 	* Item B
//   // 	* Item C

//   print("\n--- ProcessIndent (No Bullet) ---");
//   print(processIndent("My Notes:", "", simpleLines));
//   // Output:
//   // My Notes:
//   // 	Item A
//   // 	Item B
//   // 	Item C

//   print("\n--- ProcessIndent (With Multi-line Item) ---");
//   List<String> complexLines = [
//     "Chapter 1",
//     "Chapter 2\n  - Section 2.1\n  - Section 2.2",
//     "Chapter 3"
//   ];
//   print(processIndent("Table of Contents:", "-", complexLines));
//   // Output:
//   // Table of Contents:
//   // 	- Chapter 1
//   // 	- Chapter 2
//   // 		- Section 2.1
//   // 		- Section 2.2
//   // 	- Chapter 3

//   print("\n--- ProcessIndent (Empty Title) ---");
//   print(processIndent("", "+", simpleLines));
//   // Output:
//   // 	+ Item A
//   // 	+ Item B
//   // 	+ Item C

//   print("\n--- ProcessIndent (Empty Lines) ---");
//   print(processIndent("Empty Section:", "*", []));
//   // Output:
//   // Empty Section:
//   // (followed by a newline from writeln(title))

//    print("\n--- ProcessIndent (Multi-line item is first) ---");
//     List<String> multiFirst = [
//     "Introduction\n  - Overview\n  - Goals",
//     "Conclusion"
//     ];
//     print(processIndent("Document Outline:", ">", multiFirst));
//     // Expected Output:
//     // Document Outline:
//     // 	> Introduction
//     // 		- Overview
//     // 		- Goals
//     // 	> Conclusion
// }
