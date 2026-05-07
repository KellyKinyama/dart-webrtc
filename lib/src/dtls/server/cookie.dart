// Cookie generation for the DTLS HelloVerifyRequest exchange.

import 'dart:math';
import 'dart:typed_data';

const int _cookieLength = 20;

final _random = Random.secure();

/// Generates a random DTLS cookie.
Uint8List generateDtlsCookie() {
  final cookie = Uint8List(_cookieLength);
  for (var i = 0; i < cookie.length; i++) {
    cookie[i] = _random.nextInt(256);
  }
  return cookie;
}
