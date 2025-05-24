import 'sip_parser/sip.dart';
import 'transports/transport.dart';

class SipClient {
  SipClient(this.number, this.transport);

  // bool operator ==(SipClient other) {
  //   if (_number == other.getNumber()) {
  //     return true;
  //   }

  //   return false;
  // }

  String getNumber() {
    return number;
  }

  SipTransport getAddress() {
    return transport;
  }

  String number;
  SipTransport transport;
}
