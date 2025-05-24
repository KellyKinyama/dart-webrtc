//import 'package:dart_pbx/sip/transport.dart';
import 'dart:math';

//import 'package:dart_pbx/services/location_server.dart';
//import 'package:dart_pbx/services/models/gateway.dart';
//import 'package:dart_pbx/services/models/location.dart';
import 'package:dartls/signal/sdp2.dart';

import '../../../signal/sdp3.dart';
import '../globals.dart';
import '../session.dart';
import '../sip_client.dart';
import '../transports/transport.dart';
import '../sip_parser/sip.dart';
import '../sip_parser/sip_message_types.dart';

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

class RequestsHandler {
  Map<String, Function(SipMsg, {SipTransport? transport})> handlers = {};

  RequestsHandler() {
    handlers[SipMessageTypes.REGISTER.toLowerCase()] = onRegister;
    handlers[SipMessageTypes.CANCEL.toLowerCase()] = onCancel;
    handlers[SipMessageTypes.REQUEST_TERMINATED.toLowerCase()] =
        onReqTerminated;
    handlers[SipMessageTypes.INVITE.toLowerCase()] = onInvite;
    handlers[SipMessageTypes.TRYING.toLowerCase()] = onTrying;
    handlers[SipMessageTypes.RINGING.toLowerCase()] = onRinging;
    handlers[SipMessageTypes.BUSY.toLowerCase()] = onBusy;
    handlers[SipMessageTypes.UNAVAIALBLE.toLowerCase()] = onUnavailable;
    handlers[SipMessageTypes.BYE.toLowerCase()] = onBye;
    handlers[SipMessageTypes.OK.toLowerCase()] = onOk;
    handlers[SipMessageTypes.ACK.toLowerCase()] = onAck;
    handlers[SipMessageTypes.UNAUTHORIZED.toLowerCase()] = onUnauthorized;
  }

  void handle(String request, SipTransport transport) {
    SipMsg sipMsg = SipMsg();
    sipMsg.Parse(request);
    //print(request);
    if (sipMsg.Req.Method != null && sipMsg.Req.Method!.isNotEmpty) {
      print("request: ${sipMsg.Req.Method}");
      if (handlers[sipMsg.Req.Method!.toLowerCase()] != null) {
        //print(transport.send);
        // if (sipMsg.Req.Method!.toLowerCase() == "bye") {
        //   print("bye: parsed{${sipMsg.src}}, data: $request");
        // }
        handlers[sipMsg.Req.Method!.toLowerCase()]!(sipMsg,
            transport: transport);
      }
    } else if (sipMsg.Req.StatusCode != null) {
      print("Response: ${sipMsg.Req.StatusCode} ${sipMsg.Req.StatusDesc}");
      if (int.parse(sipMsg.Req.StatusCode!) == 200 &&
          sipMsg.Req.StatusDesc!.toLowerCase() == "ok") {
        onOk(sipMsg, transport: transport);
      }
      if (int.parse(sipMsg.Req.StatusCode!) == 100 &&
          sipMsg.Req.StatusDesc!.toLowerCase() == "trying") {
        onTrying(sipMsg, transport: transport);
      }
      if (int.parse(sipMsg.Req.StatusCode!) == 180 &&
          sipMsg.Req.StatusDesc!.toLowerCase() == "ringing") {
        onRinging(sipMsg, transport: transport);
      }
      if (int.parse(sipMsg.Req.StatusCode!) == 486
          //&& sipMsg.Req.StatusDesc!.toLowerCase() == "ringing"
          ) {
        onBusy(sipMsg, transport: transport);
      }
      if (int.parse(sipMsg.Req.StatusCode!) == 480
          //&& sipMsg.Req.StatusDesc!.toLowerCase() == "ringing"
          ) {
        onUnavailable(sipMsg, transport: transport);
      }
    } else {
      print("Uknown SIP message: $request");
    }
  }

