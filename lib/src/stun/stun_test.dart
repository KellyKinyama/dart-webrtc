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

import 'stun.dart';
import 'package:test/test.dart';

Future<void> main() async {
  // test("udp", () async {
  StunClient stunClient = StunClient.create(
    transport: Transport.udp,
    serverHost: "stun.l.google.com",
    serverPort: 19302,
    localIp: "10.100.53.194",
    localPort: 4444,
    stunProtocol: StunProtocol.RFC5780,
  );
  StunMessage stunMessage = stunClient.createBindingStunMessage();
  StunMessage data = await stunClient.sendAndAwait(stunMessage);
  print(data);
  // });

  // test("tcp", () async {
  //   StunClient stunClient = StunClient.create(
  //     transport: Transport.tcp,
  //     serverHost: "stun.hot-chilli.net",
  //     serverPort: 3478,
  //     localIp: "0.0.0.0",
  //     localPort: 54320,
  //     stunProtocol: StunProtocol.RFC5780,
  //   );
  //   StunMessage stunMessage = stunClient.createBindingStunMessage();
  //   StunMessage data = await stunClient.sendAndAwait(stunMessage);
  //   print(data);
  // });

  // test("tls", () async {
  //   StunClient stunClient = StunClient.create(
  //     transport: Transport.tls,
  //     serverHost: "stun.hot-chilli.net",
  //     serverPort: 3478,
  //     localIp: "0.0.0.0",
  //     localPort: 54320,
  //     stunProtocol: StunProtocol.RFC5780,
  //   );
  //   StunMessage stunMessage = stunClient.createBindingStunMessage();
  //   StunMessage data = await stunClient.sendAndAwait(stunMessage);
  //   print(data);
  // });

  test("natChecker", () async {
    var natChecker = NatChecker();
    var result = await natChecker.check();
    print(result);
  });
}
