const CR = "\u000D";
const LF = "\u000A";
const NUL = "\u0000";
const CRLF = "$CR$LF";
const SP = "\u0020";

enum RECORD_TYPE {
  VERSION("v"),
  ORIGIN("o"),
  SESSION_NAME("s"),
  INFORMATION("i"),
  URI("u"),
  EMAIL("e"),
  PHONE("p"),
  CONNECTION("c"),
  BANDWIDTH("b"),
  TIME("t"),
  REPEAT("r"),
  ZONE_ADJUSTMENTS("z"),
  KEY("k"),
  ATTRIBUTE("a"),
  MEDIA("m");

  const RECORD_TYPE(this.value);
  final String value;
}