  onRegister(SipMsg data, {SipTransport? transport}) {
    print("Registering user");

    List<String> finalLines = [];
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
    bool contactAdded = false;
    finalLines.add(SipMessageTypes.OK);

    bool toHeaderAdded = false;
    String toTag;
    ////print("Request: ${data.src}");
    String? contact_id;

    for (int x = 1; x < lines.length; x++) {
      if (lines[x].toLowerCase().contains("via") // &&
          //viaAdded &&
          //data.Via[0].Host == transport!.serverSocket.addr
          ) {
        if (lines[x].contains("rport")) {
          lines[x] =
              lines[x].replaceFirst("rport", "rport=${transport!.socket.port}");
        }
        lines[x] = lines[x].replaceFirst(
            lines[x], "${lines[x]};received=${transport!.serverSocket.addr}");
        // print("Checking via");
        //print("Via header: {${lines[x]}}");
        finalLines.add(lines[x]);

        //viaAdded = true;
      } else if (lines[x].toLowerCase().contains("to")) {
        lines[x] =
            lines[x].replaceFirst(lines[x], "${lines[x]};tag=${IDGen()}");
        finalLines.add(lines[x]);
        toHeaderAdded = false;
        //print(lines[x]);
      } else if (lines[x].toLowerCase().contains("contact") &&
          !(transport?.serverSocket.transport.toLowerCase() != 'ws' ||
              transport?.serverSocket.transport.toLowerCase() != 'wss')) {
        // print(transport?.serverSocket.transport.toUpperCase());
        lines[x] =
            "Contact: <sip:${data.From.User!}@${transport?.serverSocket.addr}:${transport?.serverSocket.port};transport=${transport?.serverSocket.transport.toUpperCase()}>";
        contact_id = lines[x];
        contactAdded == true;
        finalLines.add(lines[x]);
        //print(lines[x]);
      } else {
        //print("Line: ${lines[x]}");
        finalLines.add(lines[x]);
      }
    }
    // if (!contactAdded) {
    //   finalLines.add(
    //       "Contact: <sip:${data.From.User!}@${transport?.serverSocket.addr}:${transport?.serverSocket.port};transport=${transport?.serverSocket.transport.toUpperCase()}>");
    // }
    finalLines.add("\r\n");
    var response = finalLines.join("\r\n");
    // locations[contact_id!] = Location(
    //     contact_id,
    //     data.From.User!,
    //     data.From.Host,
    //     contact_id,
    //     sockaddr_in(transport!.socket.addr, transport.socket.port,
    //         transport.socket.transport));
    //print(transport!.send);
    clients[data.From.User!] = SipClient(data.From.User!, transport!);
    //locations[contact_id]?.send = transport.send;

    if (transport.serverSocket.transport == "udp") {
      transport.send(response,
          destIp: transport.socket.addr, destPort: transport.socket.port);
    } else {
      transport.send(response);
    }
  }

  onCancel(SipMsg data, {SipTransport? transport}) {
    //   setCallState(data->getCallID(), Session::State::Cancel);
    // endHandle(data->getToNumber(), data);

    Session? session = sessions[data.CallId.Value];
    session?.state = State.Cancel;
    SipClient? client = clients[data.To.User!];
    //client!.transport.send(data.src!);

    if (client!.transport.serverSocket.transport == "udp") {
      client.transport.send(data.src!,
          destIp: client.transport.socket.addr,
          destPort: client.transport.socket.port);
    } else {
      //client.transport.send(response);
      client.transport.send(data.src!);
    }
  }

