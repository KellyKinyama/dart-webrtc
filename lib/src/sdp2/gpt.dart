import 'dart:io';

import 'interface.dart';

class SdpDecoder {
  static Sdp decode(String text) {
    final sdp = Sdp();
    final lines = text.split(RegExp(r'\r?\n')).where((line) => line.trim().isNotEmpty);
    String? currentMedia;
    for (final line in lines) {
      final parts = line.split('=');
      if (parts.length != 2) continue;
      final prefix = parts[0];
      final value = parts[1];

      switch (prefix) {
        case 'v':
          sdp.protocolVersion = int.tryParse(value);
          break;
        case 'o':
          final oParts = value.split(RegExp(r'\s+'));
          if (oParts.length >= 6) {
            sdp.origin = SdpOrigin(
              oParts[0],
              oParts[1],
              int.tryParse(oParts[2]) ?? 0,
              _parseInternetAddressType(oParts[3]),
              _parseInternetAddressType(oParts[4]),
              oParts[5],
            );
          }
          break;
        case 's':
          sdp.sessionName = value;
          break;
        case 'i':
          sdp.sessionInformation = value;
          break;
        case 'u':
          sdp.uri = value;
          break;
        case 'e':
          sdp.emailAddress = value;
          break;
        case 'p':
          sdp.phoneNumber = value;
          break;
        case 't':
          final tParts = value.split(RegExp(r'\s+'));
          if (tParts.length >= 2) {
            final timing = SdpTiming(
              int.tryParse(tParts[0]) ?? 0,
              int.tryParse(tParts[1]) ?? 0,
            );
            sdp.timing ??= [];
            sdp.timing!.add(timing);
          }
          break;
        case 'r':
          final rParts = value.split(RegExp(r'\s+'));
          if (rParts.length >= 2) {
            final repeat = SdpRepeatTimes(
              int.tryParse(rParts[0]) ?? 0,
              int.tryParse(rParts[1]) ?? 0,
              rParts.length > 2
                  ? rParts.sublist(2).map((e) => int.tryParse(e) ?? 0).toList()
                  : [],
            );
            sdp.repeat ??= [];
            sdp.repeat!.add(repeat);
          }
          break;
        case 'k':
          final methodValue = value.split(':');
          final methodName = methodValue[0].trim();
          final method = Method.values.firstWhere(
              (m) => m.name == methodName,
              orElse: () => Method.prompt);
          final key = methodValue.length > 1 ? methodValue[1] : null;
          sdp.encryptionKeys ??= [];
          sdp.encryptionKeys!.add(SdpEncryptionKey(method, key));
          break;
        case 'a':
          final aParts = value.split(':');
          final attributeName = aParts[0].trim();
          final attributeValue = aParts.length > 1 ? aParts.sublist(1).join(':') : null;

          sdp.attributes ??= {};
          sdp.attributes![attributeName] = SdpAttribute(attributeName, attributeValue);
          break;

        case 'm':
          // Add stub for media parsing – assume this exists in SdpMediaSection
          currentMedia = value;
          sdp.media ??= [];
          sdp.media!.add(SdpMediaSection.fromLine(value));
          break;
        // You can handle other fields like 'b=', 'c=', 'a=group:' here as needed.
      }
    }
    return sdp;
  }

  static InternetAddressType? _parseInternetAddressType(String s) {
    switch (s.toUpperCase()) {
      case 'IP4':
        return InternetAddressType.IPv4;
      case 'IP6':
        return InternetAddressType.IPv6;
      default:
        return null;
    }
  }
}

class SdpAttribute {
  final String name;
  final String? value;
  SdpAttribute(this.name, this.value);
}

class SdpMediaSection {
  final String mediaLine;
  SdpMediaSection(this.mediaLine);

  static SdpMediaSection fromLine(String line) {
    return SdpMediaSection(line);
  }
}
// class SdpOrigin {
//   final String username;
//   final String sessionId;
//   final int sessionVersion;
//   final InternetAddressType? netType;
//   final InternetAddressType? addrType;
//   final String unicastAddress;

//   SdpOrigin(this.username, this.sessionId, this.sessionVersion, this.netType, this.addrType, this.unicastAddress);
// }