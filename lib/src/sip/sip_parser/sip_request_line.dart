/*
 RFC 3261 - https://www.ietf.org/rfc/rfc3261.txt

INVITE sip:01798300765@87.252.61.202;user=phone SIP/2.0
SIP/2.0 200 OK

*/
import 'sip_enums.dart';

class sipReq {
  parseSipReq(String v) {
    Src = v;
    var pos = 0;
    ParseState state = ParseState.FIELD_NULL;

    // Init the output area
    // UriType = "";
    // Method = "";
    // StatusCode = "";
    // User = "";
    // Host = "";
    // Port = "";
    // UserType = "";
    // Src = "";

    // Keep the source line if needed
    // if (keep_src==true) {
    // 	Src = v;
    // }
    //print("Request line: $v");
//     print("""
// Parsing Request line: ...
//     """);

    // Loop through the bytes making up the line
    while (pos < v.length) {
      // FSM
      switch (state) {
        case ParseState.FIELD_NULL:
          {
            if (v[pos].compareTo("A") >= 0 &&
                v[pos].compareTo("S") <= 0 &&
                pos == 0) {
              //print("StrComp: ${v[pos].compareTo("S".toLowerCase())}");
              //print("StrPos: $pos");

              state = ParseState.FIELD_METHOD;
              //print("Method first character: ${v[pos]}");
              continue;
            }
          }
        case ParseState.FIELD_METHOD:
          if (v[pos] == ' ' || pos > 9) {
            if (Method == "SIP/2.0") {
              state = ParseState.FIELD_STATUS;
              Method = "";
            } else {
              state = ParseState.FIELD_BASE;
            }
            pos++;
            continue;
          }
          Method = Method == null ? v[pos] : "$Method${v[pos]}";

        case ParseState.FIELD_BASE:
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
            if ((pos + 5 < v.length) && v.substring(pos, pos + 5) == "user=") {
              state = ParseState.FIELD_USERTYPE;
              pos = pos + 5;
              continue;
            }
            if (v[pos] == '@') {
              state = ParseState.FIELD_HOST;
              User = Host; // Move host to user
              Host = ""; // Clear the host
              pos++;
              continue;
            }
          }
        case ParseState.FIELD_USER:
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
          if (v[pos] == '@') {
            state = ParseState.FIELD_HOST;
            User = Host; // Move host to user
            Host = ""; // Clear the host
            pos++;
            continue;
          }
          Host =
              Host == null ? v[pos] : Host! + v[pos]; // Append to host for now

        case ParseState.FIELD_HOST:
          if (v[pos] == ':') {
            state = ParseState.FIELD_PORT;
            pos++;
            continue;
          }
          if (v[pos] == ';' || v[pos] == '>' || v[pos] == ' ') {
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

        case ParseState.FIELD_STATUS:
          if (v[pos] == ';' || v[pos] == '>') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          if (v[pos] == ' ') {
            state = ParseState.FIELD_STATUSDESC;
            pos++;
            continue;
          }
          StatusCode = StatusCode == null ? v[pos] : StatusCode! + v[pos];

        case ParseState.FIELD_STATUSDESC:
          if (v[pos] == ';' || v[pos] == '>') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          StatusDesc = StatusDesc == null ? v[pos] : StatusDesc! + v[pos];

        default:
          {}
      }
      pos++;
    }
    //print("Method: $Method");
    // print("UriType: $UriType");
    // print("StatusCode: $StatusCode");
    // print("StatusDesc: $StatusDesc");
    // print("User: $User");
    // print("Host: $Host");
    // print("Port: $Port");
    // print("UserType: $UserType");
    // print("Src: $Src");
  }

  String? Method; // Sip Method eg INVITE etc
  String? UriType; // classof URI sip, sips, tel etc
  String? StatusCode; // Status Code eg 100
  String? StatusDesc; // Status Code Description eg trying
  String? User; // User part
  String? Host; // Host part
  String? Port; // Port number
  String? UserType; // User Type
  String? Src; // Full source if needed
}

// func parseSipReq(v String, out *sipReq) {

// 	pos := 0
// 	state := 0

