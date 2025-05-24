/*
 RFC 3261 - https://www.ietf.org/rfc/rfc3261.txt - 8.1.1.7 Via

 The Via header field indicates the transport used for the transaction
and identifies the location where the response is to be sent.  A Via
header field value is added only after the transport that will be
used to reach the next hop has been selected (which may involve the
usage of the procedures in [4]).

*/

import 'sip_enums.dart';

class sipVia {
  void parseSipVia(String v) {
    Src = v;
    var pos = 0;
    Src = v;
    ParseState state = ParseState.FIELD_BASE;

    // Init the output area
    // out.Trans = ""
    // out.Host = nil
    // out.Port = nil
    // out.Branch = nil
    // out.Rport = nil
    // out.Maddr = nil
    // out.Ttl = nil
    // out.Rcvd = nil
    // out.Src = nil

    // Keep the source line if needed
    // if keep_src {
    // 	out.Src = v
    // }
//     print("""
// Parsing Via header ...
// """);
    // Loop through the bytes making up the line
    while (pos < v.length) {
      // FSM
      switch (state) {
        case ParseState.FIELD_BASE:
          if (v[pos] != ' ') {
            // Not a space
            if (v.length > pos + 8 && v.substring(pos, pos + 8) == "SIP/2.0/") {
              // Transport type
              state = ParseState.FIELD_HOST;
              pos = pos + 8;
              if (v.substring(pos, pos + 3) == "UDP") {
                Trans = "udp";
                pos = pos + 3;
                continue;
              }
              if (v.substring(pos, pos + 3) == "TCP") {
                Trans = "tcp";
                pos = pos + 3;
                continue;
              }
              if (v.substring(pos, pos + 3) == "TLS") {
                Trans = "tls";
                pos = pos + 3;
                continue;
              }
              if (v.substring(pos, pos + 4) == "SCTP") {
                Trans = "sctp";
                pos = pos + 4;
                continue;
              }
            }
            // Look for a Branch identifier
            if (v.length > pos + 7 && v.substring(pos, pos + 7) == "branch=") {
              state = ParseState.FIELD_BRANCH;
              pos = pos + 7;
              continue;
            }
            // Look for a Rport identifier
            if (v.length > pos + 6 && v.substring(pos, pos + 6) == "rport=") {
              state = ParseState.FIELD_RPORT;
              pos = pos + 6;
              continue;
            }
            // Look for a maddr identifier
            if (v.length > pos + 6 && v.substring(pos, pos + 6) == "maddr=") {
              state = ParseState.FIELD_MADDR;
              pos = pos + 6;
              continue;
            }
            // Look for a ttl identifier
            if (v.length > pos + 4 && v.substring(pos, pos + 4) == "ttl=") {
              state = ParseState.FIELD_TTL;
              pos = pos + 4;
              continue;
            }
            // Look for a recevived identifier
            if (v.length > pos + 9 &&
                v.substring(pos, pos + 9) == "received=") {
              state = ParseState.FIELD_REC;
              pos = pos + 9;
              continue;
            }
          }

        case ParseState.FIELD_HOST:
          if (v[pos] == ':') {
            state = ParseState.FIELD_PORT;
            pos++;
            continue;
          }
          if (v[pos] == ';') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          if (v[pos] == ' ') {
            pos++;
            continue;
          }
          Host = Host == null ? v[pos] : Host! + v[pos];

        case ParseState.FIELD_PORT:
          if (v[pos] == ';') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          Port = Port == null ? v[pos] : Port! + v[pos];

        case ParseState.FIELD_BRANCH:
          if (v[pos] == ';') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          Branch = Branch == null ? v[pos] : Branch! + v[pos];

        case ParseState.FIELD_RPORT:
          if (v[pos] == ';') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          Rport = Rport == null ? v[pos] : v[pos];

        case ParseState.FIELD_MADDR:
          if (v[pos] == ';') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          Maddr = Maddr == null ? v[pos] : Branch! + v[pos];

        case ParseState.FIELD_TTL:
          if (v[pos] == ';') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          Ttl = Ttl == null ? v[pos] : Ttl! + v[pos];

        case ParseState.FIELD_REC:
          if (v[pos] == ';') {
            state = ParseState.FIELD_BASE;
            pos++;
            continue;
          }
          Rcvd = Rcvd == null ? v[pos] : Rcvd! + v[pos];
        default:
          {}
      }
      pos++;
    }

    // print("Trans: $Trans");
    // print("Host: $Host");
    // print("Port: $Port");
    // print("Branch: $Branch");
    // print("Rport: $Rport");
    // print("Maddr: $Maddr");
    // print("Port: $Port");
    // print("Ttl: $Ttl");
    // print("Rcvd: $Rcvd");
    // print("Src: $Src");
  }

  String? Trans; // classof Transport udp, tcp, tls, sctp etc
  String? Host; // Host part
  String? Port; // Port number
  String? Branch; //
  String? Rport; //
  String? Maddr; //
  String? Ttl; //
  String? Rcvd; //
  String? Src; // Full source if needed
}
