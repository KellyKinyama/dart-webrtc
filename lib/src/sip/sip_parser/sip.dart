import 'sdp_attrib.dart';
import 'sdp_connection_data.dart';
import 'sdp_media_desc.dart';
import 'sip_contact.dart';
import 'sip_cseq.dart';
import 'sip_from.dart';
import 'sip_message_headers.dart';
import 'sip_proxy_auth.dart';
import 'sip_request_line.dart';
import 'sip_to.dart';
import 'sip_via.dart';
import 'sip_www_auth.dart';
import 'sip_auth.dart';
//import 'sip_message_types.dart';
//import 'sip_message_headers.dart';

class SipMsg {
  void Parse(String v) {
    src = v;
    // Allow multiple vias and media Attribs
    var via_idx = 0;
    Via = []; //make([]sipVia, 0, 8);
    var attr_idx = 0;
    Sdp.Attrib = []; //make([]sdpAttrib, 0, 8)

    // var hdrDelimeter = SipMessageHeaders.HEADERS_DELIMETER;

    // int pos = v.indexOf(SipMessageHeaders.HEADERS_DELIMETER);
    // // print(_messageStr);
    // // print(msg);
    // // print(" index: $pos");
    // if (pos == -1) return;
    // header = v.substring(0, pos);

    // v = v.substring(pos + SipMessageHeaders.HEADERS_DELIMETER.length);

    // if (header!.indexOf(" ") == -1) return;

    // //lines := bytes.Split(v, []byte("\r\n"))
    // var lines = v.split(hdrDelimeter);
    // print("Lines length: ${lines.length}");
    // //print("Lines length: ${lines.length}");
    // //print("Index of Headers delimiter: ${v.indexOf(delimeter)}");

    var hdrDelimeter = SipMessageHeaders.HEADERS_DELIMETER;

    //lines := bytes.Split(v, []byte("\r\n"))
    var lines = v.split(hdrDelimeter);
    //print("Lines length: ${lines.length}");
    //print("Index of Headers delimiter: ${v.indexOf(delimeter)}");

    for (int i = 0; i < lines.length; i++) {
      // 	//fmt.Println(i, string(line))

      var line = lines[i].trim();
      if (i == 0) {
        // For the first line parse the request
        //parseSipReq(line, Req);
        Req.parseSipReq(line);
      } else {
        // 		// For subsequent lines split in sep (: for sip, = for sdp)
        var delimeter = indexSep(line);
        var spos = delimeter.i;
        var stype = delimeter.dtype;
        if (spos > 0 && stype == ':') {
          // 			// SIP: Break up into header and value
          //var 			lhdr = strings.ToLower(string(line[0:spos]))
          var lhdr =
              line.substring(0, spos); //strings.ToLower(string(line[0:spos]))
          var lval = line.substring(spos + 1);

          lhdr = lhdr.toLowerCase();

          // print("header name: $lhdr");

          // 			// Switch on the line header
          // 			//fmt.Println(i, string(lhdr), string(lval))
          switch (lhdr) {
            case "f" || "from":
              // 				parseSipFrom(lval, &output.From)
              From.parseSipFrom(lval);
            case "t" || "to":
              // 				parseSipTo(lval, &output.To)
              To.parseSipTo(lval);
            case "m" || "contact":
              Contact.parseSipContact(lval);
            case "v" || "via":
              var tmpVia = sipVia();
              tmpVia.parseSipVia(lval);
              Via.add(tmpVia); // = append(output.Via, tmpVia)
              //parseSipVia(lval, &output.Via[via_idx])
              via_idx++;
            case "i" || "call-id":
              CallId.Value = lval;
            case "c" || "content-type":
              ContType.Value = lval;
            case "content-length":
              ContLen.Value = lval;
            case "user-agent":
              Ua.Value = lval;
            case "expires":
              Exp.Value = lval;
            case "max-forwards":
              MaxFwd.Value = lval;
            case "cseq":
              //parseSipCseq(lval, &output.Cseq)
              Cseq.parseSipCseq(lval);
            case "authorization":
              Auth.parseSipAuth(lval);
            case "www-authenticate":
              wwwAuth.parseSipAuth(lval);
            case "proxy-authorization":
              ProxyAuth.parseSipProxyAuth(lval);
          } // End of Switch
        }
        if (spos == 1 && stype == '=') {
          // SDP: Break up into header and value
          var lhdr = line[0].toLowerCase();
          var lval = line.substring(2);
          // Switch on the line header
          //fmt.Println(i, spos, string(lhdr), string(lval))
          switch (lhdr) {
            case "m":
              Sdp.MediaDesc.parseSdpMediaDesc(lval);
            case "c":
              Sdp.ConnData.parseSdpConnectionData(lval);
            case "a":
              var tmpAttrib = sdpAttrib();
              tmpAttrib.parseSdpAttrib(
                  lval); // = append(output.Sdp.Attrib, tmpAttrib)
              Sdp.Attrib!.add(tmpAttrib);
              //parseSdpAttrib(lval, &output.Sdp.Attrib[attr_idx])
              attr_idx++;
          } // End of Switch
        }
      }
    }
  }

// Finds the first valid Seperate or notes its type
  dynamic indexSep(String s) {
    for (int i = 0; i < s.length; i++) {
      if (s[i] == ':') {
        return (i: i, dtype: ':'); //, ':'
      }
      if (s[i] == '=') {
        return (i: i, dtype: '='); //, '='
      }
    }
    return (i: -1, dtype: null); //, ' '
  }

  // void setHeader(String value) {
  //   // print("Setting header");
  //   int headerPos = Src!.indexOf(header!);

  //   //print("header position $headerPos for $_header to be replaced with $value");
  //   if (headerPos == -1) {
  //     // print("Header not found");
  //     return;
  //   }
  //   Src = Src!.replaceFirst(header!, value, headerPos);
  //   header = value;

  //   // print(_messageStr);
  // }

  sipReq Req = sipReq();
  sipFrom From = sipFrom();
  sipTo To = sipTo();
  sipContact Contact = sipContact();
  List<sipVia> Via = [];
  sipCseq Cseq = sipCseq();
  sipVal Ua = sipVal();
  sipVal Exp = sipVal();
  sipVal MaxFwd = sipVal();
  sipVal CallId = sipVal();
  sipVal ContType = sipVal();
  sipVal ContLen = sipVal();
  sipAuth Auth = sipAuth();
  sipProxyAuth ProxyAuth = sipProxyAuth();
  //String? Src; // Full source if needed
  String? header;

  sipWwwAuth wwwAuth = sipWwwAuth();

  SdpMsg Sdp = SdpMsg();

  sockaddr_in? transport;

  String? src;
}

class SdpMsg {
  sdpMediaDesc MediaDesc = sdpMediaDesc();
  List<sdpAttrib> Attrib = [];
  sdpConnData ConnData = sdpConnData();
  String? Src; // Full source if needed
}

class sipVal {
  String? Value; // Sip Value
  String? Src; // Full source if needed
}

class sockaddr_in {
  sockaddr_in(this.addr, this.port, this.transport);
  String addr;
  String transport;
  int port;
}
