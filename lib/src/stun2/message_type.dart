import 'message_class.dart';
import 'message_method.dart';

class MessageType {
  MessageMethod messageMethod;
  MessageClass messageClass;

  MessageType({required this.messageMethod, required this.messageClass});

  @override
  String toString() {
    // TODO: implement toString
    return "MessageType{ messageMethod: $messageMethod, messageClass: $messageClass}";
  }

  int encode() {
    // int (mt *MessageType) Encode() uint16 {
    int m = messageMethod.value;
    int a = m & methodABits; // A = M * 0b0000000000001111 (right 4 bits)
    int b = m & methodBBits; // B = M * 0b0000000001110000 (3 bits after A)
    int d = m & methodDBits; // D = M * 0b0000111110000000 (5 bits after B)

    // Shifting to add "holes" for C0 (at 4 bit) and C1 (8 bit).
    m = a + (b << methodBShift) + (d << methodDShift);

    // C0 is zero bit of C, C1 is first bit.
    // C0 = C * 0b01, C1 = (C * 0b10) >> 1
    // Ct = C0 << 4 + C1 << 8.
    // Optimizations: "((C * 0b10) >> 1) << 8" as "(C * 0b10) << 7"
    // We need C0 shifted by 4, and C1 by 8 to fit "11" and "7" positions
    // (see figure 3).
    int c = messageClass.value;
    int c0 = (c & c0Bit) << classC0Shift;
    int c1 = (c & c1Bit) << classC1Shift;
    int className = c0 + c1;

    return m + className;
  }
}

// func (mt MessageType) String() string {
// 	return fmt.Sprintf("%s %s", mt.MessageMethod, mt.MessageClass)
// }

const methodABits = 0xf; // 0b0000000000001111
const methodBBits = 0x70; // 0b0000000001110000
const methodDBits = 0xf80; // 0b0000111110000000

const methodBShift = 1;
const methodDShift = 2;

const firstBit = 0x1;
const secondBit = 0x2;

const c0Bit = firstBit;
const c1Bit = secondBit;

const classC0Shift = 4;
const classC1Shift = 7;

MessageType decodeMessageType(int mt) {
  // Decoding class.
  // We are taking first bit from v >> 4 and second from v >> 7.
  int c0 = (mt >> classC0Shift) & c0Bit;
  int c1 = (mt >> classC1Shift) & c1Bit;
  int className = c0 + c1;

  // Decoding method.
  int a = mt & methodABits; // A(M0-M3)
  int b = (mt >> methodBShift) & methodBBits; // B(M4-M6)
  int d = (mt >> methodDShift) & methodDBits; // D(M7-M11)
  int m = a + b + d;

  return MessageType(
    messageClass: MessageClass.fromInt(className),
    messageMethod: MessageMethod.fromInt(m),
  );
}

final MessageTypeBindingRequest = MessageType(
  messageMethod: MessageMethod.StunBinding,
  messageClass: MessageClass.Request,
);
final MessageTypeBindingSuccessResponse = MessageType(
  messageMethod: MessageMethod.StunBinding,
  messageClass: MessageClass.SuccessResponse,
);
final MessageTypeBindingErrorResponse = MessageType(
  messageMethod: MessageMethod.StunBinding,
  messageClass: MessageClass.ErrorResponse,
);
final MessageTypeBindingIndication = MessageType(
  messageMethod: MessageMethod.StunBinding,
  messageClass: MessageClass.Indication,
);
