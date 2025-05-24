import '../globals.dart';

enum TransactionState {
  // Transaction states.
  TRYING,
  PROCEEDING,
  CALLING,
  ACCEPTED,
  COMPLETED,
  TERMINATED,
  CONFIRMED
}

// abstract class TransactionBase {
//   TransactionBase(this.request);
//   String? id;
//   //PitelUA? ua;
//   //Transport? transport;
//   TransactionState? state;
//   SipMessage? last_response;
//   SipMessage request;
//   void onTransportError();

//   void send();

//   void receiveResponse(int status_code, SipMessage response,
//       [void Function()? onSuccess, void Function()? onFailure]) {
//     // default NO_OP implementation
//   }
// }
class Transaction {
  Transaction(this.request);
  String? id;
  TransactionState? state;
  SipMessage request;
  SipMessage? last_response;

  void receiveResponse(SipMessage response,
      [void Function()? onSuccess, void Function()? onFailure]) {
    // default NO_OP implementation
    last_response = response;
    if (response.Req.StatusCode == null) {
      throw "Response Status Code cannot be empty";
    } else {
      if (response.Req.StatusCode == '100') {
        state = TransactionState.TRYING;
      }
      if (response.Req.StatusCode == '180') {
        state = TransactionState.CALLING;
      }
      if (response.Req.StatusCode == '200') {
        state = TransactionState.ACCEPTED;
      }
    }
  }
}
