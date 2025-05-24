import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// import '../src/sdp/sdp_transform.dart';
// import 'fingerprint.dart';
import '../src/sdp8/sdp_offer2.dart';

Future<void> main() async {
  // Start WebSocket Server on localhost at port 8080
  final server = await HttpServer.bind('localhost', 8081);
  print('WebSocket Proxy Server running on ws://localhost:8081');

  await for (var request in server) {
    if (request.uri.path == '/ws') {
      handleWebSocketProxy(request);
    } else {
      request.response.statusCode = HttpStatus.notFound;
      request.response.close();
    }
  }
}

void handleWebSocketProxy(HttpRequest request) async {
  final webSocket = await WebSocketTransformer.upgrade(request);
  print('Client connected');

  webSocket.listen(
    (message) {
      print("Received: $message");
      var data = jsonDecode(message);
      print("Received SDP Offer");
      if (data["type"] == "write") {
        print("Received SDP map: $data");
      }
    },
    onDone: () {
      print("Client disconnected");
      webSocket.close();
    },
    onError: (error) {
      print("WebSocket Error: $error");
    },
  );

  final offer = generateSdpOfferMap(
    sessionId: '1234567890',
    ufrag: 'abcd',
    pwd: 'efghijklmnop',
    fingerprint:
        '12:34:56:78:90:AB:CD:EF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77',
    candidates: [
      Candidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 2113937151,
        ip: '192.168.1.2',
        port: 54555,
        type: 'host',
      ),
    ],
  );

  webSocket.add(jsonEncode({"type": "SdpOffer", "offer": offer}));

  // print("Sdp offer: $offer");
}
