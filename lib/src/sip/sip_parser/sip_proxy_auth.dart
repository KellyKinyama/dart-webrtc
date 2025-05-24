/*
 RFC 3261 - https://www.ietf.org/rfc/rfc3261.txt - 8.1.1.5 CSeq

  The CSeq header field serves as a way to identify and order
  transactions.  It consists of a sequence number and a method.  The
  method MUST match that of the request.

  Example:

     CSeq: 4711 INVITE

*/

import 'sip_enums.dart';

class sipProxyAuth {
  void parseSipProxyAuth(String v) {
    Src = v;

    var pos = 0;
    ParseState state = ParseState.FIELD_AUTHORIZATION;

    // Init the output area
    // out.Id = nil
    // out.Method = nil
    // out.Src = nil

    // Keep the source line if needed
    // if keep_src {
    // 	out.Src = v
    // }
    //print("Authorization: $v");

    // Loop through the bytes making up the line
    while (pos < v.length) {
      // FSM
      //fmt.Println("POS:", pos, "CHR:", string(v[pos]), "STATE:", state)
      switch (state) {
        case ParseState.FIELD_AUTHORIZATION:
          if ((pos + 6 < v.length) && v.substring(pos, pos + 6) == 'Digest') {
            state = ParseState.FIELD_DIGEST;
            pos = pos + 6;
            //print("parsing Digest");
            continue;
          }

        case ParseState.FIELD_DIGEST:
          if ((pos + 10 < v.length) &&
              v.substring(pos, pos + 10) == 'username="') {
            state = ParseState.FIELD_USERNAME;
            pos = pos + 10;
            continue;
          }
          if ((pos + 7 < v.length) && v.substring(pos, pos + 7) == 'realm="') {
            state = ParseState.FIELD_REALM;
            pos = pos + 7;
            continue;
          }
          if ((pos + 7 < v.length) && v.substring(pos, pos + 7) == 'nonce="') {
            state = ParseState.FIELD_NONCE;
            pos = pos + 7;
            continue;
          }
          if ((pos + 10 < v.length) &&
              v.substring(pos, pos + 10) == 'response="') {
            state = ParseState.FIELD_RESPONSE;
            pos = pos + 10;
            continue;
          }

        case ParseState.FIELD_USERNAME:
          if (v[pos] == '"') {
            state = ParseState.FIELD_DIGEST;
            pos++; // = pos + 9;
            continue;
          }
          username = username == null ? v[pos] : username! + v[pos];
        case ParseState.FIELD_REALM:
          if (v[pos] == '"') {
            state = ParseState.FIELD_DIGEST;
            pos++; // = pos + 9;
            continue;
          }
          realm = realm == null ? v[pos] : realm! + v[pos];
        case ParseState.FIELD_NONCE:
          if (v[pos] == '"') {
            state = ParseState.FIELD_DIGEST;
            pos++; // = pos + 9;
            continue;
          }
          nonce = nonce == null ? v[pos] : nonce! + v[pos];
        case ParseState.FIELD_RESPONSE:
          if (v[pos] == '"') {
            state = ParseState.FIELD_DIGEST;
            pos++; // = pos + 9;
            continue;
          }
          response = response == null ? v[pos] : response! + v[pos];
        default:
          {}
      }
      pos++;
    }
    print("username: $username");
    print("realm: $realm");
    print("nonce: $nonce");
    print("response: $response");
  }

  String? username; // Cseq ID
  String? realm; // Cseq Method
  String? nonce; // Full source if needed
  String? response;
  String? Src; // Full source if needed
}
