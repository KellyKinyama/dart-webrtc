import 'dart:io';

// import '../stun2/message.dart'
// import 'package:dartls/src/stun2/message_type.dart';
import 'package:dartls/src/stun2/message_class.dart';

import '../stun2/attributes.dart';
import '../stun2/message_method.dart';
import '../stun2/message_type.dart';

import '../stun2/message_manual.dart';

Message createBindingResponse(
    Message request, RawDatagramSocket addr, String userName) {
  final responseMessage = Message.newMessage(
      MessageType(
          messageClass: MessageClass.Request,
          messageMethod: MessageMethod.StunBinding),
      request.transactionID);

  responseMessage.setAttribute(
      createAttrXorMappedAddress(responseMessage.transactionID, addr));
  responseMessage.setAttribute(createAttrUserName(userName));

  return responseMessage;
}
