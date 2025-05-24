import 'sip_enums.dart';


/*
  RFC4566 - https://tools.ietf.org/html/rfc4566#section-5.14

  6.  SDP Attributes

 The following attributes are defined.  Since application writers may
 add new attributes as they are required, this list is not exhaustive.
 Registration procedures for new attributes are defined in Section
 8.2.4.

    a=cat:<category>

       This attribute gives the dot-separated hierarchical category of
       the session.  This is to enable a receiver to filter unwanted
       sessions by category.  There is no central registry of
       categories.  It is a session-level attribute, and it is not
       dependent on charset.

 eg:
 a=ptime:20

*/

class sdpAttrib {
  void parseSdpAttrib(String v) {
    Src = v;
    var pos = 0;
    ParseState state = ParseState.FIELD_CAT;

    // Init the output area
    // out.Cat = nil
    // out.Val = nil
    // out.Src = nil

    // // Keep the source line if needed
    // if keep_src {
    // 	out.Src = v
    // }

    // Loop through the bytes making up the line
    while (pos < v.length) {
      // FSM
      switch (state) {
        case ParseState.FIELD_CAT:
          if (v[pos] == ':') {
            state = ParseState.FIELD_VALUE;
            pos++;
            continue;
          }
          Cat = Cat == null ? v[pos] : Cat! + v[pos];

        case ParseState.FIELD_VALUE:
          Val = Val == null ? v[pos] : Val! + v[pos];
        default:
          {}
      }
      pos++;
    }
  }

  String? Cat; // Named portion of URI
  String? Val; // Port number
  String? Src; // Full source if needed
}