  onReqTerminated(SipMsg data, {SipTransport? transport}) {}
  onInvite(SipMsg data, {SipTransport? transport}) {
    print("Inviting user: ${data.To.User}");

    // Check if the caller is registered
    SipClient? caller = clients[data.From.User!];
    if (caller == null) {
      if (gateways[data.From.Host] != null) {
        print("Call from gateway");
        clients[data.From.User!] = SipClient(data.From.User!, transport!);
        caller = clients[data.From.User!];
      } else
        return;
    }

    // Check if the called is registered
    SipClient? called = clients[data.To.User!];
    if (called == null) {
      // Send "SIP/2.0 404 Not Found"
      List<String> finalLines = [];
      var lines = data.src!.split('\r\n');
      lines[0] = SipMessageTypes.NOT_FOUND;
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
      finalLines.add(lines[0]);

      bool toHeaderAdded = false;
      String toTag;
      ////print("Request: ${data.src}");
      String? contact_id;

      for (int x = 1; x < lines.length; x++) {
        if (lines[x].toLowerCase().contains("contact")) {
          lines[x] =
              "Contact: <sip:${data.From.User!}@${transport?.serverSocket.addr}:${transport?.serverSocket.port};transport=${transport?.serverSocket.transport.toUpperCase()}>";
          contact_id = lines[x];
          //print(lines[x]);
        } else {
          //print("Line: ${lines[x]}");
          finalLines.add(lines[x]);
        }
      }
      finalLines.add("\r\n");
      var response = finalLines.join("\r\n");

      //transport!.send(response);

      if (transport!.serverSocket.transport == "udp") {
        transport.send(data.src!,
            destIp: transport.socket.addr, destPort: transport.socket.port);
      } else {
        //client.transport.send(response);
        transport.send(data.src!);
      }
      print("invited user: ${data.To.User} not found");
      return;
    }

    // auto message = dynamic_cast<SipSdpMessage*>(data.get());
    // if (!message)
    // {
    // 	std::cerr << "Couldn't get SDP from " << data->getFromNumber() << "'s INVITE request." << std::endl;
    // 	return;
    // }

    print(
        "invited user: ${data.To.User} found on transport: ${called.transport.serverSocket.transport}");

    Session newSession = Session(
        data.CallId.Value!, caller!, int.parse(data.Sdp.MediaDesc.Port!));
    // _sessions.emplace(data->getCallID(), newSession);
    sessions[data.CallId.Value!] = newSession;

    // auto response = data;
    // response->setContact("Contact: <sip:" + caller.value()->getNumber() + "@" + _serverIp + ":" + std::to_string(_serverPort) + ";transport=UDP>");
    // endHandle(data->getToNumber(), response);

    // Send "SIP/2.0 404 Not Found"
    List<String> finalLines = [];
    var lines = data.src!.split('\r\n');
    //lines[0] = SipMessageTypes.NOT_FOUND;
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
    finalLines.add(lines[0]);

    bool toHeaderAdded = false;
    String toTag;
    ////print("Request: ${data.src}");
    String? contact_id;

    for (int x = 1; x < lines.length; x++) {
      if (lines[x].toLowerCase().contains("contact")) {
        lines[x] =
            "Contact: <sip:${data.From.User!}@${transport?.serverSocket.addr}:${transport?.serverSocket.port};transport=${transport?.serverSocket.transport.toUpperCase()}>";
        contact_id = lines[x];
        //print(lines[x]);
      } else {
        //print("Line: ${lines[x]}");
        finalLines.add(lines[x]);
      }
    }
    finalLines.add("\r\n");
    var response = finalLines.join("\r\n");
    print(
        "Sending invite response number:${called.number}, sip:${called.transport.socket.transport}:${called.transport.socket.addr}:${called.transport.socket.port}");
    // locations[contact_id!] = Location(
    //     contact_id,
    //     data.From.User!,
    //     data.From.Host,
    //     contact_id,
    //     sockaddr_in(transport!.socket.addr, transport.socket.port,
    //         transport.socket.transport));
    //print(transport!.send);
    // locations[contact_id]?.send = transport.send;
    // called.transport.send(response);
    if (called.transport.serverSocket.transport == "udp") {
      //print("invite: $response");
      called.transport.send(data.src!,
          destIp: called.transport.socket.addr,
          destPort: called.transport.socket.port);
    } else {
      called.transport.send(data.src!);
    }
  }

  onTrying(SipMsg data, {SipTransport? transport}) {
    SipClient? client = clients[data.From.User!];
    // client!.transport.send(data.src!);

    if (client!.transport.serverSocket.transport == "udp") {
      client.transport.send(data.src!,
          destIp: client.transport.socket.addr,
          destPort: client.transport.socket.port);
    } else {
      //client.transport.send(response);
      client.transport.send(data.src!);
    }
  }

  onRinging(SipMsg data, {SipTransport? transport}) {
    SipClient? client = clients[data.From.User!];
    //client!.transport.send(data.src!);
    if (client!.transport.serverSocket.transport == "udp") {
      client.transport.send(data.src!,
          destIp: client.transport.socket.addr,
          destPort: client.transport.socket.port);
    } else {
      //client.transport.send(response);
      client.transport.send(data.src!);
    }
  }

  onBusy(SipMsg data, {SipTransport? transport}) {
    //   setCallState(data->getCallID(), Session::State::Busy);
    // endHandle(data->getFromNumber(), data);

    Session? session = sessions[data.CallId.Value];
    session?.state = State.Busy;
    SipClient? client = clients[data.From.User!];
    //client!.transport.send(data.src!);

    if (client!.transport.serverSocket.transport == "udp") {
      client.transport.send(data.src!,
          destIp: client.transport.socket.addr,
          destPort: client.transport.socket.port);
    } else {
      //client.transport.send(response);
      client.transport.send(data.src!);
    }
  }

  onUnavailable(SipMsg data, {SipTransport? transport}) {
    //   setCallState(data->getCallID(), Session::State::Unavailable);
    // endHandle(data->getFromNumber(), data);
    Session? session = sessions[data.CallId.Value];
    session?.state = State.Unavailable;
    SipClient? client = clients[data.From.User!];
    //client!.transport.send(data.src!);

    if (client!.transport.serverSocket.transport == "udp") {
      client.transport.send(data.src!,
          destIp: client.transport.socket.addr,
          destPort: client.transport.socket.port);
    } else {
      //client.transport.send(response);
      client.transport.send(data.src!);
    }
  }

  onBye(SipMsg data, {SipTransport? transport}) {
    //   setCallState(data->getCallID(), Session::State::Bye);
    // endHandle(data->getToNumber(), data);
    Session? session = sessions[data.CallId.Value];
    session?.state = State.Bye;
    SipClient? client = clients[data.To.User!];
    //client!.transport.send(data.src!);

    if (client!.transport.serverSocket.transport == "udp") {
      client.transport.send(data.src!,
          destIp: client.transport.socket.addr,
          destPort: client.transport.socket.port);
    } else {
      //client.transport.send(response);
      client.transport.send(data.src!);
    }
  }

