enum MessageMethod {
  StunBinding(0x0001),
  TurnAllocate(0x0003),
  TurnRefresh(0x0004),
  TurnSend(0x0006),
  TurnData(0x0007),
  TurnCreatePermission(0x0008),
  TurnChannelBind(0x0009),
  TurnConnect(0x000a),
  TurnConnectionBind(0x000b),
  TurnConnectionAttempt(0x000c);

  const MessageMethod(this.value);
  final int value;

  factory MessageMethod.fromInt(int key) {
    return values.firstWhere((element) => element.value == key);
  }
}

class messageMethodDef {
  String name;
  messageMethodDef(this.name);
}


// func (mm MessageMethod) String() string {
// 	messageMethodDef, ok := messageMethodMap[mm]
// 	if !ok {
// 		// Just return hex representation of unknown method.
// 		return fmt.Sprintf("0x%x", uint16(mm))
// 	}
// 	return messageMethodDef.Name
// }
