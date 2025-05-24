import "dart:core";
import 'dart:ffi';
import 'dart:math';

import 'dialog/dialog.dart';
import 'sip_parser/sip_message_headers.dart';
import 'sip_parser/sip_message_types.dart';

import 'globals.dart';
//import "SipMessage.dart";
import "sip_client.dart";
import "session.dart";
import 'dart:io';

import 'dart:convert';
//import 'SipMessageTypes.dart';
//import 'SipSdpMessage.dart';
import 'sip_parser/sip.dart';

import 'transactions/transaction_base.dart';

String IDGen() {
  String out = "";
  String temp =
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJK7LMNOPQRSTUVWXYZ0123456789";
  for (var x = 0; x < 9; x++) {
    var intValue = Random().nextInt(temp.length);
    out += temp[intValue % temp.length];
  }
  return out;
}

class ReqHandler {
  int _serverPort;
  Map<String, SipClient> _clients = {};

  Map<String, Dialog> dialogs = {};
  Map<String, Function(SipMessage)> handlers = {};
  void Function(sockaddr_in, dynamic)? _onHandled;
  String _serverIp;
  ReqHandler(String serverIp, int serverPort, RawDatagramSocket socket)
      : _serverIp = serverIp,
        _serverPort = serverPort,
        this.socket = socket {
    // SipMessageTypes.REGISTER,
    // SipMessageTypes.CANCEL,
    // SipMessageTypes.INVITE,
    // SipMessageTypes.TRYING,
    // SipMessageTypes.RINGING,
    //   SipMessageTypes.BUSY,
    //   SipMessageTypes.UNAVAIALBLE,
    //   SipMessageTypes.OK,
    //   SipMessageTypes.ACK,
    //   SipMessageTypes.BYE,
    //   SipMessageTypes.REQUEST_TERMINATED,

    handlers[SipMessageTypes.REGISTER.toLowerCase()] = OnRegister;
    handlers[SipMessageTypes.CANCEL.toLowerCase()] = OnCancel;
    handlers[SipMessageTypes.REQUEST_TERMINATED.toLowerCase()] =
        onReqTerminated;
    handlers[SipMessageTypes.INVITE.toLowerCase()] = OnInvite;
    handlers[SipMessageTypes.TRYING.toLowerCase()] = OnTrying;
    handlers[SipMessageTypes.RINGING.toLowerCase()] = OnRinging;
    handlers[SipMessageTypes.BUSY.toLowerCase()] = OnBusy;
    handlers[SipMessageTypes.UNAVAIALBLE.toLowerCase()] = OnUnavailable;
    handlers[SipMessageTypes.BYE.toLowerCase()] = OnBye;
    handlers[SipMessageTypes.OK.toLowerCase()] = OnOk;
    handlers[SipMessageTypes.ACK.toLowerCase()] = OnAck;
    handlers[SipMessageTypes.UNAUTHORIZED.toLowerCase()] = OnAck;

    _sessions = {};

    // //print("listening for events from ION SFU");
    // webSocket!.listen((event) {
    //   //print("From SFU: $event");
    // });
  }

  void handle(SipMessage request, sockaddr_in protocol) {
    // //print(request.getType());
    ////print(request.src);
    ////print("Expires header value: ${request.Exp.Value}");

    // ignore: curly_braces_in_flow_control_structures
    if (request.Req.Method != null) {
      if (handlers[request.Req.Method!.toLowerCase()] != null ||
          request.Req.StatusCode != null) {
        ////print(request.src);
        //var lines = request.src!.split(SipMessageHeaders.HEADERS_DELIMETER);
        //var lines = request.src!.split(SipMessageHeaders.HEADERS_DELIMETER);
        // //print("Lines length: ${lines[8]}");
        //if (request.Req.Method!.toLowerCase() == "invite") //print(request.src);

        if (request.Req.Method!.toLowerCase() == "register") {
          handlers[request.Req.Method!.toLowerCase()]!(request);
        } else {
          proxy(request);
        }
      }
    }
  }