  onOk(SipMsg data, {SipTransport? transport}) {
    print("handling ok");

    var response = data.src!.split("\r\n\r\n");
    print("Response: ${response}");
    final sdpMsg = generateSdpOffer();
    data.src = "${response[0]}\r\n\r\n$sdpMsg";
    Session? session = sessions[data.CallId.Value];
    if (session != null) {
      if (session.state == State.Cancel) {
        SipClient? client = clients[data.From.User!];
        //client!.transport.send(data.src!);

        if (client!.transport.serverSocket.transport == "udp") {
          client.transport.send(data.src!,
              destIp: client.transport.socket.addr,
              destPort: client.transport.socket.port);
        } else {
          //client.transport.send(response);
          client.transport.send(data.src!);
        }
        return;
      }

      if (data.Cseq.Src!
          .toLowerCase()
          .contains(SipMessageTypes.INVITE.toLowerCase())) {
        SipClient? client = clients[data.To.User!];
        if (client == null) {
          return;
        }

        // auto sdpMessage = dynamic_cast<SipSdpMessage*>(data.get());
        // if (!sdpMessage)
        // {
        // 	std::cerr << "Coudn't get SDP from: " << client.value()->getNumber() << "'s OK message.";
        // 	endCall(data->getCallID(), data->getFromNumber(), data->getToNumber(), "SDP parse error.");
        // 	return;
        // }
        //session->get()->setDest(client.value(), sdpMessage->getRtpPort());
        session.dest = client;
        session.state = State.Connected;
        String response = data.src!;
        // Send "SIP/2.0 404 Not Found"
        List<String> finalLines = [];
        var lines = data.src!.split('\r\n');
        //lines[0] = SipMessageTypes.NOT_FOUND;
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
        finalLines.add(lines[0]);

        bool toHeaderAdded = false;
        String toTag;
        ////print("Request: ${data.src}");
        String? contact_id;

        for (int x = 1; x < lines.length; x++) {
          if (lines[x].toLowerCase().contains("contact")) {
            lines[x] =
                "Contact: <sip:${data.From.User!}@${transport?.serverSocket.addr}:${transport?.serverSocket.port};transport=${transport?.serverSocket.transport.toUpperCase()}>";
            contact_id = lines[x];
            //print(lines[x]);
          } else {
            //print("Line: ${lines[x]}");
            finalLines.add(lines[x]);
          }
        }
        finalLines.add("\r\n");
        var resp = finalLines.join("\r\n");
        client = clients[data.From.User!];
        //client!.transport.send(data.src!);

        if (client!.transport.serverSocket.transport == "udp") {
          client.transport.send(data.src!,
              destIp: client.transport.socket.addr,
              destPort: client.transport.socket.port);
        } else {
          //client.transport.send(response);
          client.transport.send(data.src!);
        }
        return;
      }

      if (session.state == State.Bye) {
        SipClient? client = clients[data.From.User!];
        //client!.transport.send(data.src!);

        if (client!.transport.serverSocket.transport == "udp") {
          client.transport.send(data.src!,
              destIp: client.transport.socket.addr,
              destPort: client.transport.socket.port);
        } else {
          //client.transport.send(response);
          client.transport.send(data.src!);
        }
        sessions.remove(data.CallId.Value);
      }
    }
  }

  onAck(SipMsg data, {SipTransport? transport}) {
    Session? session = sessions[data.CallId.Value];
    if (session == null) {
      return;
    }

    SipClient? client = clients[data.To.User!];
    //client!.transport.send(data.src!);

    if (client!.transport.serverSocket.transport == "udp") {
      client.transport.send(data.src!,
          destIp: client.transport.socket.addr,
          destPort: client.transport.socket.port);
    } else {
      //client.transport.send(response);
      client.transport.send(data.src!);
    }

    State sessionState = session.state!;
    String endReason;
    if (sessionState == State.Busy) {
      endReason = "${data.To.User} is busy.";
      sessions.remove(data.CallId.Value);
      return;
    }

    if (sessionState == State.Unavailable) {
      endReason = "${data.To.User} is unavailable.";
      sessions.remove(data.CallId.Value);
      return;
    }

    if (sessionState == State.Cancel) {
      endReason = "${data.From.User} canceled the session.";
      sessions.remove(data.CallId.Value);
      return;
    }
  }

  onUnauthorized(SipMsg data, {SipTransport? transport}) {}

  Map<String, SipClient> clients = {};
  Map<String, Session> sessions = {};
}
