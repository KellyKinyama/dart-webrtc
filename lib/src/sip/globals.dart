import 'dart:io';
import 'handlers/requests_handlers.dart';
import 'services/models/gateway.dart' as gw;
import 'sip_parser/sip.dart';

WebSocket? webSocket;
typedef SipMessage = SipMsg;
Map<String, gw.Gateway> gateways = {};

RequestsHandler requestsHander = RequestsHandler();
