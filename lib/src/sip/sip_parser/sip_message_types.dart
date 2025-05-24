class SipMessageTypes {
  SipMessageTypes() {}

  static String REGISTER = "REGISTER";
  static String INVITE = "INVITE";
  static String CANCEL = "CANCEL";
  static String REQUEST_TERMINATED = "SIP/2.0 487 Request Terminated";
  static String TRYING = "SIP/2.0 100 Trying";
  static String RINGING = "SIP/2.0 180 Ringing";
  static String BUSY = "SIP/2.0 486 Busy Here";
  static String UNAVAIALBLE = "SIP/2.0 480 Temporarily Unavailable";
  static String OK = "SIP/2.0 200 OK";
  static String ACK = "ACK";
  static String BYE = "BYE";
  static String NOT_FOUND = "SIP/2.0 404 Not Found";
  static String UNAUTHORIZED = "SIP/2.0 401 Unauthorized";

  static String NOT_IMPLEMENTED = "SIP/2.0 501 Not Implemented";
}