  void proxy(SipMessage msg) {
    void acknowledge() {}
    //socket.send(buffer, address, port)
    ////print(msg.Req.Method);
    ////print(msg.src);
    ////print("Branch: ${msg.Via[0].Branch}");

    ////print("Message from: ${msg.transport!.addr}");
    if (msg.CallId.Value != null) {
      if (dialogs[msg.CallId.Value!] == null) {
        print("Creating dialog for call ID: ${msg.CallId.Value}");
        dialogs[msg.CallId.Value!] = Dialog(msg.CallId.Value!);
        if (msg.Via[0].Branch != null && msg.Req.Method != null) {
          print(
              "Creating transaction in dialog for call ID: ${msg.CallId.Value}. Transaction ID: ${msg.Via[0].Branch}. Method: ${msg.Req.Method}");
          //transactions[msg.Via[0].Branch!] = msg.transport!;
          dialogs[msg.CallId.Value!]!.transactions[msg.Via[0].Branch!] =
              Transaction(msg);
          if (msg.Req.Method!.toLowerCase() == "invite") {
            dialogs[msg.CallId.Value!]!.caller = msg;
          }
        }
      } else {
        if (msg.Via[0].Branch != null) {
          //transactions[msg.Via[0].Branch!] = msg.transport!;
          if (dialogs[msg.CallId.Value!]!.transactions[msg.Via[0].Branch!] !=
              null) {
            print(
                "Updating transaction for existing dialog for call ID: ${msg.CallId.Value}. Transaction ID: ${msg.Via[0].Branch}. Status: ${msg.Req.Src}");
            if (msg.Req.StatusCode != null) {
              dialogs[msg.CallId.Value!]!
                  .transactions[msg.Via[0].Branch!]!
                  .receiveResponse(msg);
            }
          } else {
            print(
                "Creating transaction in dialog for call ID: ${msg.CallId.Value}. Transaction ID: ${msg.Via[0].Branch}");
            dialogs[msg.CallId.Value!]!.transactions[msg.Via[0].Branch!] =
                Transaction(msg);
          }
        }

        if (msg.Via[0].Branch != null && msg.Req.Method != null) {
          //transactions[msg.Via[0].Branch!] = msg.transport!;
          dialogs[msg.CallId.Value!]!.transactions[msg.Via[0].Branch!] =
              Transaction(msg);
        }
      }
    }

    bool bye = false;
    if (msg.Req.Method != null) {
      if (msg.Req.Method!.toLowerCase() == "bye") {
        bye = true;
      }
    }

    bool ok = false;
    if (msg.Req.StatusCode != null) {
      if (msg.Req.StatusCode!.toLowerCase() == "200") {
        ok = true;
        String? method = dialogs[msg.CallId.Value!]!
            .transactions[msg.Via[1].Branch]!
            .request
            .Req
            .Method;

        if (method != null && method.toLowerCase() == "bye") {
          print(msg.src);
        }
      }
    }

    // if (ack) {
    //   String caller = dialogs[msg.CallId.Value!]!.caller!.From.User!;
    //   if (msg.From.User != caller) {
    //     // socket.send(
    //     //     finalLines.join("\r\n").codeUnits,
    //     //     InternetAddress(dialogs[msg.CallId.Value!]!.caller!.Via[0].Host!),
    //     //     int.parse(dialogs[msg.CallId.Value!]!.caller!.Via[0].Port!));

    //     socket.send(
    //         finalLines.join("\r\n").codeUnits,
    //         InternetAddress(dialogs[msg.CallId.Value!]!
    //             .transactions[msg.Via[1].Branch]!
    //             .request
    //             .Via[0]
    //             .Host!),
    //         int.parse(dialogs[msg.CallId.Value!]!
    //             .transactions[msg.Via[1].Branch]!
    //             .request
    //             .Via[0]
    //             .Port!));

    //     return;
    //   }

    if (msg.transport!.addr != "10.43.0.55" || bye) {
      print("Message to: ${msg.transport!.addr}");
      var lines = msg.src!.split("\r\n");
      String via;
      List<String> finalLines = [];
      bool viaAdded = false;
      for (int x = 0; x < lines.length; x++) {
        if (lines[x].toLowerCase().contains("via") && !viaAdded) {
          // //print("Found via: ${lines[x]}");
          via = lines[x].replaceFirst("${msg.Via[0].Host}:${msg.Via[0].Port}",
              "$_serverIp:$_serverPort");
          ////print("Create via: $via");
          viaAdded = true;
          if (msg.Req.Method != null) {
            if (msg.Req.Method!.toLowerCase() == "invite" ||
                msg.Req.Method!.toLowerCase() == "bye") {
              finalLines.add("Record-Route: <sip:$_serverIp:$_serverPort;lr>");
            }
          }
          finalLines.add(via);
          finalLines.add(lines[x]);
        } else {
          finalLines.add(lines[x]);
        }
      }
      if (bye) {
        String caller = dialogs[msg.CallId.Value!]!.caller!.From.User!;
        if (msg.From.User != caller) {
          socket.send(
              finalLines.join("\r\n").codeUnits,
              InternetAddress(dialogs[msg.CallId.Value!]!.caller!.Via[0].Host!),
              int.parse(dialogs[msg.CallId.Value!]!.caller!.Via[0].Port!));

          return;
        }
        // != msg.From.User) {
        ////print(finalLines.join("\r\n"));

        // if (ack) {
        //   String caller = dialogs[msg.CallId.Value!]!.caller!.From.User!;
        //   if (msg.From.User != caller) {
        //     // socket.send(
        //     //     finalLines.join("\r\n").codeUnits,
        //     //     InternetAddress(dialogs[msg.CallId.Value!]!.caller!.Via[0].Host!),
        //     //     int.parse(dialogs[msg.CallId.Value!]!.caller!.Via[0].Port!));

        //     socket.send(
        //         finalLines.join("\r\n").codeUnits,
        //         InternetAddress(dialogs[msg.CallId.Value!]!
        //             .transactions[msg.Via[1].Branch]!
        //             .request
        //             .Via[0]
        //             .Host!),
        //         int.parse(dialogs[msg.CallId.Value!]!
        //             .transactions[msg.Via[1].Branch]!
        //             .request
        //             .Via[0]
        //             .Port!));

        //     return;
        //   }
        // != msg.From.User) {
        ////print(finalLines.join("\r\n"));
      }

      // SipMessage response = SipMessage();
      // response.Parse(finalLines.join("\r\n"));

      // if (msg.Req.Method!.toLowerCase() == 'ack') {
      //   socket.send(finalLines.join("\r\n").codeUnits,
      //       InternetAddress(msg.Via[0].Host!), int.parse(msg.Via[0].Port!));
      //} else {
      socket.send(finalLines.join("\r\n").codeUnits,
          InternetAddress("10.43.0.55"), 5080);
      // }
    } else {
      //print("Message from: ${msg.src}");

      var lines = msg.src!.split("\r\n");
      List<String> finalLines = [];
      bool viaAdded = false;
      for (int x = 0; x < lines.length; x++) {
        if (lines[x].toLowerCase().contains("via") &&
            !viaAdded &&
            msg.Via[0].Host == _serverIp) {
          viaAdded = true;
        } else {
          finalLines.add(lines[x]);
        }
      }
      ////print(finalLines.join("\r\n"));

      SipMessage response = SipMessage();
      response.Parse(finalLines.join("\r\n"));

      ////print("Branch: ${transactions[msg.Via[0].Branch!]!.addr}");
      socket.send(
          response.src!.codeUnits,
          InternetAddress(response.Via[0].Host!),
          int.parse(response.Via[0].Port!));
      ////print("Message to: ${msg.transport!.addr}");
    }
    //endHandle(destNumber, message)
  }

