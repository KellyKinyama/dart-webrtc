import "sip_client.dart";

enum State {
  // ignore: constant_identifier_names
  Invited,
  // ignore: constant_identifier_names
  Busy,
  // ignore: constant_identifier_names
  Unavailable,
  // ignore: constant_identifier_names
  Cancel,
  // ignore: constant_identifier_names
  Bye,
  // ignore: constant_identifier_names
  Connected,
}

class Session {
  Session(this.callID, this.src, this.srcRtpPort);

  void setState(State state) {
    if (state == state) {
      return;
    }
    state = state;
    if (state == State.Connected) {
      print(
          "Session Created between  ${src.getNumber()} and  _dest->getNumber()");
    }
  }

  void setDest(SipClient dest, int destRtpPort) {
    dest = dest;
    destRtpPort = destRtpPort;
  }

  String getCallID() {
    return callID;
  }

  SipClient getSrc() {
    return src;
  }

  SipClient getDest() {
    return dest!;
  }

  State? getState() {
    return state;
  }

  String callID;
  SipClient src;
  SipClient? dest;
  State? state;

  int srcRtpPort;
  int? destRtpPort;
}
