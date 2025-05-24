class SessionDescription {
  String version;
  Origin origin;
  String? sessionName;
  String? information;
  String? uri;
  List<String> emails;
  List<String> phones;
  Connection? connection;
  List<Bandwidth> bandwidths;
  List<TimeField> timeFields;
  Key? key;
  SessionAttributes attributes;
  List<MediaDescription> mediaDescription;
}

class Origin {
  username: string;
  sessId: string;
  sessVersion: string;
  nettype: string;
  addrtype: string;
  unicastAddress: string;
}

class Repeat {
  String repeatInterval;
  List<String> typedTimes;
}
class Time{
  String startTime;
  String stopTime;
}
class ZoneAdjustment {
  String time;
  String typedTime;
  bool back;
}

class TimeField {
  Time time;
  List<Repeat> repeats;
  List<ZoneAdjustment>? zoneAdjustments;
}

class Media {
  String mediaType: string;
  String port: string;
  List<String> protos;
  List<String> fmts;
}

class Connection {
  String nettype;
  String addrtype;
  String address;
}

class Bandwidth {
  String bwtype;
  String bandwidth;
}

enum Key {
  prompt,
  clear,
  base64,
  uri,
}

extension KeyExtension on Key {
  String get value {
    switch (this) {
      case Key.prompt:
        return 'prompt';
      case Key.clear:
        return 'clear:';
      case Key.base64:
        return 'base64:';
      case Key.uri:
        return 'uri:';
    }
  }

  static Key? fromString(String input) {
    switch (input) {
      case 'prompt':
        return Key.prompt;
      case 'clear:':
        return Key.clear;
      case 'base64:':
        return Key.base64;
      case 'uri:':
        return Key.uri;
      default:
        return null;
    }
  }
}

class Attribute {
  bool? ignored;
  String attField;
  String? attValue;
  String _cur;
}

class MediaDescription {
  Media media;
  String? information;
  List<Connection> connections;
  List<Bandwidth> bandwidths;
  Key? key;
  MediaAttributes attributes;
}

class Record {
  RECORD_TYPE type;
  String value: string;
  num cur;
  num line;
}
