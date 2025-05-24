class SipMessageHeaders {
  SipMessageHeaders() {}

  static String VIA = "Via";
  static String FROM = "From";
  static String TO = "To";
  static String CALL_ID = "Call-ID";
  static String CSEQ = "CSeq";
  static String CONTACT = "Contact";
  static String CONTENT_LENGTH = "Content-Length";

  static String HEADERS_DELIMETER = "\r\n";
  static String UNAUTHORIZED = "SIP/2.0 401 Unauthorized";
}