  bool OnRegister(SipMessage data) {
    ////print(data.src);
    ////print("Expires header value: ${data.Exp.Value}");
    bool isUnregisterReq = data.Exp.Value == null
        ? false
        : data.Exp.Value!.toLowerCase().contains("expires=0");

    if (!isUnregisterReq) {
      ////print("Number ${data.getFromNumber()}");
      SipClient newClient = SipClient(data.From.User!, data.transport!);
      registerClient(newClient);
    }
    if (data.Via[0].Branch != null) {
      //transactions[data.Via[0].Branch!] = data.transport!;
    }

    List<String> finalLines = [];
    //response.Parse(data.src!);
    var lines = data.src!.split('\r\n');
    lines[0] = SipMessageTypes.OK;
    ////print(data.To.Src);
    // response.setVia(data.getVia() + ";received=" + _serverIp);
    // response.setTo(data.getTo() + ";tag=" + IDGen());
    // response.setContact("Contact: <sip:" +
    //     data.getFromNumber() +
    //     "@" +
    //     _serverIp +
    //     ":" +
    //     _serverPort.toString() +
    //     ";transport=UDP>");

    //response.setHeader(SipMessageTypes.OK);
    bool viaAdded = false;
    finalLines.add(SipMessageTypes.OK);
    bool toHeaderAdded = false;
    String toTag;
    ////print("Request: ${data.src}");

    for (int x = 1; x < lines.length; x++) {
      if (lines[x].toLowerCase().contains("via") &&
          viaAdded &&
          data.Via[0].Host == _serverIp) {
        lines[x] =
            lines[x].replaceFirst(lines[x], "${lines[x]};received=$_serverIp");

        viaAdded = true;
      } else if (lines[x].toLowerCase().contains("to")) {
        lines[x] =
            lines[x].replaceFirst(lines[x], "${lines[x]};tag=${IDGen()}");
        finalLines.add(lines[x]);
        toHeaderAdded = false;
      } else if (lines[x].toLowerCase().contains("contact")) {
        lines[x] =
            "Contact: <sip:${data.From.User!}@$_serverIp:$_serverPort;transport=UDP>";
      } else {
        finalLines.add(lines[x]);
      }
    }

    ////print(finalLines.join("\r\n"));
    socket.send(finalLines.join("\r\n").codeUnits,
        InternetAddress(data.transport!.addr), data.transport!.port);

    if (isUnregisterReq) {
      SipClient newClient = SipClient(data.From.User!, data.transport!);
      unregisterClient(newClient);
    }

    return true;
  }

