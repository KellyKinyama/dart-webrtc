/*
 * Copyright (C) 2025 halifox
 *
 * This file is part of dart_stun.
 *
 * dart_stun is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation, either version 3 of the License,
 * or (at your option) any later version.
 *
 * dart_stun is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with dart_stun. If not, see <http://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'stun_message_rfc3489.dart';
import '../stun.dart';

typedef StunMessageListener = void Function(StunMessage stunMessage);

enum Transport {
  udp,
  tcp,
  tls,
}

abstract class StunClient {
  Transport transport;
  String serverHost;
  int serverPort;
  String localIp;
  int localPort;
  StunProtocol stunProtocol;

  StunClient(this.transport, this.serverHost, this.serverPort, this.localIp, this.localPort, this.stunProtocol);

  int connectTimeoutMilliseconds = 30 * 1000;
  int lookupTimeoutMilliseconds = 3 * 1000;
  int messageListenerTimeoutMilliseconds = 3 * 1000;

  static StunClient create({
    Transport transport = Transport.udp,
    String serverHost = "stun.hot-chilli.net",
    int serverPort = 3478,
    String localIp = "0.0.0.0",
    int localPort = 54320,
    StunProtocol stunProtocol = StunProtocol.RFC5780,
  }) {
    return switch (transport) {
      Transport.udp => StunClientUdp(transport, serverHost, serverPort, localIp, localPort, stunProtocol),
      Transport.tcp => StunClientTcp(transport, serverHost, serverPort, localIp, localPort, stunProtocol),
      Transport.tls => StunClientTls(transport, serverHost, serverPort, localIp, localPort, stunProtocol),
    };
  }

  StunMessage createBindingStunMessage() {
    return StunMessage.create(
      StunMessage.HEAD,
      StunMessage.METHOD_BINDING | StunMessage.CLASS_REQUEST,
      0,
      StunMessage.MAGIC_COOKIE,
      //todo: the transaction ID MUST be uniformly and randomly chosen from the interval 0 .. 2**96-1
      Random.secure().nextInt(2 << 32 - 1),
      [],
      stunProtocol,
    );
  }

  StunMessage createChangeStunMessage({bool flagChangeIp = true, bool flagChangePort = true}) {
    return StunMessage.create(
      StunMessage.HEAD,
      StunMessage.METHOD_BINDING | StunMessage.CLASS_REQUEST,
      8,
      StunMessage.MAGIC_COOKIE,
      //todo: the transaction ID MUST be uniformly and randomly chosen from the interval 0 .. 2**96-1
      Random.secure().nextInt(2 << 32 - 1),
      [
        ChangeAddress(flagChangeIp: flagChangeIp, flagChangePort: flagChangePort),
      ],
      stunProtocol,
    );
  }

  connect();

  disconnect();

  send(StunMessage stunMessage);

  Future<StunMessage> sendAndAwait(StunMessage stunMessage, {bool isAutoClose = false}) async {
    Completer<StunMessage> completer = Completer<StunMessage>();
    int transactionId = stunMessage.transactionId;
    StunMessageListener listener = (StunMessage stunMessage) {
      if (stunMessage.transactionId == transactionId) {
        completer.complete(stunMessage);
      }
    };
    addOnMessageListener(listener);
    await send(stunMessage);

    Timer? timer = Timer(Duration(milliseconds: messageListenerTimeoutMilliseconds), () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException("Response timed out after 3 seconds"));
      }
    });
    try {
      StunMessage message = await completer.future;
      return message;
    } catch (e, stackTrace) {
      rethrow;
    } finally {
      timer.cancel();
      removeOnMessageListener(listener);
      if (isAutoClose) {
        disconnect();
      }
    }
  }

  onData(Uint8List data) {
    StunMessage stunMessage = StunMessage.form(data, stunProtocol);
    onMessage(stunMessage);
  }

  onMessage(StunMessage stunMessage) {
    for (StunMessageListener listener in listeners) {
      listener.call(stunMessage);
    }
  }

  List<StunMessageListener> listeners = [];

  void addOnMessageListener(StunMessageListener l) {
    listeners.add(l);
  }

  void removeOnMessageListener(StunMessageListener l) {
    listeners.remove(l);
  }
}

class StunClientUdp extends StunClient {
  RawDatagramSocket? socket;

  List<InternetAddress> addresses = [];

  StunClientUdp(super.transport, super.serverHost, super.serverPort, super.localIp, super.localPort, super.stunProtocol);

  _onData(RawSocketEvent socketEvent) {
    if (socketEvent != RawSocketEvent.read) return;
    Datagram? incomingDatagram = socket?.receive();
    if (incomingDatagram == null) return;
    Uint8List data = incomingDatagram.data;
    onData(data);
  }

  connect() async {
    if (socket != null) return;
    socket = await RawDatagramSocket.bind(InternetAddress(localIp), localPort);
    socket?.listen(_onData);
    addresses = await InternetAddress.lookup(serverHost, type: InternetAddressType.IPv4).timeout(Duration(milliseconds: lookupTimeoutMilliseconds));
    if (addresses.isEmpty) throw Exception("Failed to resolve host: $serverHost");
  }

  disconnect() {
    socket?.close();
    socket = null;
  }

  send(StunMessage stunMessage) async {
    await connect();
    if (addresses.isEmpty) throw Exception("Failed to resolve host: $serverHost");
    InternetAddress address = addresses[0];
    socket?.send(stunMessage.toUInt8List(), address, serverPort);
  }
}

class StunClientTcp extends StunClient {
  Socket? socket;

  StunClientTcp(super.transport, super.serverHost, super.serverPort, super.localIp, super.localPort, super.stunProtocol);

  connect() async {
    socket = await Socket.connect(serverHost, serverPort, timeout: Duration(milliseconds: connectTimeoutMilliseconds));
    socket?.listen(onData);
  }

  disconnect() {
    socket?.destroy();
    socket = null;
  }

  send(StunMessage stunMessage) async {
    await connect();
    socket?.add(stunMessage.toUInt8List());
  }
}

class StunClientTls extends StunClient {
  Socket? socket;

  StunClientTls(super.transport, super.serverHost, super.serverPort, super.localIp, super.localPort, super.stunProtocol);

  connect() async {
    socket = await SecureSocket.connect(serverHost, serverPort, timeout: Duration(milliseconds: connectTimeoutMilliseconds));
    socket?.listen(onData);
  }

  disconnect() {
    socket?.destroy();
    socket = null;
  }

  send(StunMessage stunMessage) async {
    await connect();
    socket?.add(stunMessage.toUInt8List());
  }
}
