enum Flight {
  Flight0(0),
  Flight2(2),
  Flight4(4),
  Flight6(6);

  const Flight(this.value);
  final int value;
}

enum TLSState {
  TLSStateNew(1),
  TLSStateConnecting(2),
  TLSStateConnected(3),
  TLSStateFailed(4);

  const TLSState(this.value);
  final int value;
}