  SipClient? findClient(String number) {
    return _clients[number];
  }

  void endHandle(String destNumber, SipMessage message) {
    //SipClient destClient = findClient(destNumber);
    SipClient? destClient = _clients[destNumber];
    ////print(destClient.getNumber());
    // ignore: unnecessary_null_comparison
    if (destClient != null) {
      //print("${destClient.getAddress().addr}:${destClient.getAddress().port}");

      //_onHandled!(destClient.getAddress(), message);
      ////print(message.getType());
      socket.send(
          message.toString().codeUnits,
          InternetAddress(destClient.getAddress().addr),
          destClient.getAddress().port);
    } else {
      message.Req.Src = SipMessageTypes.NOT_FOUND;
      //sockaddr_in src = message.getSource();
      try {
        //_onHandled!(src, message);
        // socket.send(
        //     message.toString().codeUnits, InternetAddress(src.addr), src.port);
      } catch (error) {
        //print(error);
      }

      socket.send(
          message.toString().codeUnits,
          InternetAddress(destClient!.getAddress().addr),
          destClient.getAddress().port);
    }
  }

  void unregisterClient(SipClient client) {
    //print("unregister client:  ${client.getNumber()}");
    _clients.remove(client.getNumber());
  }

  bool registerClient(SipClient client) {
    if (_clients[client.getNumber()] == null) {
      ////print("New Client: ${client.getNumber()}");
      _clients[client.getNumber()] = client;

      ////print(client.getAddress().addr);
      return true;
    } else {
      _clients[client.getNumber()] = client;
      // //print(
      //     "${_clients[client.getNumber()]!.getAddress().addr}:${_clients[client.getNumber()]!.getAddress().port}");
      return true;
    }
    return false;
  }

  Session? getSession(String callID) {
    return _sessions![callID];
  }

  bool OnCancel(dynamic data) {
    setCallState(data.getCallID(), State.Cancel);
    endHandle(data.getToNumber(), data);
    return true;
  }

  bool onReqTerminated(dynamic data) {
    endHandle(data.getFromNumber(), data);
    return true;
  }

