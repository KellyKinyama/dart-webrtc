/*

RFC 3261 - https://www.ietf.org/rfc/rfc3261.txt - 8.1.1.8 Contact

   The Contact header field provides a SIP or SIPS URI that can be used
   to contact that specific instance of the UA for subsequent requests.
   The Contact header field MUST be present and contain exactly one SIP
   or SIPS URI in any request that can result in the establishment of a
   dialog.

Examples:

   Contact: "Mr. Watson" <sip:watson@worcester.bell-telephone.com>
      ;q=0.7; expires=3600,
      "Mr. Watson" <mailto:watson@bell-telephone.com> ;q=0.1
   m: <sips:bob@192.0.2.4>;expires=60

*/

import 'sip_enums.dart';

class sipContact {
  void parseSipContact(String v) {
    Src = v;
    var pos = 0;
    ParseState state = ParseState.FIELD_BASE;

    // Init the output area
    // out.UriType = ""
    // out.Name = nil
    // out.User = nil
    // out.Host = nil
    // out.Port = nil
    // out.Tran = nil
    // out.Qval = nil
    // out.Expires = nil
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
            if ((pos + 4 < v.length) && v.substring(pos, pos + 4) == "sip:") {
              state = ParseState.FIELD_USER;
              pos = pos + 4;
              UriType = "sip";
              continue;
            }
            if ((pos + 5 < v.length) && v.substring(pos, pos + 5) == "sips:") {
              state = ParseState.FIELD_USER;
              pos = pos + 5;
              UriType = "sips";
              continue;
            }
            if ((pos + 4 < v.length) && v.substring(pos, pos + 4) == "tel:") {
              state = ParseState.FIELD_USER;
              pos = pos + 4;
              UriType = "tel";
              continue;
            }
            // Look for a Q identifier
            if ((pos + 2 < v.length) && v.substring(pos, pos + 2) == "q=") {
              state = ParseState.FIELD_Q;
              pos = pos + 2;
              continue;
            }
            // Look for a Expires identifier
            if ((pos + 8 < v.length) &&
                v.substring(pos, pos + 8) == "expires=") {
              state = ParseState.FIELD_EXPIRES;
              pos = pos + 8;
              continue;
            }
            // Look for a transport identifier
            if ((pos + 10 < v.length) &&
                v.substring(pos, pos + 10) == "transport=") {
              state = ParseState.FIELD_TRAN;
              pos = pos + 10;
              continue;
            }
            // Look for other identifiers and ignore
            if (v[pos] == '=') {
              state = ParseState.FIELD_IGNORE;
              pos = pos + 1;
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

        case ParseState.FIELD_TRAN:
          if (v[pos] == ';' || v[pos] == '>' || v[pos] == ' ') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          Tran = Tran == null ? v[pos] : Tran! + v[pos];

        case ParseState.FIELD_Q:
          if (v[pos] == ';' || v[pos] == '>' || v[pos] == ' ') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          Qval = Qval == null ? v[pos] : Qval! + v[pos];

        case ParseState.FIELD_EXPIRES:
          if (v[pos] == ';' || v[pos] == '>' || v[pos] == ' ') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          Expires = Expires == null ? v[pos] : Expires! + v[pos];

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
    // print("Tran: $Tran");
    // print("Tag: $Qval");
    // print("Expires: $Expires");
    // print("Src: $Src");
  }

  String? UriType; // classof URI sip, sips, tel etc
  String? Name; // Named portion of URI
  String? User; // User part
  String? Host; // Host part
  String? Port; // Port number
  String? Tran; // Transport
  String? Qval; // Q Value
  String? Expires; // Expires
  String? Src; // Full source if needed
}
