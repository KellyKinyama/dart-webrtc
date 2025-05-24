/*
RFC4566 - https://tools.ietf.org/html/rfc4566#section-5.14

5.14.  Media Descriptions ("m=")

  m=<media> <port> <proto> <fmt> ...

A session description may contain a number of media descriptions.
Each media description starts with an "m=" field and is terminated by
either the next "m=" field or by the end of the session description.

eg:
m=audio 24414 RTP/AVP 8 18 101

*/

import 'sip_enums.dart';

class sdpMediaDesc {
  void parseSdpMediaDesc(String v) {
    Src = v;

    var pos = 0;
    ParseState state = ParseState.FIELD_MEDIA;

    // Init the output area
    // out.MediaType = nil
    // out.Port = nil
    // out.Proto = nil
    // out.Fmt = nil
    // out.Src = nil

    // Keep the source line if needed
    // if keep_src {
    // 	out.Src = v
    // }

    // Loop through the bytes making up the line
    while (pos < v.length) {
      // FSM
      switch (state) {
        case ParseState.FIELD_MEDIA:
          if (v[pos] == ' ') {
            state = ParseState.FIELD_PORT;
            pos++;
            continue;
          }
          MediaType = MediaType == null ? v[pos] : MediaType! + v[pos];

        case ParseState.FIELD_PORT:
          if (v[pos] == ' ') {
            state = ParseState.FIELD_PROTO;
            pos++;
            continue;
          }
          Port = Port == null ? v[pos] : Port! + v[pos];

        case ParseState.FIELD_PROTO:
          if (v[pos] == ' ') {
            state = ParseState.FIELD_FMT;
            pos++;
            continue;
          }
          Proto = Proto == null ? v[pos] : Proto! + v[pos];

        case ParseState.FIELD_FMT:
          Fmt = Fmt == null ? v[pos] : Fmt! + v[pos];

        default:
          {}
      }
      pos++;
    }
  }

  String? MediaType; // Named portion of URI
  String? Port; // Port number
  String? Proto; // Protocol
  String? Fmt; // Fmt
  String? Src; // Full source if needed
}