  bool OnInvite(dynamic data) {
    // Check if the caller is registered
    //SipClient caller = findClient(data.getFromNumber());
    SipClient? caller = _clients[data.getFromNumber()];

    if (caller == null) return true;

    // //print("Caller is: ${caller.getNumber()}");

    // if (caller.getNumber() == "") {
    //   ////print("Caller is: ${caller.getNumber()}");
    //   //print("Caller not registered");
    //   return true;
    // } else {
    //   //print("Caller is: ${caller.getNumber()}");
    // }

    ////print("Callee is: ${data.getToNumber()}");
    // Check if the called is registered
    //SipClient called = findClient(data.getToNumber());
    SipClient? called = _clients[data.getToNumber()];
    String strMsg = data.src!;
    // SipMessage trying = SipMessage(strMsg, data.getSource());
    SipMessage trying = SipMessage();
    trying.Parse(strMsg);

    trying.Req.Src = SipMessageTypes.TRYING;
    //trying.setHeader(SipMessageTypes.TRYING);
    //endHandle(trying.getFromNumber(), trying);

    // //print("Callee is: ");
    // //print("Callee is: ${called.getNumber()}");

    // //print(called.getNumber());
    if (called == null) {
      //print("Callee is: ${data.getToNumber()} is not registered");
      ////print(data.src!);

      int sdpDelimitor = strMsg.indexOf(SipMessageHeaders.HEADERS_DELIMETER +
          SipMessageHeaders.HEADERS_DELIMETER);
      ////print("Sdp delimiter: $sdpDelimitor");
      String sdp = strMsg.substring(sdpDelimitor + 4);
      ////print(sdp);

      // var jsonRpcReq = {
      //   "jsonrpc": "2.0",
      //   "method": "request",
      //   "params": {
      //     "sid": "defaultroom",
      //     "offer": {"type": "offer", "sdp": sdp}
      //   }
      // };
      var jsonRpcReq = {
        "jsonrpc": "2.0",
        "method": "join",
        "params": {
          "sid": "defaultroom",
          "offer": {"type": "offer", "sdp": sdp}
          //"offer": sdp
        },
        "id": 1
      };
      //print("Sending offer to sfu");
      webSocket!.add(jsonEncode(jsonRpcReq));
      // //print(jsonRpcReq);

      //ion_sfu.add(jsonEncode(jsonRpcReq));
      // Send "SIP/2.0 404 Not Found"
      data.setHeader(SipMessageTypes.NOT_FOUND);
      data.setContact(
          "Contact: <sip: ${caller.getNumber()}@ _serverIp + :$_serverPort;transport=UDP>");

      //print(data.getType());
      endHandle(data.getFromNumber(), data);

      // socket.send(data.src!.codeUnits,
      //     InternetAddress(caller.getAddress().addr), caller.getAddress().port);
      return true;
    }

    //SipSdpMessage message = SipSdpMessage(data.src!, data.getSource());
    SipMessage message = SipMessage();
    //if (!message.isValidMessage()) {
    // //print(
    //    "Couldn't get SDP from ${data.getFromNumber()}'s INVITE request."); //<< std::endl;
    //return true;
    //}
    //print("Creating session");
    // Session newSession =
    //     Session(data.getCallID(), caller, message.getRtpPort());
    // _sessions?[data.getCallID()] = newSession;
    //print("Session created");
    //SipMessage response = SipMessage(data.src!, caller.getAddress());
    SipMessage response = SipMessage();
    response.Parse(data.src!);
    //print("Setting call dialog");
    // response.setContact(
    //     "Contact: <sip:${caller.getNumber()}@$_serverIp:$_serverPort;transport=UDP>");

    response.Contact.Src =
        "Contact: <sip:${caller.getNumber()}@$_serverIp:$_serverPort;transport=UDP>";

    //print("Setting call dialog after response");
    endHandle(data.getToNumber(), response);

    return true;
  }

  bool OnTrying(dynamic data) {
    endHandle(data.getFromNumber(), data);
    return true;
  }

  bool OnRinging(dynamic data) {
    endHandle(data.getFromNumber(), data);
    return true;
  }