// 	// Init the output area
// 	out.UriType = ""
// 	out.Method = nil
// 	out.StatusCode = nil
// 	out.User = nil
// 	out.Host = nil
// 	out.Port = nil
// 	out.UserType = nil
// 	out.Src = nil

// 	// Keep the source line if needed
// 	if keep_src {
// 		out.Src = v
// 	}

// 	// Loop through the bytes making up the line
// 	for pos < len(v) {
// 		// FSM
// 		switch state {
// 		case FIELD_NULL:
// 			if v[pos] >= 'A' && v[pos] <= 'S' && pos == 0 {
// 				state = FIELD_METHOD
// 				continue
// 			}

// 		case FIELD_METHOD:
// 			if v[pos] == ' ' || pos > 9 {
// 				if string(out.Method) == "SIP/2.0" {
// 					state = FIELD_STATUS
// 					out.Method = String{}
// 				} else {
// 					state = FIELD_BASE
// 				}
// 				pos++
// 				continue
// 			}
// 			out.Method = append(out.Method, v[pos])

// 		case FIELD_BASE:
// 			if v[pos] != ' ' {
// 				// Not a space so check for uri types
// 				if getString(v, pos, pos+4) == "sip:" {
// 					state = FIELD_USER
// 					pos = pos + 4
// 					out.UriType = "sip"
// 					continue
// 				}
// 				if getString(v, pos, pos+5) == "sips:" {
// 					state = FIELD_USER
// 					pos = pos + 5
// 					out.UriType = "sips"
// 					continue
// 				}
// 				if getString(v, pos, pos+4) == "tel:" {
// 					state = FIELD_USER
// 					pos = pos + 4
// 					out.UriType = "tel"
// 					continue
// 				}
// 				if getString(v, pos, pos+5) == "user=" {
// 					state = FIELD_USERTYPE
// 					pos = pos + 5
// 					continue
// 				}
// 				if v[pos] == '@' {
// 					state = FIELD_HOST
// 					out.User = out.Host // Move host to user
// 					out.Host = nil      // Clear the host
// 					pos++
// 					continue
// 				}
// 			}
// 		case FIELD_USER:
// 			if v[pos] == ':' {
// 				state = FIELD_PORT
// 				pos++
// 				continue
// 			}
// 			if v[pos] == ';' || v[pos] == '>' {
// 				state = FIELD_BASE
// 				pos++
// 				continue
// 			}
// 			if v[pos] == '@' {
// 				state = FIELD_HOST
// 				out.User = out.Host // Move host to user
// 				out.Host = nil      // Clear the host
// 				pos++
// 				continue
// 			}
// 			out.Host = append(out.Host, v[pos]) // Append to host for now

// 		case FIELD_HOST:
// 			if v[pos] == ':' {
// 				state = FIELD_PORT
// 				pos++
// 				continue
// 			}
// 			if v[pos] == ';' || v[pos] == '>' || v[pos] == ' ' {
// 				state = FIELD_BASE
// 				pos++
// 				continue
// 			}
// 			out.Host = append(out.Host, v[pos])

// 		case FIELD_PORT:
// 			if v[pos] == ';' || v[pos] == '>' || v[pos] == ' ' {
// 				state = FIELD_BASE
// 				pos++
// 				continue
// 			}
// 			out.Port = append(out.Port, v[pos])

// 		case FIELD_USERTYPE:
// 			if v[pos] == ';' || v[pos] == '>' || v[pos] == ' ' {
// 				state = FIELD_BASE
// 				pos++
// 				continue
// 			}
// 			out.UserType = append(out.UserType, v[pos])

// 		case FIELD_STATUS:
// 			if v[pos] == ';' || v[pos] == '>' {
// 				state = FIELD_BASE
// 				pos++
// 				continue
// 			}
// 			if v[pos] == ' ' {
// 				state = FIELD_STATUSDESC
// 				pos++
// 				continue
// 			}
// 			out.StatusCode = append(out.StatusCode, v[pos])

// 		case FIELD_STATUSDESC:
// 			if v[pos] == ';' || v[pos] == '>' {
// 				state = FIELD_BASE
// 				pos++
// 				continue
// 			}
// 			out.StatusDesc = append(out.StatusDesc, v[pos])

// 		}
// 		pos++
// 	}
// }
