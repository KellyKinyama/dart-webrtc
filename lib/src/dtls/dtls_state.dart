enum DTLSState {
  DTLSStateNew(1),
  DTLSStateConnecting(2),
  DTLSStateConnected(3),
  DTLSStateFailed(4);

  const DTLSState(this.value);
  final int value;
}
