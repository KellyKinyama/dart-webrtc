// Parses a single line that is in the format of a to line, v
// Also requires a pointer to a struct of type sipTo to write output to
// RFC 3261 - https://www.ietf.org/rfc/rfc3261.txt - 8.1.1.2 To

import 'sip_enums.dart';

class sipTo {
  void parseSipTo(String v) {
    Src = v;
    var pos = 0;
    ParseState state = ParseState.FIELD_BASE;

    // Init the output area
    // out.UriType = ""
    // out.Name = nil
    // out.User = nil
    // out.Host = nil
    // out.Port = nil
    // out.Tag = nil
    // out.UserType = nil
    // out.Src = nil

    // Keep the source line if needed
    // if keep_src {
    // 	out.Src = v
    // }

    // Loop through the bytes making up the line
    while (pos < v.length) {
      // FSM
      //fmt.Println("POS:", pos, "CHR:", string(v[pos]), "STATE:", state)
      switch (state) {
        case ParseState.FIELD_BASE:
          if (v[pos] == '"' && UriType == "") {
            state = ParseState.FIELD_NAMEQ;
            pos++;
            continue;
          }
          if (v[pos] != ' ') {
            // Not a space so check for uri types
            if (v.substring(pos, pos + 4) == "sip:") {
              state = ParseState.FIELD_USER;
              pos = pos + 4;
              UriType = "sip";
              continue;
            }
            if (v.substring(pos, pos + 5) == "sips:") {
              state = ParseState.FIELD_USER;
              pos = pos + 5;
              UriType = "sips";
              continue;
            }
            if (v.substring(pos, pos + 4) == "tel:") {
              state = ParseState.FIELD_USER;
              pos = pos + 4;
              UriType = "tel";
              continue;
            }
            // Look for a Tag identifier
            if (v.substring(pos, pos + 4) == "tag=") {
              state = ParseState.FIELD_TAG;
              pos = pos + 4;
              continue;
            }
            // Look for other identifiers and ignore
            if (v[pos] == '=') {
              state = ParseState.FIELD_IGNORE;
              pos = pos + 1;
              continue;
            }
            // Look for a User classidentifier
            if (v.substring(pos, pos + 5) == "user=") {
              state = ParseState.FIELD_USERTYPE;
              pos = pos + 5;
              continue;
            }
            // Check for other chrs
            if (v[pos] != '<' &&
                v[pos] != '>' &&
                v[pos] != ';' &&
                UriType == "") {
              state = ParseState.FIELD_NAME;
              continue;
            }
          }

        case ParseState.FIELD_NAMEQ:
          if (v[pos] == '"') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          Name = Name == null ? v[pos] : Name! + v[pos];

        case ParseState.FIELD_NAME:
          if (v[pos] == '<' || v[pos] == ' ') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          Name = Name == null ? v[pos] : Name! + v[pos];

        case ParseState.FIELD_USER:
          if (v[pos] == '@') {
            state = ParseState.FIELD_HOST;
            pos++;
            continue;
          }
          User = User == null ? v[pos] : User! + v[pos];

        case ParseState.FIELD_HOST:
          if (v[pos] == ':') {
            state = ParseState.FIELD_PORT;
            pos++;
            continue;
          }
          if (v[pos] == ';' || v[pos] == '>') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          Host = Host == null ? v[pos] : Host! + v[pos];

        case ParseState.FIELD_PORT:
          if (v[pos] == ';' || v[pos] == '>' || v[pos] == ' ') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          Port = Port == null ? v[pos] : Port! + v[pos];

        case ParseState.FIELD_USERTYPE:
          if (v[pos] == ';' || v[pos] == '>' || v[pos] == ' ') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          UserType = UserType == null ? v[pos] : UserType! + v[pos];

        case ParseState.FIELD_TAG:
          if (v[pos] == ';' || v[pos] == '>' || v[pos] == ' ') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          Tag = Tag == null ? v[pos] : Tag! + v[pos];

        case ParseState.FIELD_IGNORE:
          if (v[pos] == ';' || v[pos] == '>') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }

        default:
          {}
      }
      pos++;
    }

    // print("UriType: $UriType");
    // print("Name: $Name");
    // print("User: $User");
    // print("Host: $Host");
    // print("Port: $Port");
    // // print("Maddr: $Maddr");
    // print("Tag: $Tag");
    // print("UserType: $UserType");
    // print("Src: $Src");
    //print("Src: $Src");
  }

  String? UriType; // classof URI sip, sips, tel etc
  String? Name; // Named portion of URI
  String? User; // User part
  String? Host; // Host part
  String? Port; // Port number
  String? Tag; // Tag
  String? UserType; // User Type
  String? Src; // Full source if needed
}
