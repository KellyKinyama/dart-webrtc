/*
 RFC 3261 - https://www.ietf.org/rfc/rfc3261.txt - 8.1.1.5 CSeq

  The CSeq header field serves as a way to identify and order
  transactions.  It consists of a sequence number and a method.  The
  method MUST match that of the request.

  Example:

     CSeq: 4711 INVITE

*/

import 'sip_enums.dart';

class sipCseq {
  void parseSipCseq(String v) {
    Src = v;

    var pos = 0;
    ParseState state = ParseState.FIELD_ID;

    // Init the output area
    // out.Id = nil
    // out.Method = nil
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
        case ParseState.FIELD_ID:
          if (v[pos] == ' ') {
            state = ParseState.FIELD_METHOD;
            pos++;
            continue;
          }
          Id = Id == null ? v[pos] : Id! + v[pos];

        case ParseState.FIELD_METHOD:
          Method = Method == null ? v[pos] : Method! + v[pos];
        default:
          {}
      }
      pos++;
    }
  }

  String? Id; // Cseq ID
  String? Method; // Cseq Method
  String? Src; // Full source if needed
}
