enum MessageClass {
  Request(0x00),
  Indication(0x01),
  SuccessResponse(0x02),
  ErrorResponse(0x03);

  const MessageClass(this.value);
  final int value;

  factory MessageClass.fromInt(int key) {
    return values.firstWhere((element) => element.value == key);
  }
}

class MessageClassDef {
  String name;
  MessageClassDef(this.name);
}

// final Map<MessageClass, messageClassDef> messageClassMap = {
//   MessageClassRequest: messageClassDef("request"),
//   MessageClassIndication: messageClassDef("indication"),
//   MessageClassSuccessResponse: messageClassDef("success response"),
//   MessageClassErrorResponse: messageClassDef("error response"),
// };

// func (mc MessageClass) String() string {
// 	messageClassDef, ok := messageClassMap[mc]
// 	if !ok {
// 		// Just return hex representation of unknown class.
// 		return fmt.Sprintf("0x%x", uint16(mc))
// 	}
// 	return messageClassDef.Name
// }