  bool OnBusy(dynamic data) {
    setCallState(data.getCallID(), State.Busy);
    endHandle(data.getFromNumber(), data);

    return true;
  }

  bool OnUnavailable(dynamic data) {
    setCallState(data.getCallID(), State.Unavailable);
    endHandle(data.getFromNumber(), data);

    return true;
  }

  bool OnBye(dynamic data) {
    setCallState(data.getCallID(), State.Bye);
    endHandle(data.getToNumber(), data);
    return true;
  }

  bool OnOk(dynamic data) {
    //print("Get ok");
    Session? session = getSession(data.getCallID());

    if (session != null) {
      //print("Getting state...");
      State? state = session.getState();

      if (state != null) {
        //print("Session state: $state");
      } else {
        //print("Sate is null");
      }

      //print("State gotten");
      if (state == State.Cancel) {
        endHandle(data.getFromNumber(), data);

        //print("exiting ok");
        return true;
      }
      //print("Test session");
      if (data.getCSeq().indexOf(SipMessageTypes.INVITE) != -1) {
        SipClient? client = findClient(data.getToNumber());
        if (client == null) {
          //print("No client");
          return true;
        }

        // SipMessage sdpMessage =
        //     SipSdpMessage(data.src!, data.getSource());

        SipMessage sdpMessage = SipMessage();
        sdpMessage.Parse(data.src!);

        // if (!sdpMessage.isValidMessage()) {
        //   //print("Coudn't get SDP from: ${client.getNumber()} 's OK message.");
        //   endCall(data.getCallID(), data.getFromNumber(), data.getToNumber(),
        //       "SDP parse error.");

        //   //print("exiting ok");
        //   return true;
        // }
        //print("Performing last operation");
        //session.setDest(client, sdpMessage.getRtpPort());
        session.setState(State.Connected);
        SipMessage response = SipMessage();
        response.Parse(
            data.toString()); //= SipMessage(data.src!, client.getAddress());
        // response.setContact("Contact: <sip:" +
        //     data.getToNumber() +
        //     "@" +
        //     _serverIp +
        //     ":" +
        //     _serverPort.toString() +
        //     ";transport=UDP>");

        response.ContType.Src = "Contact: <sip:" +
            data.getToNumber() +
            "@" +
            _serverIp +
            ":" +
            _serverPort.toString() +
            ";transport=UDP>";

        //print("exiting ok");
        endHandle(data.getFromNumber(), response);
        return true;
      }

      if (session.getState() == State.Bye) {
        endHandle(data.getFromNumber(), data);
        endCall(data.getCallID(), data.getToNumber(), data.getFromNumber(),
            State.Bye as String);
      }
    }
    //print("end of ok");
    return true;
  }

  void OnAck(dynamic data) {
    Session? session = getSession(data.getCallID());
    if (session != null) {
      return;
    }

    endHandle(data.getToNumber(), data);

    State? sessionState = session!.getState();
    String endReason;
    if (sessionState == State.Busy) {
      endReason = data.getToNumber() + " is busy.";
      endCall(data.getCallID(), data.getFromNumber(), data.getToNumber(),
          endReason);
      return;
    }

    if (sessionState == State.Unavailable) {
      endReason = data.getToNumber() + " is unavailable.";
      endCall(data.getCallID(), data.getFromNumber(), data.getToNumber(),
          endReason);
      return;
    }

    if (sessionState == State.Cancel) {
      endReason = data.getFromNumber() + " canceled the session.";
      endCall(data.getCallID(), data.getFromNumber(), data.getToNumber(),
          endReason);
      return;
    }
  }

  bool setCallState(String callID, State state) {
    Session? session = getSession(callID);
    if (session != null) {
      session.setState(state);
      return true;
    }

    return false;
  }

  void endCall(
      String callID, String srcNumber, String destNumber, String reason) {
    _sessions!.remove(callID);
    // _sessions.remove(callID)
    // {
    String message =
        "Session has been disconnected between $srcNumber and $destNumber";
    if (reason.isNotEmpty) {
      message += " because $reason";
    }
    // //print(message);
    //}
  }

  RawDatagramSocket socket;
  Map<String, Session>? _sessions;
  //WebSocket ion_sfu;
}
