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

class Call {
  Call(this.callId);
  String callId;
  String? caller;
  String? callee;

  State? state;
}

Map<String, Call> calls = {};
