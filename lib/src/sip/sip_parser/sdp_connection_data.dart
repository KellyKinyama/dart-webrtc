/*
RFC4566 - https://tools.ietf.org/html/rfc4566#section-5.7

5.7.  Connection Data ("c=")

  c=<nettype> <addrtype> <connection-address>

  c=IN IP4 88.215.55.98
*/

import 'sip_enums.dart';

class sdpConnData {
  void parseSdpConnectionData(String v) {
    Src = v;
    var pos = 0;
    ParseState state = ParseState.FIELD_BASE;

    // Init the output area
    //out.NetType = nil
    // out.AddrType = nil
    // out.ConnAddr = nil
    // out.Src = nil

    // Keep the source line if needed
    // if keep_src {
    // 	out.Src = v
    // }

    // Loop through the bytes making up the line
    while (pos < v.length) {
      // FSM
      switch (state) {
        case ParseState.FIELD_BASE:
          if (v[pos] == ' ') {
            state = ParseState.FIELD_ADDRTYPE;
            pos++;
            continue;
          }
        case ParseState.FIELD_ADDRTYPE:
          if (v[pos] == ' ') {
            state = ParseState.FIELD_CONNADDR;
            pos++;
            continue;
          }
          AddrType = AddrType == null ? v[pos] : AddrType! + v[pos];

        case ParseState.FIELD_CONNADDR:
          if (v[pos] == ' ') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          ConnAddr = ConnAddr == null ? v[pos] : ConnAddr! + v[pos];
        default:
          {}
      }
      pos++;
    }
  }

  //NetType   String // Network Type
  String? AddrType; // Address Type
  String? ConnAddr; // Connection Address
  String? Src; // Full source if needed
}
